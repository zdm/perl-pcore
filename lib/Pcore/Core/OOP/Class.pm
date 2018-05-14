package Pcore::Core::OOP::Class;

use Pcore;
use Pcore::Util::Scalar qw[is_ref is_plain_arrayref is_plain_hashref is_coderef];
use Class::XSAccessor qw[];
use Package::Stash::XS qw[];
use Sub::Util qw[];       ## no critic qw[Modules::ProhibitEvilModules]
use Data::Dumper qw[];    ## no critic qw[Modules::ProhibitEvilModules]

our %REG;

sub import ( $self, $caller = undef ) {
    $caller //= caller;

    eval <<"PERL";        ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub does { Pcore::Core::OOP::Class::_does(\@_) };
PERL

    _defer_sub( $caller, new => sub { return _build_constructor($caller) } );

    {
        no strict qw[refs];    ## no critic qw[TestingAndDebugging::ProhibitProlongedStrictureOverride]

        *{"$caller\::extends"} = \&_extends;
        *{"$caller\::with"}    = \&_with;
        *{"$caller\::has"}     = \&_has;
        *{"$caller\::around"}  = \&_around;
    }

    return;
}

sub load_class ($class) {
    my $name = $class =~ s[::][/]smgr . '.pm';

    require $name if !exists $INC{$name};

    return;
}

sub _does ( $self, $role ) {
    $self = ref $self if is_ref $self;

    return exists $REG{$self}{does}{$role};
}

sub _extends (@superclasses) {
    my $caller = caller;

    for my $base (@superclasses) {
        load_class($base);

        no strict qw[refs];

        push @{"$caller\::ISA"}, $base;

        die qq[Class "$caller" multiple inheritance is disabled. Use roles or redesign your classes] if @{"$caller\::ISA"} > 1;

        # merge attributes
        while ( my ( $attr, $spec ) = each $REG{$base}{attr}->%* ) {
            add_attribute( $caller, $attr, $spec, 1, 1 );
        }
    }

    return;
}

sub _with (@roles) {
    my $caller = caller;

    for my $role (@roles) {

        # role is already applied
        die if $REG{$caller}{does}{$role};

        load_class($role);

        die qq[Class "$caller" is not a role] if !$REG{$role}{is_role};

        # merge does
        $REG{$caller}{does}->@{ $role, keys $REG{$role}{does}->%* } = ();    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

        # merge attributes
        while ( my ( $attr, $spec ) = each $REG{$role}{attr}->%* ) {
            add_attribute( $caller, $attr, $spec, 0, 1 );
        }
    }

    # merge methods
    export_methods( \@roles, $caller );

    #check requires,  install around
    for my $role (@roles) {
        if ( $REG{$role}{requires} ) {
            my @missed_methods = grep { !$caller->can($_) } $REG{$role}{requires}->@*;

            die qq[Class "$caller" required methods are missed: ] . join q[, ], map {qq["$_"]} @missed_methods if @missed_methods;
        }

        _install_around( $caller, $REG{$role}{around} ) if $REG{$role}{around};
    }

    return;
}

sub export_methods ( $roles, $to ) {
    my $to_role_methods;

    if ( $REG{$to}{is_role} ) {
        $to_role_methods = $REG{$to}{method} //= {
            map { $_ => 1 }
              grep {
                my $fullname = Sub::Util::subname( *{"$to\::$_"}{CODE} );

                "$to\::$_" eq $fullname || substr( $_, 0, 1 ) eq '(';
              } Package::Stash::XS->new($to)->list_all_symbols('CODE')
        };
    }

    for my $role ( $roles->@* ) {
        no strict qw[refs];

        my $role_methods = $REG{$role}{method} //= {
            map { $_ => 1 }
              grep {
                my $fullname = Sub::Util::subname( *{"$role\::$_"}{CODE} );

                "$role\::$_" eq $fullname || substr( $_, 0, 1 ) eq '(';
              } Package::Stash::XS->new($role)->list_all_symbols('CODE')
        };

        for my $name ( grep { !defined *{"$to\::$_"}{CODE} } keys $role_methods->%* ) {
            $to_role_methods->{$name} = 1 if $to_role_methods;

            *{"$to\::$name"} = *{"$role\::$name"}{CODE};
        }
    }

    return;
}

sub _has ( $attr, @spec ) {
    my $caller = caller;

    add_attribute( $caller, $attr, \@spec, 0, 1 );

    return;
}

sub _around ( $name, $code ) {
    my $caller = caller;

    _install_around( $caller, { $name => [$code] } );

    return;
}

sub _install_around ( $to, $spec ) {
    for my $name ( keys $spec->%* ) {
        for my $code ( $spec->{$name}->@* ) {
            my $wrapped = $to->can($name);

            die qq[Class "$to" method modifier "around" requires method "$name"] if !$wrapped;

            no warnings qw[redefine];
            eval qq[package $to; sub $name { \$code->( \$wrapped, \@_ ) }];    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
        }
    }

    return;
}

sub add_attribute ( $caller, $attr, $spec, $is_base, $install_accessors ) {
    if ( is_plain_arrayref $spec) {
        if ( $spec->@* % 2 ) {
            $spec = { default => shift $spec->@*, $spec->@* };
        }
        else {
            $spec = { $spec->@* };
        }

        $spec->{is} //= q[];
    }

    # check default value
    die qq[Class "$caller" attribute "$attr" default value can be "Scalar" or "CodeRef"] if exists $spec->{default} && !( !is_ref $spec->{default} || is_coderef $spec->{default} );

    # redefine attribute
    if ( my $current_spec = $REG{$caller}{attr}{$attr} ) {
        if ( $spec->{is} and $spec->{is} ne $current_spec->{is} ) {
            die qq[Class "$caller" attribute "$attr" not allowed to redefine parent attribute "is" property];
        }

        # merge attribute spec
        if ($is_base) {
            $spec = { $spec->%*, $current_spec->%* };
        }
        else {
            $spec = { $current_spec->%*, $spec->%* };
        }
    }

    $REG{$caller}{attr}{$attr} = $spec;

    # install accessors
    if ( $install_accessors && $spec->{is} ) {

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

sub _defer_sub ( $caller, $name, $code ) {
    my $defer = [];

    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub $name {
    if ( !defined \$defer->[1] ) {

        # undefer sub
        \$defer->[1] = \$code->();

        # install, if wasn't changed
        no strict qw[refs];
        no warnings qw[redefine];

        *{'$caller\::$name'} = \$defer->[1] if *{'$caller\::$name'}{CODE} eq \$defer->[0];
    }

    goto &{\$defer->[1]};
};
PERL

    no strict qw[refs];

    $defer->[0] = *{"$caller\::$name"}{CODE};

    return;
}

sub _build_constructor ( $self ) {
    my $default1 = q[];
    my $default2 = q[];
    my $required = q[];
    my @attr_default_coderef;

    while ( my ( $attr, $spec ) = each $REG{$self}{attr}->%* ) {
        if ( $spec->{required} ) {
            $required .= qq[die qq[Class "\$self" attribute "$attr" is required] if !exists \$args->{$attr};\n];
        }

        if ( exists $spec->{default} && ( !$spec->{is} || $spec->{is} ne 'lazy' ) ) {
            if ( !is_ref $spec->{default} ) {
                local $Data::Dumper::Useqq = 1;
                local $Data::Dumper::Terse = 1;

                $default1 .= qq[\$args->{$attr} = @{[ Data::Dumper::Dumper $spec->{default} ]} if !exists \$args->{$attr};\n];
            }
            else {
                push @attr_default_coderef, $spec->{default};

                $default2 .= qq[\$args->{$attr} = &{\$attr_default_coderef[$#attr_default_coderef]}(\$self) if !exists \$args->{$attr};\n];
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

        join q[ ], map {qq[\$self->$_\::BUILD(\$args);]}
          grep { defined *{"$_\::BUILD"} && *{"$_\::BUILD"}{CODE} }
          reverse mro::get_linear_isa($self)->@*;
    };

    no warnings qw[redefine];

    return eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $self;

sub {
    my \$self = !Pcore::Util::Scalar::is_ref \$_[0] ? CORE::shift : Pcore::Util::Scalar::is_blessed_ref \$_[0] ? CORE::ref CORE::shift : die qq[Invalid invoker for "$self\::new" constructor];

    $buildargs

    $required

    $default1

    \$self = bless \$args, \$self;

    $default2

    $build

    return \$self;
};
PERL
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 15, 168, 236, 249,   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |      | 263, 285, 367        |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 43                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_does' declared but not used        |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 175                  | Subroutines::ProhibitExcessComplexity - Subroutine "add_attribute" with high complexity score (22)             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 175                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 353                  | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
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
