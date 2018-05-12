package Pcore::Core::OOP::Role;

use Pcore;
use Pcore::Core::OOP::Class qw[];
use Pcore::Util::Scalar qw[is_ref is_plain_hashref is_coderef];

sub import ( $self, $caller = undef ) {
    $caller //= caller;

    # register role
    $Pcore::Core::OOP::Class::REG{$caller}{is_role} = 1;

    eval <<"PERL";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
package $caller;

sub does { Pcore::Core::OOP::Class::_does(\@_) };
PERL

    {
        no strict qw[refs];

        *{"$caller\::with"}   = \&_with;
        *{"$caller\::has"}    = \&_has;
        *{"$caller\::around"} = \&_around;
    }

    return;
}

sub _with (@roles) {
    my $caller = caller;

    for my $role (@roles) {

        # role is already applied
        die if $Pcore::Core::OOP::Class::REG{$caller}{does}{$role};

        Pcore::Core::OOP::Class::load_class($role);

        die qq[Class "$caller" is not a role] if !$Pcore::Core::OOP::Class::REG{$role}{is_role};

        # merge does
        $Pcore::Core::OOP::Class::REG{$caller}{does}->@{ $role, keys $Pcore::Core::OOP::Class::REG{$role}{does}->%* } = ();    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

        # merge attributes
        while ( my ( $attr, $spec ) = each $Pcore::Core::OOP::Class::REG{$role}{attr}->%* ) {
            Pcore::Core::OOP::Class::add_attribute( $caller, $attr, $spec, 0, 0 );
        }

        # merge around
        push $Pcore::Core::OOP::Class::REG{$caller}{around}->@*, $Pcore::Core::OOP::Class::REG{$role}{around}->@* if $Pcore::Core::OOP::Class::REG{$role}{around};
    }

    # merge methods
    Pcore::Core::OOP::Class::export_methods( \@roles, $caller );

    return;
}

sub _has ( $attr, $spec = undef ) {
    my $caller = caller;

    Pcore::Core::OOP::Class::add_attribute( $caller, $attr, $spec, 0, 0 );

    return;
}

sub _around ( $name, $code ) {
    my $caller = caller;

    push $Pcore::Core::OOP::Class::REG{$caller}{around}{$name}->@*, $code;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 13                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::OOP::Role

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
