package Pcore::API::Call::Action::Request;

use Pcore -class;
use Pcore::API::Call::Action::Response;

with qw[Pcore::API::Call::Action Pcore::Util::UA::Uploads];

has '+tid' => ( is => 'rwp' );

has '+data' => ( isa => HashRef | ArrayRef );

has is_response => ( is => 'lazy', isa => Bool, default => 0, init_arg => undef );

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    delete $args->{data} if !$args->{data};

    return $args;
}

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->add_uploads( $args->{uploads} ) if $args->{uploads};

    return;
}

sub response {
    my $self = shift;
    my %args = @_;

    $args{type}   = $self->type;
    $args{action} = $self->action;
    $args{method} = $self->method;
    $args{tid}    = $self->tid;

    return Pcore::API::Call::Action::Response->new( \%args );
}

sub exception {
    my $self    = shift;
    my $message = shift;
    my %args    = @_;

    $args{message} = $message if defined $message;

    $args{success} = 0;

    return $self->response(%args);
}

sub TO_DATA {
    my $self = shift;

    my $json = {
        type   => $self->type,
        action => $self->action,
        method => $self->method,
        tid    => $self->tid,
    };

    $json->{data} = $self->data if $self->has_data;

    return $json;
}

1;
__END__
=pod

=encoding utf8

=cut
