package Pcore::API::Server::Authenticated;

use Pcore -class;

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

sub api_call ( $self, $version, $class, $method, $data, $auth, $cb ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $version //= $self->default_version;

    my $on_finish = sub ( $status, $reason = undef, $result = undef ) {
        my $api_res = Pcore::API::Response->new( { status => $status, defined $reason ? ( reason => $reason ) : () } );

        $api_res->{result} = $result;

        $cb->($api_res) if $cb;

        $blocking_cv->($api_res) if $blocking_cv;

        return;
    };

    my $map = $self->{map}->{$version}->{$class};

    if ( !$map ) {
        $on_finish->( 404, q[API class was not found] );
    }
    elsif ( !exists $map->{method}->{$method} ) {
        $on_finish->( 404, q[API method was not found] );
    }
    else {

        # TODO check auth
        if (0) {
            $on_finish->( 401, q[Unauthorized] );
        }
        else {
            my $obj = bless { api => $self }, $map->{class};

            $obj->$method( $data, $on_finish );
        }
    }

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 19                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Authenticated

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
