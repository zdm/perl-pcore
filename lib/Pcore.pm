package Pcore v0.63.4;

use v5.26.0;
use common::header;
use Pcore::Core::Exporter qw[];
use Pcore::Core::Const qw[:CORE];

# define %EXPORT_PRAGMA for exporter
our $EXPORT_PRAGMA = {
    ansi     => 0,    # export ANSI color variables
    class    => 0,    # package is a Moo class
    config   => 0,    # mark package as perl config, used automatically during .perl config evaluation, do not use directly!!!
    const    => 0,    # export "const" keyword
    dist     => 0,    # mark package aas Pcore dist main module
    embedded => 0,    # run in embedded mode
    export   => 1,    # install standart import method
    inline   => 0,    # package use Inline
    l10n     => 1,    # register package L10N domain
    res      => 0,    # export Pcore::Util::Result qw[res]
    role     => 0,    # package is a Moo role
    rpc      => 0,    # run class as RPC server
    sql      => 0,    # export Pcore::Handle::DBI::Const qw[:TYPES]

    # TODO
    types => 0,       # export types
};

our $EMBEDDED    = 0;       # Pcore::Core used in embedded mode
our $FORK        = 0;       # fork template proc
our $SCRIPT_PATH = $0;
our $WIN_ENC     = undef;
our $CON_ENC     = undef;

# define alias for export
our $P = sub : const {'Pcore'};

# configure standard library
our $UTIL = {
    bit      => 'Pcore::Util::Bit',
    ca       => 'Pcore::Util::CA',
    cfg      => 'Pcore::Util::Config',
    class    => 'Pcore::Util::Class',
    data     => 'Pcore::Util::Data',
    date     => 'Pcore::Util::Date',
    digest   => 'Pcore::Util::Digest',
    file     => 'Pcore::Util::File',
    handle   => 'Pcore::Handle',
    hash     => 'Pcore::Util::Hash',
    host     => 'Pcore::Util::URI::Host',
    http     => 'Pcore::HTTP',
    list     => 'Pcore::Util::List',
    path     => 'Pcore::Util::Path',
    perl     => 'Pcore::Util::Perl',
    pm       => 'Pcore::Util::PM',
    progress => 'Pcore::Util::Term::Progress',
    random   => 'Pcore::Util::Random',
    scalar   => 'Pcore::Util::Scalar',
    sys      => 'Pcore::Util::Sys',
    term     => 'Pcore::Util::Term',
    text     => 'Pcore::Util::Text',
    tmpl     => 'Pcore::Util::Template',
    uri      => 'Pcore::Util::URI',
    uuid     => 'Pcore::Util::UUID',
};

sub import {
    my $self = shift;

    # get caller
    my $caller = caller;

    # parse tags and pragmas
    my $import = Pcore::Core::Exporter::parse_import( $self, @_ );

    state $INIT = do {

        # store -embedded pragma
        $EMBEDDED = 1 if $import->{pragma}->{embedded};

        require B::Hooks::AtRuntime;
        require B::Hooks::EndOfScope::XS;
        require EV;
        require AnyEvent;
        require Coro;
        require Pcore::Core::OOP::Class;
        require Pcore::Core::OOP::Role;

        # install run-time hook to caller package
        B::Hooks::AtRuntime::at_runtime( \&Pcore::_CORE_RUN );

        # detect RPC server
        if ( $import->{pragma}->{rpc} ) {
            if ( $0 eq '-' ) {

                # read and unpack boot args from STDIN
                my $RPC_BOOT_ARGS = <>;

                chomp $RPC_BOOT_ARGS;

                require CBOR::XS;

                $RPC_BOOT_ARGS = CBOR::XS::decode_cbor( pack 'H*', $RPC_BOOT_ARGS );

                # init RPC environment
                $SCRIPT_PATH   = $RPC_BOOT_ARGS->{script_path};
                $main::VERSION = version->new( $RPC_BOOT_ARGS->{version} );

                B::Hooks::AtRuntime::after_runtime( sub {
                    require Pcore::RPC::Server;

                    Pcore::RPC::Server::run( $caller, $RPC_BOOT_ARGS );

                    exit;
                } );
            }
            else {
                $FORK = 1;
            }
        }

        _CORE_INIT();

        1;
    };

    # export header
    common::header->import;

    # export P sub to avoid indirect calls
    {
        no strict qw[refs];

        *{"$caller\::P"} = $P;

        # flush the cache exactly once if we make any direct symbol table changes
        # mro::method_changed_in($caller);
    }

    # re-export core packages
    Pcore::Core::Const->import( -caller => $caller );

    if ( !$import->{pragma}->{config} ) {

        # process -l10n pragma
        if ( $import->{pragma}->{l10n} ) {
            state $L10N_INIT = !!require Pcore::Core::L10N;

            Pcore::Core::L10N->import( -caller => $caller );

            Pcore::Core::L10N::register_package_domain( $caller, $import->{pragma}->{l10n} );
        }

        # export "dump"
        Pcore::Core::Dump->import( -caller => $caller );

        # process -export pragma
        Pcore::Core::Exporter->import( -caller => $caller, -export => $import->{pragma}->{export} ) if $import->{pragma}->{export};

        # process -inline pragma
        if ( $import->{pragma}->{inline} ) {
            state $INLINE_INIT = !!require Pcore::Core::Inline;
        }

        # process -dist pragma
        $ENV->register_dist($caller) if $import->{pragma}->{dist};

        # process -const pragma
        if ( $import->{pragma}->{const} ) {
            no strict qw[refs];

            *{"$caller\::const"} = \&Const::Fast::const;
        }

        # process -ansi pragma
        if ( $import->{pragma}->{ansi} ) {
            Pcore::Core::Const->import( -caller => $caller, qw[:ANSI] );
        }

        # import exceptions
        Pcore::Core::Exception->import( -caller => $caller );

        # process -res pragma
        if ( $import->{pragma}->{res} ) {
            state $RESULT_INIT = !!require Pcore::Util::Result;

            Pcore::Util::Result->import( -caller => $caller, qw[res] );
        }

        # process -sql pragma
        if ( $import->{pragma}->{sql} ) {
            state $SQL_INIT = !!require Pcore::Handle::DBI::Const;

            Pcore::Handle::DBI::Const->import( -caller => $caller, qw[:TYPES :QUERY] );
        }

        # re-export OOP
        if ( $import->{pragma}->{class} || $import->{pragma}->{role} ) {

            # install universal serializer methods
            B::Hooks::EndOfScope::XS::on_scope_end( sub {
                no strict qw[refs];

                if ( my $ref = $caller->can('TO_DATA') ) {
                    *{"$caller\::TO_JSON"} = $ref unless $caller->can('TO_JSON');

                    *{"$caller\::TO_CBOR"} = $ref unless $caller->can('TO_CBOR');
                }

                return;
            } );

            $import->{pragma}->{types} = 1;

            if ( $import->{pragma}->{class} ) {
                Pcore::Core::OOP::Class->import($caller);
            }
            else {
                Pcore::Core::OOP::Role->import($caller);
            }
        }

        # export types
        _import_types($caller) if $import->{pragma}->{types};
    }

    return;
}

sub _import_types ($caller) {
    state $init = do {
        local $ENV{PERL_TYPES_STANDARD_STRICTNUM} = 0;    # 0 - Num = LaxNum, 1 - Num = StrictNum

        require Pcore::Core::Types;
        require Types::TypeTiny;
        require Types::Standard;
        require Types::Common::Numeric;

        # require Types::Common::String;
        # require Types::Encodings();
        # require Types::XSD::Lite();

        1;
    };

    Types::TypeTiny->import( { into => $caller }, qw[StringLike HashLike ArrayLike CodeLike TypeTiny] );

    Types::Standard->import( { into => $caller }, ':types' );

    Types::Common::Numeric->import( { into => $caller }, ':types' );

    Pcore::Core::Types->import( { into => $caller }, ':types' );

    return;
}

sub _CORE_INIT {
    require Pcore::Core::Dump;
    Pcore::Core::Dump->import(':CORE');

    # set default fallback mode for all further :encoding I/O layers
    $PerlIO::encoding::fallback = Encode::FB_CROAK() | Encode::STOP_AT_PARTIAL();

    if ($MSWIN) {
        require Win32;
        require Win32::Console::ANSI;

        $WIN_ENC = 'cp' . Win32::GetACP();
        $CON_ENC = Win32::GetConsoleCP();

        if ($CON_ENC) {
            $CON_ENC = 'cp' . $CON_ENC;

            # check if we can properly decode STDIN under MSWIN
            eval {
                Encode::perlio_ok($CON_ENC) or die;

                1;
            } || do {
                say qq[FATAL: Console input encoding "$CON_ENC" isn't supported. Use chcp to change console codepage.];

                exit 1;
            };
        }
        else {
            $CON_ENC = undef;
        }
    }
    else {
        $CON_ENC = 'UTF-8';
        $WIN_ENC = 'UTF-8';
    }

    # decode @ARGV
    for (@ARGV) {
        $_ = Encode::decode( $WIN_ENC, $_, Encode::FB_CROAK() );
    }

    # configure run-time environment
    require Pcore::Core::Env;

    # STDIN
    if ( -t *STDIN ) {    ## no critic qw[InputOutput::ProhibitInteractiveTest]
        if ($MSWIN) {
            binmode *STDIN, ":raw:crlf:encoding($CON_ENC)" or die;
        }
        else {
            binmode *STDIN, ':raw:encoding(UTF-8)' or die;
        }
    }
    else {
        binmode *STDIN, ':raw' or die;
    }

    # STDOUT
    config_stdout(*STDOUT);
    config_stdout(*STDERR);

    STDOUT->autoflush(1);
    STDERR->autoflush(1);

    require Pcore::Core::Exception;    # set $SIG{__DIE__}, $SIG{__WARN__}, $SIG->{INT}, $SIG->{TERM} handlers

    require Pcore::Util::PM::ForkTmpl if $FORK && !$MSWIN;

    _CORE_INIT_AFTER_FORK();

    return;
}

sub _CORE_INIT_AFTER_FORK {
    require Pcore::AE::Patch;

    return;
}

# TODO add PerlIO::removeEsc layer
sub config_stdout ($h) {
    if ($MSWIN) {
        if ( -t $h ) {    ## no critic qw[InputOutput::ProhibitInteractiveTest]
            state $init = !!require Pcore::Core::PerlIOviaWinUniCon;

            binmode $h, ':raw:via(Pcore::Core::PerlIOviaWinUniCon)' or die;    # terminal
        }
        else {
            binmode $h, ':raw:encoding(UTF-8)' or die;                         # file TODO +RemoveESC
        }
    }
    else {
        if ( -t $h ) {                                                         ## no critic qw[InputOutput::ProhibitInteractiveTest]
            binmode $h, ':raw:encoding(UTF-8)' or die;                         # terminal
        }
        else {
            binmode $h, ':raw:encoding(UTF-8)' or die;                         # file TODO +RemoveESC
        }
    }

    return;
}

sub _CORE_RUN {

    # EMBEDDED mode, if run not from INIT block or -embedded pragma specified:
    # CLI not parsed / processed;
    # process permissions not changed;
    # process will not daemonized;

    if ( !$EMBEDDED ) {
        state $INIT_CLI = !!require Pcore::Core::CLI;

        Pcore::Core::CLI->new( { class => 'main' } )->run( \@ARGV );

        if ( !$MSWIN ) {

            # GID is inherited from UID by default
            if ( defined $ENV->{UID} && !defined $ENV->{GID} ) {
                my $uid = $ENV->{UID} =~ /\A\d+\z/sm ? $ENV->{UID} : getpwnam $ENV->{UID};

                die qq[Can't find uid "$ENV->{UID}"] if !defined $uid;

                $ENV->{GID} = [ getpwuid $uid ]->[2];
            }

            # change priv
            Pcore->pm->change_priv( gid => $ENV->{GID}, uid => $ENV->{UID} );

            P->pm->daemonize if $ENV->{DAEMONIZE};
        }
    }

    return;
}

# L10N
sub set_locale ( $self, $locale = undef ) {
    state $L10N_INIT = !!require Pcore::Core::L10N;

    return Pcore::Core::L10N::set_locale($locale);
}

# AUTOLOAD
sub AUTOLOAD ( $self, @ ) {    ## no critic qw[ClassHierarchies::ProhibitAutoloading]
    my $util = our $AUTOLOAD =~ s/\A.*:://smr;

    die qq[Unregistered Pcore::Util "$util".] unless my $class = $UTIL->{$util};

    require $class =~ s[::][/]smgr . '.pm';

    no strict qw[refs];

    if ( $class->can('new') ) {
        eval <<"PERL";         ## no critic qw[BuiltinFunctions::ProhibitStringyEval ErrorHandling::RequireCheckingReturnValueOfEval]
            *{$util} = sub {
                shift;

                return $class->new(\@_);
            };
PERL
    }
    else {

        # create util namespace with AUTOLOAD method
        eval <<"PERL";         ## no critic qw[BuiltinFunctions::ProhibitStringyEval ErrorHandling::RequireCheckingReturnValueOfEval]
            package $self\::Util::_$util;

            use Pcore;

            sub AUTOLOAD {
                my \$method = our \$AUTOLOAD =~ s/\\A.*:://smr;

                no strict qw[refs];

                die qq[Sub "$class\::\$method" is not defined] if !defined &{"$class\::\$method"};

                # install method wrapper
                eval <<"EVAL";
                    *{"$self\::Util::_$util\::\$method"} = sub {
                        shift;

                        return &$class\::\$method;
                    };
EVAL

                goto &{\$method};
            }
PERL

        # create util namespace access method
        *{$util} = sub : const {"$self\::Util::_$util"};
    }

    goto &{$util};
}

# EVENT
sub _init_ev {
    state $broker = do {
        require Pcore::Core::Event;

        my $_broker = Pcore::Core::Event->new;

        # set default log channels
        $_broker->listen_events( 'LOG.EXCEPTION.*', 'stderr:' );

        # file logs are disabled by default for scripts, that are not part of the distribution
        if ( $ENV->dist ) {
            $_broker->listen_events( 'LOG.EXCEPTION.FATAL', 'file:fatal.log' );
            $_broker->listen_events( 'LOG.EXCEPTION.ERROR', 'file:error.log' );
            $_broker->listen_events( 'LOG.EXCEPTION.WARN',  'file:warn.log' );
        }

        $_broker;
    };

    return $broker;
}

sub listen_events ( $self, $masks, @listeners ) {
    state $broker = _init_ev();

    return $broker->listen_events( $masks, @listeners );
}

sub has_listeners ( $self, $key ) {
    state $broker = _init_ev();

    return $broker->has_listeners($key);
}

sub forward_event ( $self, $ev ) {
    state $broker = _init_ev();

    return $broker->forward_event($ev);
}

sub fire_event ( $self, $key, $data = undef ) {
    state $broker = _init_ev();

    my $ev = {
        key  => $key,
        data => $data,
    };

    return $broker->forward_event($ev);
}

sub sendlog ( $self, $key, $title, $data = undef ) {
    state $broker = _init_ev();

    return if !$broker->has_listeners("LOG.$key");

    my $ev;

    ( $ev->{channel}, $ev->{level} ) = split /[.]/sm, $key, 2;

    die q[Log level must be specified] unless $ev->{level};

    $ev->{key}       = "LOG.$key";
    $ev->{timestamp} = Time::HiRes::time();
    \$ev->{title} = \$title;
    \$ev->{data}  = \$data;

    $broker->forward_event($ev);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 66                   | Subroutines::ProhibitExcessComplexity - Subroutine "import" with high complexity score (22)                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 89                   | Variables::ProtectPrivateVars - Private variable used                                                          |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 275, 304, 307, 311,  | ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  |
## |      | 342, 345, 350, 353,  |                                                                                                                |
## |      | 378, 404, 515        |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 360                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_CORE_RUN' declared but not used    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 279                  | InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - say                           |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore - perl applications development environment

=begin HTML

<p><a href="https://metacpan.org/pod/Pcore" target="_blank"><img alt="CPAN version" src="https://badge.fury.io/pl/Pcore.svg"></a></p>

=end HTML

=head1 SYNOPSIS

    use Pcore -<pragma> qw[<import>], {config};

=head1 DESCRIPTION

Documentation will be provided later.

=head1 ENVIRONMENT

=over

=item * PCORE_LIB

=back

=cut
