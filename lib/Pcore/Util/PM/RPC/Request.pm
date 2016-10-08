package Pcore::Util::PM::RPC::Request;

use Pcore -class;
use Pcore::Util::Status::API::Keyword qw[status];

use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return _respond( $self, @_ ) };
  },
  fallback => undef;

has cb => ( is => 'ro', isa => Maybe [CodeRef] );

has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && !$self->{_response_status} && $self->{cb} ) {

        # RPC request object destroyed without return any result, this is possible run-time error in AE callback
        $self->{cb}->( status 500 );
    }

    return;
}

sub _respond ( $self, @ ) {
    die q[Already responded] if $self->{_response_status};

    $self->{_response_status} = 1;

    # remove callback
    if ( my $cb = delete $self->{cb} ) {
        my $status = blessed $_[1] ? $_[1] : status splice @_, 1;

        # return response, if callback is defined
        $cb->( 200, $status );
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
