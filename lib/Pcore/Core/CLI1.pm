package Pcore::Core::CLI1;

use Pcore qw[-class];
use Getopt::Long qw[];
use Pcore::Core::CLI::Opt;

has class => ( is => 'ro', isa => Str, required => 1 );
has cmd_path => ( is => 'ro', isa => ArrayRef, default => sub { [] } );

has cmd => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has opt => ( is => 'lazy', isa => HashRef,  init_arg => undef );

has is_cmd     => ( is => 'lazy', isa => Bool,    init_arg => undef );
has _cmd_index => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

sub _build_cmd ($self) {
    my $cmd = [];

    my $class = $self->class;

    if ( $class->can('cli_cmd') && defined( my $cli_cmd = $class->cli_cmd ) ) {
        my @classes;

        if ( !ref $cli_cmd ) {
            my $ns = $cli_cmd;

            my $ns_path = $ns =~ s[::][/]smgr;

            for (@INC) {
                next if ref;

                my $path = $_ . q[/] . $ns_path;

                next if !-d $path;

                opendir my $dh, $path || die qq[can't opendir $path: $!];

                while ( my $fn = readdir $dh ) {
                    next if substr( $fn, 0 ) eq q[.];

                    if ( $fn =~ /\A(.+)[.]pm\z/sm && -f "$path/$fn" ) {
                        push @classes, $ns . q[::] . $1;
                    }
                }

                closedir $dh || die;
            }
        }
        else {
            @classes = $cli_cmd->@*;
        }

        for my $class (@classes) {
            $class = P->class->load($class);

            if ( $class->can('does') && $class->does('Pcore::Core::CLI::Cmd') ) {
                push $cmd->@*, $class;
            }
        }
    }

    return $cmd;
}

sub _build_opt ($self) {
    my $opt = {};

    my $index = {};

    my $class = $self->class;

    if ( $class->can('cli_opt') && defined( my $cli_opt = $class->cli_opt ) ) {
        for my $name ( keys $cli_opt->%* ) {
            die qq[Option "$name" is duplicated] if exists $index->{$name};

            $opt->{$name} = Pcore::Core::CLI::Opt->new( { $cli_opt->{$name}->%*, name => $name } );    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

            $index->{$name} = 1;

            if ( $opt->{$name}->short ) {
                die qq[Short name "@{[$opt->{$name}->short]}" for option "$name" is duplicated] if exists $index->{ $opt->{$name}->short };

                $index->{ $opt->{$name}->short } = 1;
            }
        }
    }

    return $opt;
}

sub _build__cmd_index ($self) {
    my $index = {};

    for my $class ( $self->cmd->@* ) {
        for my $cmd ( $self->_get_class_cmd($class)->@* ) {
            die qq[Command "$cmd" is duplicated] if exists $index->{$cmd};

            $index->{$cmd} = $class;
        }
    }

    return $index;
}

sub _build_is_cmd ($self) {
    return $self->_cmd_index->%* ? 1 : 0;
}

sub run ( $self, $argv ) {
    if ( $self->is_cmd ) {
        return $self->_parse_cmd($argv);
    }
    else {
        return $self->_parse_opt($argv);
    }
}

sub _parse_cmd ( $self, $argv ) {
    my $res = {
        cmd  => undef,
        opt  => {},
        rest => undef,
    };

    my $parser = Getopt::Long::Parser->new(
        config => [    #
            'no_auto_abbrev',
            'no_getopt_compat',
            'gnu_compat',
            'no_require_order',
            'permute',
            'bundling',
            'no_ignore_case',
            'pass_through',
        ]
    );

    $parser->getoptionsfromarray(
        $argv // [],
        $res->{opt},
        'help|h|?',
        'version',
        '<>' => sub ($arg) {
            if ( !$res->{cmd} && substr( $arg, 0, 1 ) ne q[-] ) {
                $res->{cmd} = $arg;
            }
            else {
                push $res->{rest}->@*, $arg;
            }

            return;
        }
    );

    push $res->{rest}->@*, $argv->@* if defined $argv && $argv->@*;

    if ( $res->{opt}->{version} ) {
        return $self->help_version;
    }
    elsif ( !defined $res->{cmd} ) {
        if ( $res->{opt}->{help} ) {
            return $self->help;
        }
        else {
            return $self->help_usage;
        }
    }
    else {
        my $possible_commands = [];

        my @index = keys $self->_cmd_index->%*;

        for my $cmd_name (@index) {
            push $possible_commands->@*, $cmd_name if index( $cmd_name, $res->{cmd} ) == 0;
        }

        if ( !$possible_commands->@* ) {
            return $self->help_usage( [qq[command "$res->{cmd}" is unknown]] );
        }
        elsif ( $possible_commands->@* > 1 ) {
            return $self->help_error( qq[command "$res->{cmd}" is ambiguous:$LF  ] . join q[ ], $possible_commands->@* );
        }
        else {
            unshift $res->{rest}->@*, '--help' if $res->{opt}->{help};

            my $class = $self->_cmd_index->{ $possible_commands->[0] };

            push $self->cmd_path->@*, $self->_get_class_cmd($class)->[0];

            return __PACKAGE__->new( { class => $class, cmd_path => $self->cmd_path } )->run( $res->{rest} );
        }
    }
}

sub _parse_opt ( $self, $argv ) {
    my $res = {
        error => undef,
        opt   => {},
        arg   => undef,
        rest  => undef,
    };

    # build cli spec for Getopt::Long
    my $cli_spec = [];

    for my $opt ( values $self->opt->%* ) {
        push $cli_spec->@*, $opt->getopt_spec;
    }

    my $parser = Getopt::Long::Parser->new(
        config => [    #
            'no_auto_abbrev',
            'no_getopt_compat',
            'gnu_compat',
            'no_require_order',
            'permute',
            'bundling',
            'no_ignore_case',
            'no_pass_through',
        ]
    );

    {
        no warnings qw[redefine];

        local *CORE::GLOBAL::warn = sub {
            push $res->{error}->@*, join q[], @_;

            $res->{error}->[-1] =~ s/\n\z//sm;

            return;
        };

        $parser->getoptionsfromarray(
            $argv // [],
            $res->{opt},
            $cli_spec->@*,
            'version',
            'help|h|?',
            '<>' => sub ($arg) {
                push $res->{arg}->@*, $arg;

                return;
            }
        );

        push $res->{rest}->@*, $argv->@* if defined $argv && $argv->@*;
    }

    if ( $res->{opt}->{version} ) {
        return $self->help_version;
    }
    elsif ( $res->{opt}->{help} ) {
        return $self->help;
    }
    elsif ( $res->{error} ) {
        return $self->help_usage( $res->{error} );
    }

    # post-process options
    for my $opt ( values $self->opt->%* ) {
        my $name = $opt->name;

        if ( $opt->required ) {
            if ( !exists $res->{opt}->{$name} ) {
                if ( defined $opt->default ) {
                    $res->{opt}->{$name} = $opt->default;
                }
                else {
                    return $self->help_usage( [qq[option "$name" is required]] );
                }
            }
        }

        next if $opt->is_bool;

        if ( exists $res->{opt}->{$name} && ( $opt->type eq '-e' || $opt->type eq '-d' || $opt->type eq '-f' ) ) {
            my $vals = ref $res->{opt}->{$name} eq 'ARRAY' ? $res->{opt}->{$name} : ref $res->{opt}->{$name} eq 'HASH' ? [ values $res->{opt}->{$name}->%* ] : [ $res->{opt}->{$name} ];

            for my $val ( $vals->@* ) {
                if ( $opt->type eq '-e' ) {
                    return $self->help_usage( [qq[option "$name" path "$val" is not exists]] ) if !-e $val;
                }
                elsif ( $opt->type eq '-d' ) {
                    return $self->help_usage( [qq[option "$name" dir "$val" is not exists]] ) if !-d $val;
                }
                elsif ( $opt->type eq '-f' ) {
                    return $self->help_usage( [qq[option "$name" file "$val" is not exists]] ) if !-f $val;
                }
            }
        }
    }

    # validate cli
    my $class = $self->class;

    if ( $class->can('cli_validate') && defined( my $error_msg = $class->cli_validate( $res->{opt}, $res->{arg}, $res->{rest} ) ) ) {
        return $self->help_error($error_msg);
    }

    # run
    if ( $class->can('cli_run') ) {
        return $class->cli_run($res);
    }
    else {
        return $res;
    }
}

sub _get_class_cmd ( $self, $class = undef ) {
    $class //= $self->class;

    if ( $class->can('cli_name') && ( my $cmd = $class->cli_name ) ) {
        return ref $cmd ? $cmd : [$cmd];
    }
    else {
        return [ lc $class =~ s/\A.*:://smr ];
    }
}

# HELP
sub _help_class_abstract ( $self, $class = undef ) {
    my $abstract;

    $class //= $self->class;

    if ( $class->can('cli_abstract') ) {
        $abstract = $class->cli_abstract;
    }

    if ( !defined $abstract ) {
        my $path;

        if ( $class eq 'main' ) {
            $path = $PROC->{SCRIPT_PATH};
        }
        else {
            $path = $INC{ $class =~ s[::][/]smgr . '.pm' };
        }

        my $content = P->file->read_bin($path);

        if ( $content->$* =~ m[=head1\s+NAME\s*$class\s*-\s*([^\n]+)]smi ) {
            $abstract = $1;
        }
    }

    $abstract //= q[];

    $abstract =~ s/\n+\z//sm;

    return $abstract;
}

# TODO add arguments, if present
sub _help_usage_string ($self) {
    my $usage = join q[ ], P->path( $PROC->{SCRIPT_NAME} )->filename, $self->cmd_path->@*;

    if ( $self->is_cmd ) {
        $usage .= ' [COMMAND] [OPTION]...';
    }
    else {
        $usage .= q[ [OPTION]... [ARGUMENTS]...];

        # TODO add arguments specification, if needed
        if (0) {
            $usage .= q[ [ARGUMENTS]...];
        }
    }

    return $usage;
}

sub _help_alias ($self) {
    my $cmd = $self->_get_class_cmd;

    shift $cmd->@*;

    if ( $cmd->@* ) {
        return 'aliases: ' . join q[ ], sort $cmd->@*;
    }
    else {
        return q[];
    }
}

sub _help ($self) {
    my $help;

    my $class = $self->class;

    if ( $class->can('cli_help') ) {
        $help = $class->cli_help;

        if ($help) {
            $help =~ s/^/    /smg;

            $help =~ s/\n+\z//sm;
        }
    }

    return $help // q[];
}

sub _help_usage ($self) {
    my $help;

    my $list = {};

    if ( $self->is_cmd ) {
        $help = 'list of commands:' . $LF . $LF;

        for my $class ( $self->cmd->@* ) {
            $list->{ $self->_get_class_cmd($class)->[0] } = $self->_help_class_abstract($class);
        }
    }
    else {
        $help = 'options ([+] - can be repeated, [!] - is required):' . $LF . $LF;

        for my $opt ( sort { $a->name cmp $b->name } values $self->opt->%* ) {
            $list->{ $opt->spec } = $opt->desc // q[];
        }
    }

    return q[] if !$list->%*;

    my $max_key_len = 10;

    for ( keys $list->%* ) {
        $max_key_len = length if length > $max_key_len;
    }

    $help .= join $LF, map { sprintf( " %-${max_key_len}s    ", $_ ) . $list->{$_} } sort keys $list->%*;

    return $help // q[];
}

sub _help_footer ($self) {
    return q[(global options: --help, -h, -?, --version)];
}

sub help ($self) {
    say $self->_help_usage_string, $LF;

    if ( my $alias = $self->_help_alias ) {
        say $alias, $LF;
    }

    if ( my $abstract = $self->_help_class_abstract ) {
        say $abstract, $LF;
    }

    if ( my $help = $self->_help ) {
        say $help, $LF;
    }

    if ( my $help_usage = $self->_help_usage ) {
        say $help_usage, $LF;
    }

    say $self->_help_footer, $LF;

    exit 2;
}

sub help_usage ( $self, $invalid_options = undef ) {
    if ($invalid_options) {
        for ( $invalid_options->@* ) {
            say;
        }

        print $LF;
    }

    say $self->_help_usage_string, $LF;

    if ( my $abstract = $self->_help_class_abstract ) {
        say $abstract, $LF;
    }

    if ( my $help_usage = $self->_help_usage ) {
        say $help_usage, $LF;
    }

    say $self->_help_footer, $LF;

    exit 2;
}

# TODO
sub help_version ($self) {
    say 'VERSION HELP';

    exit 2;
}

sub help_error ( $self, $msg ) {
    say $msg, $LF if defined $msg;

    exit 2;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 75, 78, 108, 173,    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 208, 263, 280, 422,  │                                                                                                                │
## │      │ 427, 431, 435        │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 197                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_parse_opt" with high complexity score (30)                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 325, 451, 479        │ NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "abstract"                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 525                  │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 529 does not match the package declaration      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
