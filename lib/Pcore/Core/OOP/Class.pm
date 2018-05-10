package Pcore::Core::OOP::Class;

use Pcore;
use Pcore::Util::Scalar qw[is_ref is_coderef];
use Class::XSAccessor qw[];
use Role::Tiny qw[];

our ( %BASE, %DESTROY );
our $ATTRS = {};

sub import ( $self, $caller = undef ) {
    $caller //= caller;

    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub new { Pcore::Core::OOP::Class::_new(\@_) };
PERL

    {
        no strict qw[refs];

        *{"$caller\::extends"} = \&extends;
        *{"$caller\::with"}    = \&with;
        *{"$caller\::has"}     = \&has;
    }

    return;
}

# TODO around

sub extends (@superclasses) {
    my $caller = caller;

    for my $base (@superclasses) {
        if ( !exists $BASE{$base} ) {
            my $name = $base =~ s[::][/]smgr . '.pm';

            require $name if !exists $INC{$name};

            $BASE{$base} = undef;
        }

        no strict qw[refs];

        push @{"$caller\::ISA"}, $base;
    }

    # DEMOLISH handler
    {
        my @demolish = do {
            no strict qw[refs];

            grep { *{"$_\::DEMOLISH"}{CODE} } mro::get_linear_isa($caller)->@*;
        };

        if (@demolish) {
            {
                no strict qw[refs];

                die qq[Class "$caller" do not use DESTROY and DEMOLISH methods together] if !exists $DESTROY{$caller} && *{"$caller\::DESTROY"}{CODE};
            }

            $DESTROY{$caller} = undef;

            no warnings qw[redefine];

            eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub DESTROY {
    my \$global = \${^GLOBAL_PHASE} eq 'DESTRUCT';

    @{[ map { qq[\$_[0]->$_\::DEMOLISH(\$global);\n] } @demolish ]}

    return;
}

PERL
        }
    }

    return;
}

# TODO role attributes
sub with (@roles) {
    my $caller = caller;

    Role::Tiny->apply_roles_to_package( $caller, @roles );

    return;
}

# TODO warnings on use "is" property
sub has ( $attr, @spec ) {
    my $caller = caller;

    my $spec;

    if ( substr( $attr, 0, 1 ) eq '+' ) {
        substr $attr, 0, 1, q[];

        # find parent attr spec
        my ( undef, @isa ) = mro::get_linear_isa($caller)->@*;

        for my $class (@isa) {
            if ( exists $ATTRS->{$class}->{$attr} ) {
                $spec = { $ATTRS->{$class}->{$attr}->%* };

                last;
            }
        }

        die qq[Class "$caller" attribute "$attr" was not found in superclasses] if !defined $spec;
    }
    else {
        $spec = {};
    }

    if ( @spec == 1 ) {
        $spec->{default} = $spec[0];
    }
    else {
        my %spec = @spec;

        $spec->@{ keys %spec } = values %spec;
    }

    # check default value
    die qq[Class "$caller" attribute "$attr" deefault value can be "Scalar" or "CodeRef"] if exists $spec->{default} && !( !is_ref $spec->{default} || is_coderef $spec->{default} );

    $ATTRS->{$caller}->{$attr} = $spec;

    # install accessors
    if ( exists $spec->{is} ) {

        # "ro" accessor
        if ( $spec->{is} eq 'ro' ) {
            Class::XSAccessor->import(
                getters => [$attr],
                class   => $caller,
            );
        }

        # "rw" accessor
        elsif ( $spec->{is} eq 'rw' ) {
            Class::XSAccessor->import(
                accessors => [$attr],
                class     => $caller,
            );
        }

        # "lazy" accessor
        elsif ( $spec->{is} eq 'lazy' ) {
            eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub $attr {
    \$_[0]->{$attr} = \$_[0]->_build_$attr if !exists \$_[0]->{$attr};

    return \$_[0]->{$attr};
}
PERL
        }
        else {
            die qq[Invalid "is" type for attribute "$attr" in class "$caller"];
        }
    }

    return;
}

# TODO init_arg => undef
sub _new ( $self, @args ) {
    my $default  = q[];
    my $required = q[];

    my $attrs = $ATTRS->{$self};
    my @attr_default_coderef;

    if ($attrs) {
        while ( my ( $attr, $spec ) = each $attrs->%* ) {
            if ( $spec->{required} ) {
                $required .= qq[die qq[Class "\$self" attribute "$attr" is required] if !exists \$args->{$attr};\n];
            }

            if ( exists $spec->{default} && ( !$spec->{is} || $spec->{is} ne 'lazy' ) ) {
                if ( is_coderef $spec->{default} ) {
                    push @attr_default_coderef, $attrs->{$attr}->{default};

                    $default .= qq[\$args->{$attr} = &{\$attr_default_coderef[$#attr_default_coderef]} if !exists \$args->{$attr};\n];
                }
                else {
                    $default .= qq[\$args->{$attr} = qq[$attrs->{$attr}->{default}] if !exists \$args->{$attr};\n];
                }
            }
        }
    }

    my $buildargs = do {
        if ( $self->can('BUILDARGS') ) {
            <<'PERL';
my $args = $self->BUILDARGS(@_);

if (!defined $args) {
    $args = {};
}
elsif (!Pcore::Util::Scalar::is_plain_hashref $args) {
    die qq["$self\::BUILDARGS" method didn't returned HashRef];
}

PERL
        }
        else {
            q[my $args = Pcore::Util::Scalar::is_plain_hashref $_[0] ? {$_[0]->%*} : @_ ? {@_} : {};];
        }
    };

    my $build = do {
        no strict qw[refs];

        join q[ ], map {qq[\$self->$_\::BUILD(\$args);]} grep { *{"$_\::BUILD"}{CODE} } reverse mro::get_linear_isa($self)->@*;
    };

    no warnings qw[redefine];

    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $self;

sub new {
    my \$self = !Pcore::Util::Scalar::is_ref \$_[0] ? CORE::shift : Pcore::Util::Scalar::is_blessed_ref \$_[0] ? CORE::ref CORE::shift : die qq[Invalid invoker for "$self\::new" constructor];

    $buildargs

    $required

    $default

    \$self = bless \$args, \$self;

    $build

    return \$self;
}
PERL

    return $self->new(@args);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 14, 69, 157, 229     | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 176                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_new' declared but not used         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 217                  | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::OOP::Class

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
