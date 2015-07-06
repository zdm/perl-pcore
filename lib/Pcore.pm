package Pcore v0.11.4;

use v5.20.2;
use utf8;
use strict;
use warnings ( qw[all], FATAL => qw[utf8], NONFATAL => qw[] );
no  if $^V ge 'v5.18', warnings => 'experimental';
use if $^V ge 'v5.10', feature  => ':all';
no  if $^V ge 'v5.16', feature  => 'array_base';
use if $^V ge 'v5.22', re       => 'strict';
use if $^V ge 'v5.10', mro      => 'c3';
no multidimensional;

use namespace::clean qw[];

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

# define global variables
BEGIN {
    $Pcore::INITIALISED      = 0;                         # core initialisation flag
    $Pcore::CALLER           = caller;                    # namespace, from P was required first time
    $Pcore::EMBEDDED         = 0;                         # Pcore::Core used in embedded mode
    $Pcore::IS_PAR           = $ENV{PAR_TEMP} ? 1 : 0;    # process runned from PAR
    $Pcore::ENCODING_CONSOLE = 'UTF-8';                   # default console encoding, redefined later for windows
    $Pcore::NO_ISA_ATTR      = 0;                         # do not check isa for class / role attributes

    # NOTE workaround for incompatibility with Moo lazy attributes
    # https://rt.cpan.org/Ticket/Display.html?id=102788
    eval {
        local $SIG{__DIE__} = undef;

        require Filter::Crypto::Decrypt if $Pcore::IS_PAR;
    };

    # define %EXPORT_PRAGMAS for exporter
    %Pcore::EXPORT_PRAGMAS = (
        config      => 0,    # mark package as perl config, used automatically during .perl config evaluation, do not use directly!!!
        embedded    => 0,    # run in embedded mode
        export      => 0,    # install standart import method
        no_isa_attr => 0,    # do not check isa for class / role attributes
        autoload    => 0,    # export AUTOLOAD
        cli         => 0,    # add package namespace to CLI processors stack
        no_clean    => 0,    # do not perform namespace autoclean
        class       => 0,    # package is a Moo class
        role        => 0,    # package is a Moo role
        types       => 0,    # export types
    );

    # configure standard library
    $Pcore::UTIL = {
        bit      => 'Pcore::Util::Bit',
        capture  => 'Pcore::Util::Capture',
        cfg      => 'Pcore::Util::Config',
        class    => 'Pcore::Util::Class',
        data     => 'Pcore::Util::Data',
        date     => 'Pcore::Util::Date',
        digest   => 'Pcore::Util::Digest',
        file     => 'Pcore::Util::File',
        geoip    => 'Pcore::Util::GeoIP',
        hash     => 'Pcore::Util::Hash',
        list     => 'Pcore::Util::List',
        mail     => 'Pcore::Util::Mail',
        moo      => 'Pcore::Util::Moo',
        pm       => 'Pcore::Util::PM',
        progress => 'Pcore::Util::Progress',
        prompt   => 'Pcore::Util::Prompt',
        random   => 'Pcore::Util::Random',
        res      => 'Pcore::Util::Resources',
        scalar   => 'Pcore::Util::Scalar',
        sys      => 'Pcore::Util::Sys',
        text     => 'Pcore::Util::Text',
        tmpl     => 'Pcore::Util::Template',
        ua       => 'Pcore::HTTP::UA',
        uri      => 'Pcore::Util::URI',
        uuid     => 'Pcore::Util::UUID',
    };
}

use Pcore::Core::Exporter qw[];

sub import {
    my $self = shift;

    # find caller
    my $caller = caller;

    # parse tags and pragmas
    my ( $tags, $pragma, $data ) = Pcore::Core::Exporter::Helper->parse_import( $self, @_ );

    # initialize Pcore if called first time from non-core package
    if ( !$Pcore::INITIALISED && $caller eq $Pcore::CALLER ) {
        $Pcore::INITIALISED = 1;

        _CORE_INIT($data);
    }

    # export perl pragmas
    utf8->import();
    strict->import();
    warnings->import( 'all', FATAL => qw[utf8], NONFATAL => qw[] );
    warnings->unimport('experimental') if $^V ge 'v5.18';
    feature->import(':all')            if $^V ge 'v5.10';
    feature->unimport('array_base')    if $^V ge 'v5.16';
    re->import('strict')               if $^V ge 'v5.22';
    mro::set_mro( $caller, 'c3' ) if $^V ge 'v5.10';
    multidimensional->unimport;

    # export P sub to avoid indirect calls
    {
        state $val;

        if ( !$val ) {
            $val = 'Pcore';

            Internals::SvREADONLY( $val, 1 );
        }

        no strict qw[refs];

        my $symtab = \%{ $caller . q[::] };

        $symtab->{P} = \$val;

        # flush the cache exactly once if we make any direct symbol table changes
        mro::method_changed_in($caller);
    }

    # export Pcore::Core
    Pcore::Core::Constants->import( -caller => $caller, $tags->@* );
    Pcore::Core::Dump->import( -caller => $caller, $tags->@* );
    Pcore::Core::Exception->import( -caller => $caller, $tags->@* );
    Pcore::Core::H->import( -caller => $caller, $tags->@* );
    Pcore::Core::Log->import( -caller => $caller, $tags->@* );
    Pcore::Core::I18N->import( -caller => $caller, $tags->@* );

    if ( !$pragma->{config} ) {

        # install run-time hook to caller package
        if ( $caller eq $Pcore::CALLER ) {
            B::Hooks::AtRuntime::at_runtime(
                sub {
                    Pcore->_CORE_RUN();
                }
            );
        }

        # install standart import method
        if ( $pragma->{export} ) {
            no strict qw[refs];

            push @{ $caller . '::ISA' }, 'Pcore::Core::Exporter';
        }

        # autoload for non-Moo namespaces
        if ( $pragma->{autoload} && !$pragma->{class} && !$pragma->{role} ) {
            require Pcore::Core::Autoload;

            Pcore::Core::Autoload->import( -caller => $caller );
        }

        # store significant pragmas for use in run-time
        $Pcore::EMBEDDED = 1 if $pragma->{embedded};

        $Pcore::NO_ISA_ATTR = 1 if $pragma->{no_isa_attr};

        # CLI
        if ( $pragma->{cli} ) {
            push @Pcore::Core::CLI::PACKAGES, $caller;
        }

        # re-export Moo
        if ( $pragma->{class} || $pragma->{role} ) {

            # install universal serializer methods
            B::Hooks::EndOfScope::XS::on_scope_end(
                sub {
                    no strict qw[refs];

                    if ( my $ref = $caller->can('TO_DATA') ) {
                        *{ $caller . '::TO_JSON' } = $ref unless $caller->can('TO_JSON');

                        *{ $caller . '::TO_CBOR' } = $ref unless $caller->can('TO_CBOR');
                    }

                    return;
                }
            );

            $pragma->{types} = 1;

            if ( $pragma->{class} ) {
                $self->_import_moo( caller => $caller, class => 1 );
            }
            elsif ( $pragma->{role} ) {
                $self->_import_moo( caller => $caller, role => 1 );
            }

            # reconfigure warnings, after Moo exported
            warnings->import( 'all', FATAL => qw[utf8], NONFATAL => qw[] );
            warnings->unimport('experimental');

            # apply default roles
            $self->_apply_roles( caller => $caller, roles => [qw[Pcore::Core::Autoload::Role]] ) if $pragma->{autoload};
        }

        # export types
        $self->_import_types( caller => $caller ) if $pragma->{types};
    }

    # cleanup
    namespace::clean->import( -cleanee => $caller, -except => [qw[AUTOLOAD]] ) unless $pragma->{no_clean};

    return;
}

sub unimport {    ## no critic qw(Subroutines::ProhibitBuiltinHomonyms)
    my $self = shift;

    # parse pragmas and tags
    my ( $tags, $pragma ) = Pcore::Core::Exporter::Helper->parse_import( $self, @_ );

    # find caller
    my $caller = caller;

    # try to unimport Moo keywords
    $self->_unimport_moo( caller => $caller );

    # unimport types
    $self->_unimport_types( caller => $caller );

    return;
}

sub _import_moo {
    my $self = shift;
    my %args = (
        caller => undef,
        class  => undef,
        role   => undef,
        @_,
    );

    if ( $args{class} ) {
        Moo->import::into( $args{caller} );
    }
    else {
        Moo::Role->import::into( $args{caller} );
    }

    # install "has" hook
    {
        no strict qw[refs];

        my $has = *{ $args{caller} . '::has' }{CODE};

        no warnings qw[redefine];

        *{ $args{caller} . '::has' } = sub {
            my ( $name_proto, %spec ) = @_;

            # disable type checking
            delete $spec{isa} if $Pcore::NO_ISA_ATTR;

            $has->( $name_proto, %spec );
        };
    }

    return;
}

sub _unimport_moo {
    my $self = shift;
    my %args = (
        caller => undef,
        @_,
    );

    if ( $Moo::MAKERS{ $args{caller} } && $Moo::MAKERS{ $args{caller} }->{is_class} ) {    # Moo class
        Moo->unimport::out_of( $args{caller} );
    }
    elsif ( Moo::Role->is_role( $args{caller} ) ) {                                        # Moo::Role
        Moo::Role->unimport::out_of( $args{caller} );
    }

    return;
}

sub _import_types {
    my $self = shift;
    my %args = (
        caller => undef,
        @_,
    );

    state $required;

    if ( !$required ) {
        $required = 1;

        local $ENV{PERL_TYPES_STANDARD_STRICTNUM} = 0;    # 0 - Num = LaxNum, 1 - Num = StrictNum

        require Pcore::Core::Types;
        require Types::TypeTiny;
        require Types::Standard;
        require Types::Common::Numeric;

        # require Types::Common::String;
        # require Types::Encodings();
        # require Types::XSD::Lite();
    }

    Types::TypeTiny->import( { into => $args{caller} }, qw[StringLike HashLike ArrayLike CodeLike TypeTiny] );

    Types::Standard->import( { into => $args{caller} }, ':types' );

    Types::Common::Numeric->import( { into => $args{caller} }, ':types' );

    Pcore::Core::Types->import( { into => $args{caller} }, ':types' );

    return;
}

sub _unimport_types {
    my $self = shift;
    my %args = (
        caller => undef,
        @_,
    );

    Pcore::Core::Types->unimport( { into => $args{caller} }, ':types' );

    Types::Common::Numeric->unimport( { into => $args{caller} }, ':types' );

    Types::Standard->unimport( { into => $args{caller} }, ':types' );

    Types::TypeTiny->unimport( { into => $args{caller} }, qw[StringLike HashLike ArrayLike CodeLike TypeTiny] );

    return;
}

sub _apply_roles {
    my $self = shift;
    my %args = (
        caller => undef,
        roles  => undef,
        @_,
    );

    Moo::Role->apply_roles_to_package( $args{caller}, $args{roles}->@* );

    if ( Moo::Role->is_role( $args{caller} ) ) {
        Moo::Role->_maybe_reset_handlemoose( $args{caller} );    ## no critic qw(Subroutines::ProtectPrivateSubs)
    }
    else {
        Moo->_maybe_reset_handlemoose( $args{caller} );          ## no critic qw(Subroutines::ProtectPrivateSubs)
    }

    return;
}

# CORE compilation phase
use Pcore::Core::Constants qw[:CORE];
use Pcore::Core::EV qw[:CORE];
use Pcore::Core::Bootstrap qw[];
use Pcore::Core::Dump qw[:CORE];
use Pcore::Core::Exception qw[];
use Pcore::Core::H qw[];
use Pcore::Core::Log qw[:CORE];
use Pcore::Core::I18N qw[:CORE];
use Pcore::Core::CLI qw[];

sub _CORE_INIT ($proc_cfg) {

    # set default fallback mode for all further :encoding I/O layers
    $PerlIO::encoding::fallback = Encode::FB_CROAK | Encode::STOP_AT_PARTIAL;

    if ($MSWIN) {
        require Win32::API;
        require Win32::Console::ANSI;

        # detect windows active codepage
        $Pcore::ENCODING_CONSOLE = 'cp' . Win32::API::More->new( 'kernel32', 'int GetACP()' )->Call;

        # check if we can properly decode STDIN under MSWIN
        eval {
            Encode::perlio_ok($Pcore::ENCODING_CONSOLE) or die;
            1;
        } || do {
            say qq[FATAL: Console input encoding "$Pcore::ENCODING_CONSOLE" isn't supported. Use chcp to change console codepage.];

            exit 1;
        };
    }

    # decode @ARGV
    for (@ARGV) {
        $_ = Encode::decode( $Pcore::ENCODING_CONSOLE, $_, Encode::FB_CROAK );
    }

    # configure run-time environment
    Pcore::Core::Bootstrap::CORE_INIT($proc_cfg);

    _configure_console();

    Pcore::Core::Log::CORE_INIT();          # set default log pipes
    Pcore::Core::Exception::CORE_INIT();    # set $SIG{__DIE__}, $SIG{__WARN__}, $SIG->{INT}, $SIG->{TERM} handlers
    Pcore::Core::I18N::CORE_INIT();         # configure default I18N locations
    Pcore::Core::CLI::CORE_INIT();          # register CORE::CLI event

    return;
}

sub _CORE_RUN {

    # EMBEDDED mode, if run not from INIT block or -embedded pragma specified:
    # CLI not parsed / processed;
    # process permissions not changed;
    # process will not daemonized;

    if ( !$Pcore::EMBEDDED ) {

        # throw CORE#CLI event, CLI parsing and processing
        Pcore->EV->throw('CORE#CLI');

        # throw CORE#RUN event to perform daemonize, depends on CLI param
        Pcore->EV->throw('CORE#RUN');

        if ( !$MSWIN ) {

            # GID is inherited from UID by default
            if ( defined $PROC->{UID} && !defined $PROC->{GID} ) {
                my $uid = $PROC->{UID} =~ /\A\d+\z/sm ? $PROC->{UID} : getpwnam $PROC->{UID};

                die qq[Can't find uid "$PROC->{UID}"] if !defined $uid;

                $PROC->{GID} = [ getpwuid $uid ]->[2];
            }

            # change priv
            Pcore->pm->change_priv( gid => $PROC->{GID}, uid => $PROC->{UID} );
        }
    }

    return;
}

# AUTOLOAD
sub AUTOLOAD ( $self, @ ) {    ## no critic qw(ClassHierarchies::ProhibitAutoloading)
    my $method = our $AUTOLOAD =~ s/\A.*:://smr;

    die qq[Unregistered Pcore::Util "$method".] unless exists $Pcore::UTIL->{$method};

    my $class = $Pcore::UTIL->{$method};

    require $class =~ s[::][/]smgr . q[.pm];

    if ( $class->can('NEW') ) {
        no strict qw[refs];

        *{ $self . q[::] . $method } = \&{ $class . '::NEW' };

        goto &{ $self . q[::] . $method };
    }
    else {
        my $val = $Pcore::UTIL->{$method};

        my $symtab;

        # get symbol table ref
        {
            no strict qw[refs];

            $symtab = \%{ $self . q[::] };
        }

        # install method
        $symtab->{$method} = sub : prototype() {$val};

        mro::method_changed_in($self);

        return $val;
    }
}

sub cv {
    state $cv = AE::cv;

    return $cv;
}

sub _configure_console {

    # clone handles
    open our $STDIN,  '<&STDIN'  or $STDIN  = *STDIN;     ## no critic qw(InputOutput::ProhibitBarewordFileHandles Variables::RequireLocalizedPunctuationVars)
    open our $STDOUT, '>&STDOUT' or $STDOUT = *STDOUT;    ## no critic qw(InputOutput::ProhibitBarewordFileHandles Variables::RequireLocalizedPunctuationVars)
    open our $STDERR, '>&STDERR' or $STDERR = *STDERR;    ## no critic qw(InputOutput::ProhibitBarewordFileHandles Variables::RequireLocalizedPunctuationVars)

    # setup default layers for STD* handles
    binmode STDIN,  q[:raw:encoding(UTF-8)] or die;
    binmode STDOUT, q[:raw:encoding(UTF-8)] or die;
    binmode STDERR, q[:raw:encoding(UTF-8)] or die;

    # setup default layers for STD* handles clones
    if ($MSWIN) {
        require PerlIO::via::Win32UnicodeConsole;

        binmode $STDIN,  qq[:raw:crlf:encoding($Pcore::ENCODING_CONSOLE)] or die;
        binmode $STDOUT, q[:raw:via(Win32UnicodeConsole)]                 or die;
        binmode $STDERR, q[:raw:via(Win32UnicodeConsole)]                 or die;

        select $STDOUT;    ## no critic qw(InputOutput::ProhibitOneArgSelect)
    }
    else {
        binmode $STDIN,  q[:raw:encoding(UTF-8)] or die;
        binmode $STDOUT, q[:raw:encoding(UTF-8)] or die;
        binmode $STDERR, q[:raw:encoding(UTF-8)] or die;
    }

    # make STD* non-caching
    STDOUT->autoflush(1);
    STDERR->autoflush(1);

    $STDOUT->autoflush(1);
    $STDERR->autoflush(1);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 45                   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 97                   │ Subroutines::ProhibitExcessComplexity - Subroutine "import" with high complexity score (28)                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 158                  │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 402, 450, 467, 515,  │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## │      │ 516, 517, 523, 524,  │                                                                                                                │
## │      │ 525, 530, 531, 532   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 405                  │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - say                           │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 493                  │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore - perl applications development environment

=head1 SYNOPSIS

    use Pcore qw[-<pragma> <import>], {config};

=head1 DESCRIPTION

Documentation will be provided later.

=head1 ENVIRONMENT

=over

=item * PCORE_DIST_LIB

=item * PCORE_RESOURCES

=item * PCORE_MOUNTED_RESOURCES

=item * MODULE_SIGNATURE_AUTHOR = q["<author-email>"]

=item * __PCORE_SCRIPT_DIR

=item * __PCORE_SCRIPT_NAME

=back

=cut
