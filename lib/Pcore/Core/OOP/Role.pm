package Pcore::Core::OOP::Role;

use Pcore;
use Pcore::Util::Scalar qw[is_ref is_plain_hashref is_coderef];

our ( %BASE, %REG );

sub import ( $self, $caller = undef ) {
    $caller //= caller;

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
        next if $REG{$caller}{does}{$role};

        if ( !exists $BASE{$role} ) {
            my $name = $role =~ s[::][/]smgr . '.pm';

            require $name if !exists $INC{$name};

            $BASE{$role} = undef;
        }

        # register does
        $REG{$caller}{does}{$role} = 1;

        # merge does
        $REG{$caller}{does}->@{ keys $REG{$role}{does}->%* } = values $REG{$role}{does}->%*;

        # merge attributes
        while ( my ( $attr, $spec ) = each $REG{$role}{attr}->%* ) {
            die qq[Impossible to redefine attribute "$attr"] if exists $REG{$caller}{attr}{$attr};

            has( $caller, $attr, $spec );
        }

        # TODO merge modifiers
        # push $REG{$caller}{around}->@*, $REG{$role}{around}->@*;

        # TODO
        # merge methods
    }

    return;
}

sub _has ( $attr, $spec = undef ) {
    my $caller = caller;

    has( $caller, $attr, $spec );

    return;
}

sub has ( $caller, $attr, $spec = undef ) {
    if ( !defined $spec ) {
        $spec = { is => q[] };
    }
    elsif ( !is_plain_hashref $spec) {
        $spec = { is => q[], default => $spec };
    }
    else {
        $spec->{is} //= q[];
    }

    # check default value
    die qq[Class "$caller" attribute "$attr" default value can be "Scalar" or "CodeRef"] if exists $spec->{default} && !( !is_ref $spec->{default} || is_coderef $spec->{default} );

    if ( my $current_spec = $REG{$caller}{attr}{$attr} ) {
        if ( $spec->{is} and $spec->{is} ne $current_spec->{is} ) {
            die qq[Class "$caller" attribute "$attr" not allowed to redefine parent attribute "is" property];
        }

        # redefine attr
        $REG{$caller}{attr}{$attr} = { $current_spec->%*, $spec->%* };
    }
    else {
        $REG{$caller}{attr}{$attr} = $spec;
    }

    return;
}

sub _around ( $sub, $code ) {
    my $caller = caller;

    push $REG{$caller}{around}{$sub}->@*, $code;

    return;
}

1;
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
