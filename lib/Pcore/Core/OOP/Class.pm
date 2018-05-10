package Pcore::Core::OOP::Class;

use Pcore;
use Pcore::Util::Scalar qw[is_ref is_coderef];
use Class::XSAccessor qw[];

our (%EXTENDS);
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
        *{"$caller\::has"}     = \&has;
    }

    return;
}

sub extends (@superclasses) {
    my $caller = caller;

    for my $base (@superclasses) {
        if ( !exists $EXTENDS{$base} ) {
            my $name = $base =~ s[::][/]smgr . '.pm';

            require $name if !exists $INC{$name};

            $EXTENDS{$base} = undef;
        }

        no strict qw[refs];

        push @{"$caller\::ISA"}, $base;
    }

    return;
}

# TODO warnings on use "is" property
# TODO do not allow to redefine "is"
# TODO do not install accessor, if default value wasn't changed;
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

            # attr has default property
            if ( exists $spec->{default} ) {

                # default is a coderef
                if ( is_coderef $spec->{default} ) {
                    my $sub = $spec->{default};

                    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub $attr {
    \$_[0]->{$attr} = &{\$sub}(\$_[0]) if !exists \$_[0]->{$attr};

    return \$_[0]->{$attr};
}
PERL
                }

                # default is a plain scalar
                else {
                    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub $attr {
    \$_[0]->{$attr} = qq[$spec->{default}] if !exists \$_[0]->{$attr};

    return \$_[0]->{$attr};
}
PERL
                }
            }

            # use attr builder
            else {
                eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub $attr {
    \$_[0]->{$attr} = \$_[0]->_build_$attr if !exists \$_[0]->{$attr};

    return \$_[0]->{$attr};
}
PERL
            }
        }
        else {
            die qq[Invalid "is" type for attribute "$attr" in class "$caller"];
        }
    }

    return;
}

# TODO init_arg => undef
sub _new ( $self, @args ) {
    my $default1 = q[];
    my $default2 = q[];
    my $required = q[];
    my $attrs    = $ATTRS->{$self};
    my @attr_default_coderef;

    if ($attrs) {
        while ( my ( $attr, $spec ) = each $attrs->%* ) {
            if ( $spec->{required} ) {
                $required .= qq[die qq[Class "\$self" attribute "$attr" is required] if !exists \$args->{$attr};\n];
            }

            if ( exists $spec->{default} && ( !$spec->{is} || $spec->{is} ne 'lazy' ) ) {
                if ( !is_ref $spec->{default} ) {
                    $default1 .= qq[\$args->{$attr} = qq[$attrs->{$attr}->{default}] if !exists \$args->{$attr};\n];
                }
                else {
                    push @attr_default_coderef, $attrs->{$attr}->{default};

                    $default2 .= qq[\$args->{$attr} = &{\$attr_default_coderef[$#attr_default_coderef]}(\$self) if !exists \$args->{$attr};\n];
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

    $default1

    \$self = bless \$args, \$self;

    $default2

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
## |    3 | 13, 120, 133, 147,   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |      | 220                  |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 167                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_new' declared but not used         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 208                  | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
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
