package Pcore::API::Server::Session;

use Pcore -class;

has api => ( is => 'ro', isa => ConsumerOf ['Pcore::API::Server'], required => 1 );
has uid     => ( is => 'ro', isa => PositiveInt, required => 1 );
has role_id => ( is => 'ro', isa => PositiveInt, required => 1 );

has allowed_methods => ( is => 'lazy', isa => HashRef, init_arg => undef );

# TODO resolve role_id -> methods
sub _build_allowed_methods ($self) {
    return {};
}

sub is_root ($self) {
    return $self->{uid} == 1;
}

sub api_call ( $self, $version, $class, $method, @ ) {
    my $cb = $_[-1];

    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $on_finish = sub ( $status, $reason = undef, $result = undef ) {
        my $api_res = Pcore::API::Response->new( { status => $status, defined $reason ? ( reason => $reason ) : () } );

        $api_res->{result} = $result;

        $cb->($api_res) if $cb;

        $blocking_cv->($api_res) if $blocking_cv;

        return;
    };

    my $method_id = join q[/], $version, $class, $method;

    my $map = $self->api->map->{$method_id};

    if ( !$map ) {
        $on_finish->( 404, q[API method was not found] );
    }
    else {

        # TODO check auth
        if ( $self->{uid} != 1 && !exists $self->allowed_methods->{$version}->{$class}->{$method} ) {
            $on_finish->( 401, q[Unauthorized] );
        }
        else {
            my $obj = bless { api => $self }, $map->{class};

            $obj->$method( splice( @_, 4, -1 ), $on_finish );
        }
    }

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Session

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
