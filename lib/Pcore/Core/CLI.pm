package Pcore::Core::CLI;

use Pcore qw[-class];
use Getopt::Long qw[];
use Pcore::Core::CLI::Opt;
use Pcore::Core::CLI::Arg;

has class => ( is => 'ro', isa => Str, required => 1 );
has cmd_path => ( is => 'ro', isa => ArrayRef, default => sub { [] } );

has cmd => ( is => 'lazy', isa => ArrayRef, init_arg => undef );
has opt => ( is => 'lazy', isa => HashRef,  init_arg => undef );
has arg => ( is => 'lazy', isa => ArrayRef, init_arg => undef );

has is_cmd     => ( is => 'lazy', isa => Bool,    init_arg => undef );
has _cmd_index => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

my $SCAN_DEPS = !$PROC->is_par && $PROC->dist && $PROC->dist->cfg->{dist}->{par} && exists $PROC->dist->cfg->{dist}->{par}->{ $PROC->{SCRIPT_NAME} };

sub _build_cmd ($self) {
    my $cmd = [];

    my $class = $self->class;

    if ( $class->can('cli_cmd') && ( my $cli_cmd = $class->cli_cmd ) ) {
        $cli_cmd = [$cli_cmd] if !ref $cli_cmd;

        my @classes;

        for my $cli_cmd_class ( $cli_cmd->@* ) {
            if ( substr( $cli_cmd_class, -2, 2 ) eq q[::] ) {
                my $ns = $cli_cmd_class;

                my $ns_path = $ns =~ s[::][/]smgr;

                for (@INC) {
                    next if ref;

                    my $path = $_ . q[/] . $ns_path;

                    next if !-d $path;

                    for my $fn ( P->file->read_dir( $path, full_path => 0 )->@* ) {
                        if ( $fn =~ /\A(.+)[.]pm\z/sm && -f "$path/$fn" ) {
                            push @classes, $ns . $1;
                        }
                    }
                }
            }
            else {
                push @classes, $cli_cmd_class;
            }
        }

        my $index;

        for my $class (@classes) {
            next if $index->{$class};

            $index->{$class} = 1;

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

    my $index = {
        help      => undef,
        h         => undef,
        q[?]      => undef,
        version   => undef,
        scan_deps => undef,
    };

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

sub _build_arg ($self) {
    my $args = [];

    my $index = {};

    my $class = $self->class;

    my $next_arg = 0;    # 0 - any, 1 - min = 0, 2 - no arg

    if ( $class->can('cli_arg') && defined( my $cli_arg = $class->cli_arg ) ) {
        for my $cfg ( $cli_arg->@* ) {
            die q[Can't have other arguments after slurpy argument] if $next_arg == 2;

            my $arg = Pcore::Core::CLI::Arg->new($cfg);

            die q[Can't have required argument after not mandatory argument] if $next_arg == 1 && $arg->min != 0;

            die qq[Argument "@{[$arg->name]}" is duplicated] if exists $index->{ $arg->name };

            if ( !defined $arg->max ) {
                $next_arg = 2;
            }
            elsif ( $arg->min == 0 ) {
                $next_arg = 1;
            }

            push $args->@*, $arg;

            $index->{ $arg->name } = 1;
        }
    }

    return $args;
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
    my $class = $self->class;

    # redirect, if defined
    if ( $class->can('cli_class') && ( my $cli_class = $class->cli_class ) ) {
        require $cli_class =~ s[::][/]smgr . '.pm';

        return __PACKAGE__->new( { class => $cli_class } )->run($argv);
    }

    # make a copy
    my @argv = $argv ? $argv->@* : ();

    if ( $self->is_cmd ) {
        return $self->_parse_cmd( \@argv );
    }
    else {
        return $self->_parse_opt( \@argv );
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
        $argv,
        $res->{opt},
        'help|h|?',
        'version',
        ( $SCAN_DEPS ? 'scan-deps' : () ),
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

    # process --scan-deps option
    require Pcore::Devel::ScanDeps if $SCAN_DEPS && $res->{opt}->{'scan-deps'};

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
        arg   => {},
        rest  => undef,
    };

    # build cli spec for Getopt::Long
    my $cli_spec = [];

    for my $opt ( values $self->opt->%* ) {
        push $cli_spec->@*, $opt->getopt_spec;
    }

    my $parser = Getopt::Long::Parser->new(
        config => [    #
            'auto_abbrev',
            'no_getopt_compat',    # do not allow + to start options
            'gnu_compat',
            'no_require_order',
            'permute',
            'bundling',
            'no_ignore_case',
            'no_pass_through',
        ]
    );

    my $parsed_args = [];

    {
        no warnings qw[redefine];

        local *CORE::GLOBAL::warn = sub {
            push $res->{error}->@*, join q[], @_;

            $res->{error}->[-1] =~ s/\n\z//sm;

            return;
        };

        $parser->getoptionsfromarray(
            $argv,
            $res->{opt},
            $cli_spec->@*,
            'version',
            'help|h|?',
            ( $SCAN_DEPS ? 'scan-deps' : () ),
            '<>' => sub ($arg) {
                push $parsed_args->@*, $arg;

                return;
            }
        );

        push $res->{rest}->@*, $argv->@* if defined $argv && $argv->@*;
    }

    # process --scan-deps option
    require Pcore::Devel::ScanDeps if $SCAN_DEPS && $res->{opt}->{'scan-deps'};

    if ( $res->{opt}->{version} ) {
        return $self->help_version;
    }
    elsif ( $res->{opt}->{help} ) {
        return $self->help;
    }
    elsif ( $res->{error} ) {
        return $self->help_usage( $res->{error} );
    }

    # validate options
    for my $opt ( values $self->opt->%* ) {
        if ( my $error_msg = $opt->validate( $res->{opt} ) ) {
            return $self->help_usage( [$error_msg] );
        }
    }

    # parse and validate args
    for my $arg ( $self->arg->@* ) {
        if ( my $error_msg = $arg->parse( $parsed_args, $res->{arg} ) ) {
            return $self->help_usage( [$error_msg] );
        }
    }

    return $self->help_usage( [qq[unexpected arguments]] ) if $parsed_args->@*;

    # validate cli
    my $class = $self->class;

    if ( $class->can('cli_validate') && defined( my $error_msg = $class->cli_validate( $res->{opt}, $res->{arg}, $res->{rest} ) ) ) {
        return $self->help_error($error_msg);
    }

    # store results globally
    %ARGV = $res->%*;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    # run
    if ( $class->can('cli_run') ) {
        return $class->cli_run( $res->{opt}, $res->{arg}, $res->{rest} );
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

sub _help_usage_string ($self) {
    my $usage = join q[ ], P->path( $PROC->{SCRIPT_NAME} )->filename, $self->cmd_path->@*;

    if ( $self->is_cmd ) {
        $usage .= ' [COMMAND] [OPTION]...';
    }
    else {
        $usage .= ' [OPTION]...' if $self->opt->%*;

        if ( $self->arg->@* ) {
            my @args;

            for my $arg ( $self->arg->@* ) {
                push @args, $arg->help_spec;
            }

            $usage .= q[ ] . join q[ ], @args;
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

# TODO try to get help from POD =head DESCRIPTION
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
            $list->{ $self->_get_class_cmd($class)->[0] } = [ $self->_get_class_cmd($class)->[0], $self->_help_class_abstract($class) ];
        }
    }
    else {
        $help = 'options ([+] - can be repeated, [!] - is required):' . $LF . $LF;

        for my $opt ( values $self->opt->%* ) {
            $list->{ $opt->name } = [ $opt->help_spec, $opt->desc // q[] ];
        }
    }

    return q[] if !$list->%*;

    my $max_key_len = 10;

    for ( values $list->%* ) {
        $max_key_len = length $_->[0] if length $_->[0] > $max_key_len;

        # remove \n from desc
        $_->[1] =~ s/\n+\z//smg;
    }

    my $desc_indent = $LF . q[    ] . ( q[ ] x $max_key_len );

    $help .= join $LF, map { sprintf( " %-${max_key_len}s   ", $list->{$_}->[0] ) . $list->{$_}->[1] =~ s/\n/$desc_indent/smgr } sort keys $list->%*;

    return $help // q[];
}

sub _help_footer ($self) {
    my @opt = qw[--help -h -? --version];

    push @opt, '--scan-deps' if $SCAN_DEPS;

    return '(global options: ' . join( q[, ], @opt ) . q[)];
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

sub help_version ($self) {
    say $PROC->dist->name . q[ ], $PROC->dist->version, ', rev: ' . $PROC->dist->revision if $PROC->dist;

    say 'Pcore ' . $PROC->pcore->version, ', rev: ' . $PROC->pcore->revision if !$PROC->dist || $PROC->dist->name ne $PROC->pcore->name;

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
## │    3 │ 46                   │ ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 89, 92, 157, 238,    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 273, 334, 357, 420,  │                                                                                                                │
## │      │ 483, 488, 492, 501   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 347                  │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 381, 521, 549        │ NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "abstract"                              │
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
