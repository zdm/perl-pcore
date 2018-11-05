package Pcore::Src1;

use Pcore -class, -const, -res, -export, -ansi;
use Pcore::Util::Scalar qw[is_path is_plain_arrayref is_plain_hashref];
use Pcore::Util::Text qw[encode_utf8 decode_eol lcut_all rcut_all rtrim_multi remove_bom];
use Pcore::Util::Digest qw[md5_hex];

has path    => ();    # Scalar, ArrayRef
has data    => ();
has type    => ();    # ArrayRef[ Enum ['css', 'html', 'js', 'json', 'perl']], list of types to process, used if path is directory
has ignore  => 1;     # Bool, ignore unsupported file types
has filter  => ();    # HashRef, additional filter arguments
has dry_run => ();    # Bool, if true - do not write results to the source path
has report  => ();    # print report

const our $SRC_DECOMPRESS => 1;
const our $SRC_COMPRESS   => 2;
const our $SRC_OBFUSCATE  => 3;
const our $SRC_COMMIT     => 4;

const our $STATUS_REASON => {
    200 => 'OK',
    201 => 'Warning',
    202 => 'File skipped',
    404 => 'File not found',
    500 => 'Error',
    510 => 'Params error',
};

const our $STATUS_COLOR => {
    200 => $BOLD . $GREEN,
    201 => $YELLOW,
    404 => $BOLD . $RED,
    500 => $BOLD . $RED,
};

# TODO do we need this???
our $EXPORT = { ACTION => [qw[$SRC_DECOMPRESS $SRC_COMPRESS $SRC_OBFUSCATE]] };

# TODO do not use class, use functional interface???
# TODO CLI mode

# CLI
sub CLI ($self) {
    return {
        help => <<'TXT',
- convert to uft-8;
- strip BOM header;
- convert tabs to spaces;
- trim trailing spaces;
- trim trailing empty strings;
- convert line endings to unix style (\x0A);

Exit codes:

    0 - source is valid;
    1 - run-time error;
    2 - params error;
    3 - source error;
TXT
        opt => {
            action => {
                desc => <<'TXT',
action to perform:
    decompress   unpack sources, DEFAULT;
    compress     pack sources, comments will be deleted;
    obfuscate    applied only for javascript and embedded javascripts, comments will be deleted;
    commit       SCM commit hook
TXT
                isa     => [ $SRC_DECOMPRESS, $SRC_COMPRESS, $SRC_OBFUSCATE, $SRC_COMMIT ],
                default => $SRC_DECOMPRESS,
            },
            type => {
                desc => 'define source files to process. Mandatory, if <source> is a directory. Recognized types: perl, html, css, js',
                isa  => [qw[perl html css js]],
            },
            stdin_files => {
                short   => undef,
                desc    => 'read list of filenames from STDIN',
                default => 0,
            },
            filename => {
                desc => 'mandatory, if read source content from STDIN',
                type => 'Str',
            },
            no_critic => {
                short   => undef,
                desc    => 'skip Perl::Critic filter',
                default => 0,
            },
            dry_run => {
                short   => undef,
                desc    => q[don't save changes],
                default => 0,
            },
            pause => {
                short   => undef,
                desc    => q[don't close console after script finished],
                default => 0,
            },
        },
        arg => [
            path => {
                isa => 'Path',
                min => 0,
            }
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    P->file->chdir( $ENV->{START_DIR} );

    my $exit_code = eval {
        my $src = Pcore::Src->new( {
            interactive => 1,
            path        => $arg->{path},
            action      => $opt->{action},
            stdin_files => $opt->{stdin_files},
            no_critic   => $opt->{no_critic},
            dry_run     => $opt->{dry_run},
            ( exists $opt->{type}     ? ( type     => $opt->{type} )     : () ),
            ( exists $opt->{filename} ? ( filename => $opt->{filename} ) : () ),
        } );

        $src->run;
    };

    if ($@) {
        say $@;

        return Pcore::Src::File->cfg->{EXIT_CODES}->{RUNTIME_ERROR};
    }

    if ( $opt->{pause} ) {
        print 'Press ENTER to continue...';
        <STDIN>;
    }

    exit $exit_code;
}

sub cfg ($self) {
    state $cfg = $ENV->{share}->read_cfg( 'Pcore', 'data', 'src.yaml' );

    return $cfg;
}

sub run ( $self, $action ) {

    # convert type to HashRef
    if ( defined $self->{type} && !is_plain_hashref $self->{type} ) {
        if ( is_plain_arrayref $self->{type} ) {
            $self->{type} = { map { $_ => undef } $self->{type}->@* };
        }
        else {
            $self->{type} = { $self->{type} => undef };
        }
    }

    my $res;

    # file content is provided
    if ( defined $self->{data} ) {

        # convert path
        my $path = $self->{path};
        $path = P->path($path) if !is_path $path;

        # get filter profile
        my $filter_profile = $self->_get_filter_profile( $path, $self->{data} );

        # ignore file
        return res [ 202, $STATUS_REASON ] if !defined $filter_profile;

        # process file
        $res = $self->_process_file( $action, $filter_profile, $path, $self->{data} );
    }

    # file content is not provided
    else {
        $res = $self->_process_files( $action, $self->{path} );
    }

    return $res;
}

# TODO fix prefix
sub _process_files ( $self, $action, $paths ) {
    my $total = res 200;

    my %tasks;

    # build absolute paths list
    for my $path ( is_plain_arrayref $paths ? $paths->@* : $paths ) {
        next if !defined $path;

        # convert path
        $path = P->path($path) if !is_path $path;
        $path->to_abs;

        # path is directory
        if ( -d $path ) {
            return res [ 510, 'Type must be specified in path is directory' ] if !defined $self->{type};

            # read dir
            for my $path ( ( $path->read_dir( abs => 1, max_depth => 0, is_dir => 0 ) // [] )->@* ) {

                # get filter profile
                if ( my $filter_profile = $self->_get_filter_profile($path) ) {
                    $tasks{$path} = [ $filter_profile, $path ];
                }
            }
        }

        # path is file
        else {

            # get filter profile
            if ( my $filter_profile = $self->_get_filter_profile($path) ) {
                $tasks{$path} = [ $filter_profile, $path ];
            }
        }
    }

    my ( $max_path_len, $prefix, $use_prefix );

    # find longest common prefix
    if ( $self->{report} ) {
        for my $task ( values %tasks ) {
            my $dirname = "$task->[1]->{dirname}/";

            if ( !defined $prefix ) {
                $prefix = $dirname;

                $max_path_len = length $task->[1];
            }
            else {
                $max_path_len = length $task->[1] if length $task->[1] > $max_path_len;

                if ( "$prefix\x00$dirname" =~ /^(.*).*\x00\1.*$/sm ) {
                    $prefix = $1;

                    $use_prefix = 1;
                }
            }
        }

        # find max. path length
        $max_path_len -= length $prefix if $use_prefix;
    }

    my $tbl;

    for my $path ( sort keys %tasks ) {
        my $res = $self->_process_file( $action, $tasks{$path}->@* );

        if ( $res != 202 ) {
            if ( $res->{status} > $total->{status} ) {
                $total->{status} = $res->{status};
                $total->{reason} = $STATUS_REASON->{ $total->{status} };
            }

            $total->{ $res->{status} }++;
            $total->{modified}++ if $res->{is_modified};

            $self->_report_file( \$tbl, $use_prefix ? substr $path, length $prefix : $path, $res, $max_path_len ) if $self->{report};
        }
    }

    print $tbl->finish if defined $tbl;

    $self->_report_total($total) if $self->{report};

    return $total;
}

sub _process_file ( $self, $action, $filter_profile, $path = undef, $data = undef ) {
    my $res = res [ 200, $STATUS_REASON ],
      is_modified => 0,
      in_size     => 0,
      out_size    => 0,
      size_delta  => 0;

    my $write_data;

    # read file
    if ( !defined $data ) {
        if ( defined $path && -f $path ) {
            $data = P->file->read_bin( $path->encoded )->$*;

            $write_data = 1;
        }

        # file not found
        else {
            $res->{status} = 404;
            $res->{reason} = $STATUS_REASON->{404};
            return $res;
        }
    }
    else {
        encode_utf8 $data;
    }

    $res->{in_size} = bytes::length $data;
    my $in_md5 = md5_hex $data;

    # run filter
    if ( my $filter_type = delete $filter_profile->{type} ) {

        # merge filter args
        $filter_profile->@{ keys $self->{filter}->%* } = values $self->{filter}->%* if defined $self->{filter};

        my $filter_res = P->class->load( $filter_type, ns => 'Pcore::Src1' )->new(
            $filter_profile->%*,
            file => $self,
            data => \$data,
        )->run($action);

        $res->{status} = $filter_res->{status};
        $res->{reason} = $filter_res->{reason};
    }

    # trim
    if ( $action == $SRC_DECOMPRESS ) {
        decode_eol $data;    # decode CRLF to internal \n representation

        lcut_all $data;      # trim leading horizontal whitespaces

        rcut_all $data;      # trim trailing horizontal whitespaces

        rtrim_multi $data;   # right trim each line

        $data =~ s/\t/    /smg;    # convert tabs to spaces

        $data .= $LF;
    }

    my $out_md5 = md5_hex $data;
    $res->{is_modified} = $in_md5 ne $out_md5;
    $res->{out_size}    = bytes::length $data;
    $res->{size_delta}  = $res->{out_size} - $res->{in_size};

    # write file
    if ($write_data) {
        if ( $res->{is_modified} && !$self->{dry_run} ) { P->file->write_bin( $path->encoded, $data ) }
    }
    else {
        $res->{data} = $data;
    }

    return $res;
}

sub _get_filter_profile ( $self, $path, $data = undef ) {
    my $cfg = $self->cfg;

    my $filter_profile;

    my $path_mime_tags = $path->mime_tags( defined $data ? \$data : 1 );

    for ( keys $cfg->{mime_tag}->%* ) { $filter_profile = $cfg->{mime_tag}->{$_} and last if exists $path_mime_tags->{$_} }

    # file type is known
    if ( defined $filter_profile ) {

        # file is filtered by the type filter and in ignore mode
        if ( defined $self->{type} && !exists $self->{type}->{ $filter_profile->{type} } && $self->{ignore} ) {
            return;
        }
        else {
            return { $filter_profile->%* };
        }
    }

    # filte type is unknown and in ignore mode
    elsif ( $self->{ignore} ) {
        return;
    }
    else {
        return {};
    }
}

sub _report_file ( $self, $tbl, $path, $res, $max_path_len ) {
    if ( !defined $tbl->$* ) {
        $tbl->$* = P->text->table(    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
            style    => 'compact',
            top_line => 1,
            cols     => [
                path => {
                    width => $max_path_len + 2,
                    align => -1,
                },
                severity => {
                    width => 25,
                    align => 1,
                },
                size => {
                    width => 10,
                    align => 1,
                },
                size_delta => {
                    title => 'SIZE DELTA',
                    width => 16,
                    align => 1,
                },
                modified => {
                    width => 12,
                    align => 1,
                },
            ],
        );

        print $tbl->$*->render_header;
    }

    my @row;

    # path
    push @row, $path;

    # severity
    push @row, $STATUS_COLOR->{ $res->{status} } . uc( $res->{reason} ) . $RESET;

    # size
    push @row, $res->{out_size};

    # size delta
    if ( !$res->{size_delta} ) {
        push @row, ' - ';
    }
    elsif ( $res->{size_delta} > 0 ) {
        push @row, $BOLD . $RED . "+$res->{size_delta} bytes" . $RESET;
    }
    else {
        push @row, $BOLD . $GREEN . "$res->{size_delta} bytes" . $RESET;
    }

    # modified
    push @row, ( $res->{is_modified} ? $BOLD . $WHITE . $ON_RED . ' modified ' . $RESET : ' - ' );

    print $tbl->$*->render_row( \@row );

    return;
}

sub _report_total ( $self, $total ) {
    return if !defined $total;

    my $tbl = P->text->table(
        style => 'full',
        cols  => [
            type => {
                width => 16,
                align => 1,
            },
            count => {
                width => 10,
                align => -1,
            },
        ],
    );

    print $tbl->render_header;

    for my $status ( 200, 201, 500, 404 ) {
        print $tbl->render_row( [ $STATUS_COLOR->{$status} . uc( $STATUS_REASON->{$status} ) . $RESET, $STATUS_COLOR->{$status} . ( $total->{$status} // 0 ) . $RESET ] );
    }

    print $tbl->render_row( [ 'MODIFIED', $total->{modified} // 0 ] );

    print $tbl->finish;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 189                  | Subroutines::ProhibitExcessComplexity - Subroutine "_process_files" with high complexity score (26)            |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 278, 386             | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 241                  | ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 315                  | ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src1

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
