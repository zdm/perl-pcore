package Pcore::Src::Filter::Perl;

use Pcore qw[-class];
use Clone qw[];

with qw[Pcore::Src::Filter];

sub decompress ( $self, % ) {
    my %args = (
        perl_verbose => 0,
        perl_tidy    => q[],
        perl_critic  => 0,
        @_[ 1 .. $#_ ],
    );

    my $err      = q[];
    my $log      = q[];
    my $severity = 0;

    # format subroutine signatures
    $self->buffer->$* =~ s/sub\s+(?:([[:alnum:]_]+)\s*)?[(]\s*([^)]*)\s*[)]/_format_sub_signature($1, $2)/smge;

    # format heredocs
    $self->_format_heredoc;

    require Perl::Tidy;

    my $perltidy_argv = $self->src_cfg->{PERLTIDY};

    $perltidy_argv .= q[ ] . $self->dist_cfg->{PERLTIDY} if $self->dist_cfg->{PERLTIDY};

    $perltidy_argv .= q[ ] . $args{perl_tidy} if $args{perl_tidy};

    $perltidy_argv .= ' --logfile-gap=50' if $args{perl_verbose};

    Perl::Tidy::perltidy(
        source      => $self->buffer,
        destination => $self->buffer,
        stderr      => \$err,
        errorfile   => \$err,
        logfile     => \$log,            # for verbose output only
        argv        => $perltidy_argv,
    );

    my $error_log;

    if ($err) {
        $severity = $self->src_cfg->{SEVERITY}->{PERLTIDY};

        $error_log = qq[PerlTidy:\n$err];

        $error_log .= qq[\n$log] if $args{perl_verbose};
    }
    elsif ( my $perl_critic_profile_name = $self->_get_perlcritic_profile_name( $args{perl_critic} ) ) {    # run perlcritic ONLY if no perltidy errors detected
        require Perl::Critic;

        # create table object
        my $t = P->text->table( { row_line => 0 } );
        $t->set_cols( 'Sev.', 'Lines', 'Policy' );
        $t->set_col_width( 'Lines', 20, 1 );
        $t->align_col( 'Lines', 'left' );
        $t->set_col_width( 'Policy', 110, 1 );

        # index violations
        if ( my @violations = $self->_get_perlcritic_object($perl_critic_profile_name)->critique( $self->buffer ) ) {
            my $violations;

            for my $v (@violations) {
                my $policy = $v->policy =~ s/\APerl::Critic::Policy:://smr;

                my $desc_md5 = P->digest->md5_hex( $v->description );

                if ( $violations->{$policy} ) {
                    $violations->{$policy}->{line}->{ $v->line_number }++;

                    $violations->{$policy}->{first_line} = $v->line_number if $violations->{$policy}->{first_line} > $v->line_number;

                    if ( $violations->{$policy}->{desc}->{$desc_md5} ) {
                        push $violations->{$policy}->{desc}->{$desc_md5}->{line}->@*, $v->line_number;
                    }
                    else {
                        $violations->{$policy}->{desc}->{$desc_md5} = {
                            text => $v->description,
                            line => [ $v->line_number ],
                        };
                    }
                }
                else {
                    $severity = $v->severity if $v->severity > $severity;
                    $violations->{$policy}->{severity} = $v->severity;
                    $violations->{$policy}->{desc}->{$desc_md5} = {
                        text => $v->description,
                        line => [ $v->line_number ],
                    };
                    $violations->{$policy}->{diag} = $v->diagnostics;
                    $violations->{$policy}->{line}->{ $v->line_number }++;
                    $violations->{$policy}->{first_line} = $v->line_number;
                }
            }

            # create table
            # sorting violations by descending severity, ascending first line then by policy text
            for my $v ( sort { $violations->{$a}->{severity} != $violations->{$b}->{severity} ? $violations->{$b}->{severity} <=> $violations->{$a}->{severity} : $violations->{$a}->{first_line} != $violations->{$b}->{first_line} ? $violations->{$a}->{first_line} <=> $violations->{$b}->{first_line} : $a cmp $b } keys $violations ) {
                my $policy = $v;

                if ( keys $violations->{$v}->{desc} > 1 ) {    # multiple violations with different descriptions
                    $t->add_row( $violations->{$v}->{severity}, q[], $policy );

                    # sorting descriptions by ascending first line number, then by description text
                    for my $desc ( sort { $violations->{$v}->{desc}->{$a}->{line}->[0] != $violations->{$v}->{desc}->{$b}->{line}->[0] ? $violations->{$v}->{desc}->{$a}->{line}->[0] <=> $violations->{$v}->{desc}->{$b}->{line}->[0] : $violations->{$v}->{desc}->{$a}->{text} cmp $violations->{$v}->{desc}->{$b}->{text} } keys $violations->{$v}->{desc} ) {
                        $t->add_row( q[], join( q[, ], sort { $a <=> $b } $violations->{$v}->{desc}->{$desc}->{line}->@* ), qq[* $violations->{$v}->{desc}->{$desc}->{text}] );
                    }
                }
                else {                                         # single violation
                    $policy .= qq[ - $violations->{$v}->{desc}->{[keys $violations->{$v}->{desc}->%*]->[0]}->{text}];

                    $t->add_row( $violations->{$v}->{severity}, join( q[, ], sort { $a <=> $b } keys $violations->{$v}->{line} ), $policy );
                }

                # add diagnostic
                $t->add_row( q[], q[], qq[\nDiagnostics:\n] . $t->protect_spaces( $violations->{$v}->{diag} ) ) if $args{perl_verbose} && $violations->{$v}->{severity} >= $self->src_cfg->{SEVERITY_RANGE}->{ERROR};

                # add table row line
                $t->add_row_line;
            }

            $error_log = qq[PerlCritic profile "$perl_critic_profile_name" policy violations:\n];

            $error_log .= $t->render;
        }
    }

    $self->_append_log($error_log);

    return $severity;
}

sub compress ( $self, % ) {
    my %args = (
        perl_compress             => 0,    # 0 - Perl::Stripper, 1 - Perl::Strip
        perl_compress_end_section => 0,    # preserve __END__ section
        perl_strip_maintain_linum => 1,
        perl_strip_ws             => 1,
        perl_strip_comment        => 1,
        perl_strip_pod            => 1,
        @_[ 1 .. $#_ ],
    );

    require BerkeleyDB;

    state $cache;

    if ( !$cache ) {
        tie my %cache, 'BerkeleyDB::Hash', -Filename => $PROC->{SYS_TEMP_DIR} . 'perl_compress.bdb', -Flags => BerkeleyDB::DB_CREATE();

        $cache = \%cache;
    }

    # cut __END__ or __DATA__ sections
    my $data_section = q[];

    if ( $self->buffer->$* =~ s/(\n__(END|DATA)__(?:\n.*|))\z//sm ) {
        $data_section = $1 if $args{perl_compress_end_section} || $2 eq 'DATA';
    }

    my $md5 = P->digest->md5_hex( $self->buffer->$* );

    my $key;

    if ( $args{perl_compress} ) {
        $key = 'compress_' . $md5;

        if ( !exists $cache->{$key} ) {
            require Perl::Strip;

            my $transform = Perl::Strip->new( optimise_size => 1, keep_nl => 0 );

            $cache->{$key} = P->text->rcut_all( $transform->strip( $self->buffer->$* ) );
        }
    }
    else {
        $key = 'strip_' . $args{perl_strip_maintain_linum} . $args{perl_strip_ws} . $args{perl_strip_comment} . $args{perl_strip_pod} . $md5;

        if ( !exists $cache->{$key} ) {
            require Perl::Stripper;

            my $transform = Perl::Stripper->new(
                maintain_linum => $args{perl_strip_maintain_linum},    # keep line numbers unchanged
                strip_ws       => $args{perl_strip_ws},                # strip extra whitespace
                strip_comment  => $args{perl_strip_comment},
                strip_pod      => $args{perl_strip_pod},
                strip_log      => 0,                                   # strip Log::Any log statements
            );

            $cache->{$key} = P->text->rcut_all( $transform->strip( $self->buffer->$* ) );
        }
    }

    $self->buffer->$* = $cache->{$key} . $data_section;                ## no critic qw(Variables::RequireLocalizedPunctuationVars)

    return 0;
}

sub _append_log ( $self, $log ) {
    $self->cut_log;

    if ($log) {
        P->text->encode_utf8($log);

        $log = qq[-----SOURCE FILTER LOG BEGIN-----\n\n$log\n-----SOURCE FILTER LOG END-----\n];

        $log =~ s/^/## /smg;

        # insert log befor __END__ or __DATA__ token
        # or append to end end or src
        if ( $self->buffer->$* =~ /^__(END|DATA)__$/sm ) {
            my $section = $1;

            $self->buffer->$* =~ s/^__${section}__$/${log}__${section}__/sm;
        }
        else {
            $self->buffer->$* .= $LF . $log;
        }
    }

    return;
}

sub _get_perlcritic_profile_name ( $self, $profile ) {
    if ( $profile eq '1' ) {
        $profile = 0;

        for my $name ( keys $self->src_cfg->{PERLCRITIC} ) {
            next if !exists $self->src_cfg->{PERLCRITIC}->{$name}->{__autodetect__};

            if ( $self->src_cfg->{PERLCRITIC}->{$name}->{__autodetect__}->( $self->buffer->$* ) ) {
                $profile = $name;

                last;
            }
        }
    }

    return $profile;
}

sub _get_perlcritic_object ( $self, $name ) {
    state $perlcritic_object_cache = {};

    unless ( exists $perlcritic_object_cache->{$name} ) {
        my $get_profile = sub ($name) {
            my $profile;

            if ( $self->src_cfg->{PERLCRITIC}->{$name}->{__parent__} ) {
                $profile = P->hash->merge( __SUB__->( $self->src_cfg->{PERLCRITIC}->{$name}->{__parent__} ), $self->src_cfg->{PERLCRITIC}->{$name} );
            }
            else {
                $profile = Clone::clone( $self->src_cfg->{PERLCRITIC}->{$name} );
            }

            delete $profile->@{qw[__autodetect__ __parent__]};

            return $profile;
        };

        my $profile = $get_profile->($name);

        # convert profile to Perl::Critic format
        for my $policy ( keys $profile ) {
            if ( !$profile->{$policy} ) {
                delete $profile->{$policy};

                $profile->{ q[-] . $policy } = 0;
            }
        }

        $perlcritic_object_cache->{$name} = Perl::Critic->new(
            '-profile-strictness' => $Perl::Critic::Utils::Constants::PROFILE_STRICTNESS_FATAL,
            -profile              => $profile,
        );
    }

    return $perlcritic_object_cache->{$name};
}

sub _format_heredoc ($self) {

    # TODO PCORE-72
    # parse heredocs in $self->buffer
    # call correspondednt formatters

    return;
}

sub _format_sub_signature ( $sub_name, $sub_sign ) {
    my $res = q[sub ];

    $res .= $sub_name . q[ ] if $sub_name;

    my @signs = split /,/sm, $sub_sign;

    $res .= q[(];

    $res .= q[ ] if @signs > 1;

    my @formatted_signs = ();

    for my $sign (@signs) {
        P->text->trim($sign);

        next unless $sign;

        if ( ( my $eq_idx = index $sign, q[=] ) != -1 ) {
            my $val = $sign;

            my $var = substr $val, 0, $eq_idx, q[];

            substr $val, 0, 1, q[];

            P->text->trim($var);

            P->text->trim($val);

            $sign = qq[$var =];

            $sign .= qq[ $val] if $val;
        }

        push @formatted_signs, $sign;
    }

    $res .= join q[, ], @formatted_signs;

    $res .= q[ ] if @signs > 1;

    $res .= q[)];

    return $res;
}

sub cut_log ($self) {
    $self->buffer->$* =~ s/^## -----SOURCE FILTER LOG BEGIN-----.*?## -----SOURCE FILTER LOG END-----\n?//sm;    ## no critic qw(RegularExpressions::ProhibitComplexRegexes)

    P->text->rcut_all( $self->buffer->$* );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 8                    │ Subroutines::ProhibitExcessComplexity - Subroutine "decompress" with high complexity score (24)                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 154                  │ Miscellanea::ProhibitTies - Tied variable used                                                                 │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 103                  │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Filter::Perl

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
