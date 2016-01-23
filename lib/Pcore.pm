package Pcore v0.16.1;

use v5.22.1;
use header;

# initialize Net::SSLeay
BEGIN {
    use Net::SSLeay qw[];

    Net::SSLeay::initialize();

    {
        no warnings qw[redefine];

        # we don't need to call Net::SSLeay::randomize several times
        *Net::SSLeay::randomize = sub : prototype(;$$$) { };
    }

    # initialize OpenSSL internal rand. num. generator, RAND_poll() is called automatically on first RAND_bytes() call
    Net::SSLeay::RAND_bytes( my $buf, 1 );    ## no critic qw[Variables::ProhibitUnusedVariables]
}

use Sub::Util qw[];
use Package::Stash qw[];

use Const::Fast qw[];
use Encode qw[];

# preload Moo
use Import::Into;
use Moo qw[];
use Moo::Role qw[];

# preload console related packages
use Term::ANSIColor qw[];
use PerlIO::encoding qw[];

use B::Hooks::AtRuntime qw[];
use B::Hooks::EndOfScope::XS qw[];

# preload AnyEvent
use EV;
use AnyEvent;

use Pcore::Core::Exporter qw[];

# define global variables
BEGIN {
    $Pcore::INITIALISED = 0;         # core initialisation flag
    $Pcore::CALLER      = caller;    # namespace, from P was required first time
    $Pcore::EMBEDDED    = 0;         # Pcore::Core used in embedded mode
    $Pcore::NO_ISA_ATTR = 0;         # do not check isa for class / role attributes
    $Pcore::WIN_ENC     = undef;
    $Pcore::CON_ENC     = undef;

    # NOTE workaround for incompatibility with Moo lazy attributes
    # https://rt.cpan.org/Ticket/Display.html?id=102788
    eval {
        local $SIG{__DIE__} = undef;

        require Filter::Crypto::Decrypt if $ENV{PAR_TEMP};
    };

    # define alias for export
    $Pcore::P = sub : const {'Pcore'};

    # define %EXPORT_PRAGMA for exporter
    $Pcore::EXPORT_PRAGMA = {
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

    # configure standard library
    $Pcore::UTIL = {
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
}

sub namespace_clean ($class) {
    state $EXCEPT = {
        import   => 1,
        unimport => 1,
        AUTOLOAD => 1,
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

sub import {
    my $self = shift;

    # find caller
    my $caller = caller;

    # parse tags and pragmas
    my ( $tags, $pragma, $data ) = Pcore::Core::Exporter::parse_import( $self, @_ );

    # initialize Pcore if called first time from non-core package
    if ( !$Pcore::INITIALISED && $caller eq $Pcore::CALLER ) {
        $Pcore::INITIALISED = 1;

        _CORE_INIT($data);
    }

    # export perl pragmas
    header->import( -caller => $caller );

    # process -const pragma
    Const::Fast->import::into( $caller, 'const' ) if $pragma->{const};

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
    Pcore::Core::Const->import( -caller => $caller, $tags->@* );
    Pcore::Core::Dump->import( -caller => $caller, $tags->@* );
    Pcore::Core::Exception->import( -caller => $caller, $tags->@* );
    Pcore::Core::H->import( -caller => $caller, $tags->@* );

    if ( !$pragma->{config} ) {

        # install run-time hook to caller package
        if ( $caller eq $Pcore::CALLER ) {
            B::Hooks::AtRuntime::at_runtime(
                sub {
                    Pcore::_CORE_RUN();

                    return;
                }
            );
        }

        # process -export pragma
        if ( $pragma->{export} ) {
            Pcore::Core::Exporter->import( -caller => $caller, -export => $pragma->{export} );
        }

        # process -inline pragma
        if ( $pragma->{inline} ) {
            state $init = !!require Pcore::Core::Inline;
        }

        # process -dist pragma
        if ( $pragma->{dist} ) {
            $ENV->register_dist($caller);
        }

        # store significant pragmas for use in run-time
        $Pcore::EMBEDDED = 1 if $pragma->{embedded};

        $Pcore::NO_ISA_ATTR = 1 if $pragma->{no_isa_attr};

        # re-export Moo
        if ( $pragma->{class} || $pragma->{role} ) {

            # install universal serializer methods
            B::Hooks::EndOfScope::XS::on_scope_end(
                sub {
                    namespace_clean($caller);

                    no strict qw[refs];

                    if ( my $ref = $caller->can('TO_DATA') ) {
                        *{"$caller\::TO_JSON"} = $ref unless $caller->can('TO_JSON');

                        *{"$caller\::TO_CBOR"} = $ref unless $caller->can('TO_CBOR');
                    }

                    return;
                }
            );

            $pragma->{types} = 1;

            if ( $pragma->{class} ) {
                _import_moo( $caller, 0 );
            }
            elsif ( $pragma->{role} ) {
                _import_moo( $caller, 1 );
            }

            # reconfigure warnings, after Moo exported
            header->import;

            # apply default roles
            # _apply_roles( $caller, qw[Pcore::Core::Autoload::Role] );
        }

        # export types
        _import_types($caller) if $pragma->{types};
    }

    # process -autoload pragma, should be after the -role to support AUTOLOAD in Moo roles
    # NOTE !!!WARNING!!! AUTOLOAD should be exported after Moo::Role, so Moo::Role can re-export this method
    if ( $pragma->{autoload} ) {
        state $init = !!require Pcore::Core::Autoload;

        Pcore::Core::Autoload->import( -caller => $caller );
    }

    return;
}

sub unimport {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]

    # my $self = shift;

    # parse pragmas and tags
    # my ( $tags, $pragma ) = Pcore::Core::Exporter::parse_import( $self, @_ );

    # find caller
    # my $caller = caller;

    # try to unimport Moo keywords
    # _unimport_moo($caller);

    # unimport types
    # _unimport_types($caller);

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

sub _unimport_moo ($caller) {
    if ( $Moo::MAKERS{$caller} && $Moo::MAKERS{$caller}->{is_class} ) {    # Moo class
        Moo->unimport::out_of($caller);
    }
    elsif ( Moo::Role->is_role($caller) ) {                                # Moo::Role
        Moo::Role->unimport::out_of($caller);
    }

    return;
}

sub _import_types ($caller) {
    state $init = do {
        local $ENV{PERL_TYPES_STANDARD_STRICTNUM} = 0;                     # 0 - Num = LaxNum, 1 - Num = StrictNum

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

sub _unimport_types ($caller) {
    Pcore::Core::Types->unimport( { into => $caller }, ':types' );

    Types::Common::Numeric->unimport( { into => $caller }, ':types' );

    Types::Standard->unimport( { into => $caller }, ':types' );

    Types::TypeTiny->unimport( { into => $caller }, qw[StringLike HashLike ArrayLike CodeLike TypeTiny] );

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

# CORE compilation phase
use Pcore::Core::Const qw[:CORE];
use Pcore::Core::EV qw[:CORE];
use Pcore::Core::Bootstrap qw[];
use Pcore::Core::Dump qw[:CORE];
use Pcore::Core::Exception qw[];
use Pcore::Core::H qw[];

sub _CORE_INIT ($proc_cfg) {

    # set default fallback mode for all further :encoding I/O layers
    $PerlIO::encoding::fallback = Encode::FB_CROAK | Encode::STOP_AT_PARTIAL;

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
        $_ = Encode::decode( $Pcore::WIN_ENC, $_, Encode::FB_CROAK );
    }

    # configure run-time environment
    Pcore::Core::Bootstrap::CORE_INIT($proc_cfg);

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
    state $cv = AE::cv;

    return $cv;
}

# LOGGER
sub log {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    state $log = do {
        require Pcore::Core::Logger;

        my $obj = Pcore::Core::Logger->new;

        # set default log pipes
        for my $ch ( $ENV->pcore->cfg->{log} ? $ENV->pcore->cfg->{log}->@* : (), $ENV->{CFG}->{log} ? $ENV->{CFG}->{log}->@* : () ) {
            $obj->add_channel( $ch->@* );
        }

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

# TODO add PerlIO::removeEsc layer
sub _config_stdout ($h) {
    if ($MSWIN) {
        if ( -t $h ) {                     ## no critic qw[InputOutput::ProhibitInteractiveTest]
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 58                   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 124                  │ BuiltinFunctions::ProhibitComplexMappings - Map blocks should have a single statement                          │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 188                  │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 317                  │ * Private subroutine/method '_unimport_moo' declared but not used                                              │
## │      │ 355                  │ * Private subroutine/method '_unimport_types' declared but not used                                            │
## │      │ 367                  │ * Private subroutine/method '_apply_roles' declared but not used                                               │
## │      │ 467                  │ * Private subroutine/method '_CORE_RUN' declared but not used                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 405, 434, 437, 441,  │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## │      │ 488, 505, 599, 602,  │                                                                                                                │
## │      │ 607, 610             │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 130                  │ ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 134                  │ ControlStructures::ProhibitPostfixControls - Postfix control "for" used                                        │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 16                   │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 409                  │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - say                           │
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

=item * PCORE_DIST_LIB

=back

=cut
