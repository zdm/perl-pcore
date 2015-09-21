package Pcore::Core::H::Role::Wrapper;

use Pcore qw[-role];

with qw[Pcore::Core::H::Role];

requires qw[h_connect];

has h => ( is => 'lazy', builder => 'h_connect', predicate => 'h_is_connected', clearer => 1, init_arg => undef );

around h_disconnect => sub {
    my $orig = shift;
    my $self = shift;

    if ( $self->h_is_connected ) {
        $self->$orig if defined $self->{h};

        $self->clear_h;
    }

    return;
};

sub AUTOLOAD ( $self, @ ) {    ## no critic qw[ClassHierarchies::ProhibitAutoloading]
    my $method = our $AUTOLOAD =~ s/\A.*:://smr;

    my $class = ref $self || $self;

    {
        no strict qw[refs];

        *{ $class . q[::] . $method } = sub {
            my $self = shift;

            return $self->h->$method(@_);
        };
    }

    goto &{ $class . q[::] . $method };
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::H::Role::Wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
