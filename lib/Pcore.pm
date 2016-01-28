package Pcore v0.16.1;

use v5.22.1;
use header;

use Pcore::Core::Exporter qw[];
use Pcore::Core::Const qw[:CORE];

sub import {
    my $self = shift;

    # find caller
    my $caller = caller;

    # init exporter
    state $INIT1 = _INIT1();

    # parse tags and pragmas
    my $import = Pcore::Core::Exporter::parse_import( $self, @_ );

    # store -embedded pragma
    $Pcore::EMBEDDED = 1 if $import->{pragma}->{embedded};

    state $INIT2 = _INIT2();

    # install run-time hook to caller package
    state $RUNTIME_HOOK = do {
        B::Hooks::AtRuntime::at_runtime( \&Pcore::_CORE_RUN );

        1;
    };

    state $INIT3 = _CORE_INIT();

    # export header
    header->import( -caller => $caller );

    # process -const pragma
    Const::Fast->import::into( $caller, 'const' ) if $import->{pragma}->{const};

    # export P sub to avoid indirect calls
    # export i18n
    {
        no strict qw[refs];

        *{"$caller\::P"} = $Pcore::P;

        *{"$caller\::i18n"} = \&i18n;

        # flush the cache exactly once if we make any direct symbol table changes
        mro::method_changed_in($caller);
    }

    # re-export core packages
    Pcore::Core::Const->import( -caller => $caller );
    Pcore::Core::Dump->import( -caller => $caller );
    Pcore::Core::Exception->import( -caller => $caller );
    Pcore::Core::H->import( -caller => $caller );

    if ( !$import->{pragma}->{config} ) {

        # process -export pragma
        if ( $import->{pragma}->{export} ) {
            Pcore::Core::Exporter->import( -caller => $caller, -export => $import->{pragma}->{export} );
        }

        # process -inline pragma
        if ( $import->{pragma}->{inline} ) {
            state $init = !!require Pcore::Core::Inline;
        }

        # process -dist pragma
        if ( $import->{pragma}->{dist} ) {
            $ENV->register_dist($caller);
        }

        # store significant pragmas for use in run-time
        $Pcore::NO_ISA_ATTR = 1 if $import->{pragma}->{no_isa_attr};

        # re-export Moo
        if ( $import->{pragma}->{class} || $import->{pragma}->{role} ) {

            # install universal serializer methods
            B::Hooks::EndOfScope::XS::on_scope_end(
                sub {
                    _namespace_clean($caller);

                    no strict qw[refs];

                    if ( my $ref = $caller->can('TO_DATA') ) {
                        *{"$caller\::TO_JSON"} = $ref unless $caller->can('TO_JSON');

                        *{"$caller\::TO_CBOR"} = $ref unless $caller->can('TO_CBOR');
                    }

                    return;
                }
            );

            $import->{pragma}->{types} = 1;

            if ( $import->{pragma}->{class} ) {
                _import_moo( $caller, 0 );
            }
            elsif ( $import->{pragma}->{role} ) {
                _import_moo( $caller, 1 );
            }

            # reconfigure warnings, after Moo exported
            header->import;

            # apply default roles
            # _apply_roles( $caller, qw[Pcore::Core::Autoload::Role] );
        }

        # export types
        _import_types($caller) if $import->{pragma}->{types};

        # process -autoload pragma, should be after the -role to support AUTOLOAD in Moo roles
        # NOTE !!!WARNING!!! AUTOLOAD should be exported after Moo::Role, so Moo::Role can re-export this method
        if ( $import->{pragma}->{autoload} ) {
            state $init = !!require Pcore::Core::Autoload;

            Pcore::Core::Autoload->import( -caller => $caller );
        }
    }

    return;
}

sub _INIT1 {

    # define %EXPORT_PRAGMA for exporter
    our $EXPORT_PRAGMA = {
        autoload    => 0,    # export AUTOLOAD
        class       => 0,    # package is a Moo class
        config      => 0,    # mark package as perl config, used automatically during .perl config evaluation, do not use directly!!!
        const       => 0,    # export "const" keyword
        dist        => 0,    # mark package aas Pcore dist main module
        embedded    => 0,    # run in embedded mode
        export      => 1,    # install standart import method
        inline      => 0,    # package use Inline
        no_isa_attr => 0,    # do not check isa for class / role attributes
        role        => 0,    # package is a Moo role
        types       => 0,    # export types
    };

    our $EMBEDDED    = 0;       # Pcore::Core used in embedded mode
    our $NO_ISA_ATTR = 0;       # do not check isa for class / role attributes
    our $WIN_ENC     = undef;
    our $CON_ENC     = undef;

    return;
}

sub _INIT2 {

    # initialize Net::SSLeay, effective only for MSWin and if Pcore is not -embedded
    if ( $^O =~ /MSWin/sm && !$Pcore::EMBEDDED ) {
        require Net::SSLeay;

        Net::SSLeay::initialize();

        {
            no warnings qw[redefine];

            # we don't need to call Net::SSLeay::randomize several times
            *Net::SSLeay::randomize = sub : prototype(;$$$) { };
        }

        # initialize OpenSSL internal rand. num. generator, RAND_poll() is called automatically on first RAND_bytes() call
        Net::SSLeay::RAND_bytes( my $buf, 1 );    ## no critic qw[Variables::ProhibitUnusedVariables]
    }

    # preload Moo
    require Import::Into;
    require B::Hooks::AtRuntime;
    require B::Hooks::EndOfScope::XS;

    # preload AnyEvent
    require EV;
    require AnyEvent;

    # NOTE workaround for incompatibility with Moo lazy attributes
    # https://rt.cpan.org/Ticket/Display.html?id=102788
    eval {
        local $SIG{__DIE__} = undef;

        require Filter::Crypto::Decrypt if $ENV{PAR_TEMP};
    };

    # define alias for export
    our $P = sub : const {'Pcore'};

    # configure standard library
    our $UTIL = {
        bit      => 'Pcore::Util::Bit',
        cfg      => 'Pcore::Util::Config',
        class    => 'Pcore::Util::Class',
        data     => 'Pcore::Util::Data',
        date     => 'Pcore::Util::Date',
        digest   => 'Pcore::Util::Digest',
        file     => 'Pcore::Util::File',
        hash     => 'Pcore::Util::Hash',
        host     => 'Pcore::Util::URI::Host',
        http     => 'Pcore::HTTP',
        list     => 'Pcore::Util::List',
        mail     => 'Pcore::Util::Mail',
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

    return;
}

sub _namespace_clean ($class) {
    state $EXCEPT = do {
        require Sub::Util;
        require Package::Stash;

        {   import   => 1,
            AUTOLOAD => 1,
        };
    };

    my $stash = Package::Stash->new($class);

    for my $subname ( $stash->list_all_symbols('CODE') ) {
        my $fullname = Sub::Util::subname( $stash->get_symbol("&$subname") );

        if ( "$class\::$subname" ne $fullname && !exists $EXCEPT->{$subname} && substr( $subname, 0, 1 ) ne q[(] ) {
            my @symbols = map {
                my $name = $_ . $subname;

                my $def = $stash->get_symbol($name);

                defined($def) ? [ $name, $def ] : ()
            } '$', '@', '%', qw[];

            $stash->remove_glob($subname);

            $stash->add_symbol( $_->@* ) for @symbols;
        }
    }

    return;
}

sub _import_moo ( $caller, $role ) {
    if ($role) {
        Moo::Role->import::into($caller);
    }
    else {
        Moo->import::into($caller);
    }

    # install "has" hook
    {
        no strict qw[refs];

        my $has = *{"$caller\::has"}{CODE};

        no warnings qw[redefine];

        *{"$caller\::has"} = sub {
            my ( $name_proto, %spec ) = @_;

            # disable type checking
            delete $spec{isa} if $Pcore::NO_ISA_ATTR;

            # auto add builder if lazy and builder or default is not specified
            $spec{builder} = 1 if $spec{lazy} && !exists $spec{default} && !exists $spec{builder};

            $has->( $name_proto, %spec );
        };
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

sub _apply_roles ( $caller, @roles ) {
    Moo::Role->apply_roles_to_package( $caller, @roles );

    if ( Moo::Role->is_role($caller) ) {
        Moo::Role->_maybe_reset_handlemoose($caller);    ## no critic qw[Subroutines::ProtectPrivateSubs]
    }
    else {
        Moo->_maybe_reset_handlemoose($caller);          ## no critic qw[Subroutines::ProtectPrivateSubs]
    }

    return;
}

sub _CORE_INIT {
    require Pcore::Core::EV;
    Pcore::Core::EV->import(':CORE');

    require Pcore::Core::Bootstrap;

    require Pcore::Core::Dump;
    Pcore::Core::Dump->import(':CORE');

    require Pcore::Core::Exception;
    require Pcore::Core::H;

    # set default fallback mode for all further :encoding I/O layers
    $PerlIO::encoding::fallback = Encode::FB_CROAK() | Encode::STOP_AT_PARTIAL();

    if ($MSWIN) {
        require Win32;
        require Win32::Console::ANSI;

        $Pcore::WIN_ENC = 'cp' . Win32::GetACP();
        $Pcore::CON_ENC = Win32::GetConsoleCP();

        if ($Pcore::CON_ENC) {
            $Pcore::CON_ENC = 'cp' . $Pcore::CON_ENC;

            # check if we can properly decode STDIN under MSWIN
            eval {
                Encode::perlio_ok($Pcore::CON_ENC) or die;

                1;
            } || do {
                say qq[FATAL: Console input encoding "$Pcore::CON_ENC" isn't supported. Use chcp to change console codepage.];

                exit 1;
            };
        }
        else {
            $Pcore::CON_ENC = undef;
        }
    }
    else {
        $Pcore::CON_ENC = 'UTF-8';
        $Pcore::WIN_ENC = 'UTF-8';
    }

    # decode @ARGV
    for (@ARGV) {
        $_ = Encode::decode( $Pcore::WIN_ENC, $_, Encode::FB_CROAK() );
    }

    # configure run-time environment
    Pcore::Core::Bootstrap::CORE_INIT();

    # STDIN
    if ( -t *STDIN ) {    ## no critic qw[InputOutput::ProhibitInteractiveTest]
        if ($MSWIN) {
            binmode *STDIN, ":raw:crlf:encoding($Pcore::CON_ENC)" or die;
        }
        else {
            binmode *STDIN, ':raw:encoding(UTF-8)' or die;
        }
    }
    else {
        binmode *STDIN, ':raw' or die;
    }

    # STDOUT
    open our $STDOUT_UTF8, '>&STDOUT' or $STDOUT_UTF8 = *STDOUT;    ## no critic qw[InputOutput::ProhibitBarewordFileHandles]

    _config_stdout($STDOUT_UTF8);

    # STDERR
    open our $STDERR_UTF8, '>&STDERR' or $STDERR_UTF8 = *STDERR;    ## no critic qw[InputOutput::ProhibitBarewordFileHandles]

    _config_stdout($STDERR_UTF8);

    select $STDOUT_UTF8;                                            ## no critic qw[InputOutput::ProhibitOneArgSelect]

    STDOUT->autoflush(1);
    STDERR->autoflush(1);

    $STDOUT_UTF8->autoflush(1);
    $STDERR_UTF8->autoflush(1);

    Pcore::Core::Exception::CORE_INIT();                            # set $SIG{__DIE__}, $SIG{__WARN__}, $SIG->{INT}, $SIG->{TERM} handlers

    return;
}

# TODO add PerlIO::removeEsc layer
sub _config_stdout ($h) {
    if ($MSWIN) {
        if ( -t $h ) {                                              ## no critic qw[InputOutput::ProhibitInteractiveTest]
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

    if ( !$Pcore::EMBEDDED ) {
        state $init_cli = !!require Pcore::Core::CLI;

        Pcore::Core::CLI->new( { class => 'main' } )->run( \@ARGV );

        # throw CORE#RUN event to perform daemonize, depends on CLI param
        Pcore->EV->throw('CORE#RUN');

        if ( !$MSWIN ) {

            # GID is inherited from UID by default
            if ( defined $ENV->{UID} && !defined $ENV->{GID} ) {
                my $uid = $ENV->{UID} =~ /\A\d+\z/sm ? $ENV->{UID} : getpwnam $ENV->{UID};

                die qq[Can't find uid "$ENV->{UID}"] if !defined $uid;

                $ENV->{GID} = [ getpwuid $uid ]->[2];
            }

            # change priv
            Pcore->pm->change_priv( gid => $ENV->{GID}, uid => $ENV->{UID} );
        }
    }

    return;
}

# AUTOLOAD
sub AUTOLOAD ( $self, @ ) {    ## no critic qw[ClassHierarchies::ProhibitAutoloading]
    my $util = our $AUTOLOAD =~ s/\A.*:://smr;

    die qq[Unregistered Pcore::Util "$util".] unless my $class = $Pcore::UTIL->{$util};

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

# AE::cv
sub cv {
    state $cv = AE::cv();

    return $cv;
}

# LOGGER
sub log {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    state $log = do {
        require Pcore::Core::Logger;

        my $obj = Pcore::Core::Logger->new;

        # set default log channels
        $obj->add_channel( 'fatal', 'stderr:', 'file:fatal.log' );
        $obj->add_channel( 'error', 'stderr:', 'file:error.log' );
        $obj->add_channel( 'warn',  'stderr:', 'file:warn.log' );

        $obj;
    };

    return $log;
}

# I18N
sub i18n {
    state $init = do {
        require Pcore::Core::I18N;

        Pcore::Core::I18N::CORE_INIT();    # configure default I18N locations

        1;
    };

    return &Pcore::Core::I18N::i18n;       ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 28                   │ Variables::ProtectPrivateVars - Private variable used                                                          │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 186                  │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 242                  │ BuiltinFunctions::ProhibitComplexMappings - Map blocks should have a single statement                          │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 318                  │ * Private subroutine/method '_apply_roles' declared but not used                                               │
## │      │ 444                  │ * Private subroutine/method '_CORE_RUN' declared but not used                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 358, 387, 390, 394,  │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## │      │ 426, 429, 434, 437,  │                                                                                                                │
## │      │ 465, 482             │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 248                  │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 252                  │ ControlStructures::ProhibitPostfixControls - Postfix control "for" used                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 168                  │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 362                  │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - say                           │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
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
