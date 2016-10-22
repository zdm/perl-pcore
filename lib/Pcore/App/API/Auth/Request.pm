package Pcore::App::API::Auth::Request;

use Pcore -class, -status;
use Pcore::Util::Scalar qw[blessed];

use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return _respond( $self, @_ ) };
  },
  fallback => 1;

has auth => ( is => 'ro', isa => InstanceOf ['Pcore::App::API::Auth'], required => 1 );
has _cb => ( is => 'ro', isa => Maybe [CodeRef] );

has _responded => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # already responded

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && !$self->{_responded} && $self->{_cb} ) {

        # API request object destroyed without return any result, this is possible run-time error in AE callback
        _respond( $self, 500 );
    }

    return;
}

sub user_id ($self) {
    return $self->{auth}->{user_id};
}

sub user_name ($self) {
    return $self->{auth}->{user_name};
}

sub user_token_id ($self) {
    return $self->{auth}->{user_token_id};
}

sub app_id ($self) {
    return $self->{auth}->{app_id};
}

sub app_instance_id ($self) {
    return $self->{auth}->{app_instance_id};
}

sub is_root ($self) {
    return $self->{auth}->is_root;
}

sub wantarray ($self) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return !!$self->{_cb};
}

sub api_call ( $self, $method_id, @args ) {
    $self->{auth}->api_call( $method_id, @args );

    return;
}

sub _respond ( $self, @ ) {
    die q[Already responded] if $self->{_responded};

    $self->{_responded} = 1;

    # remove callback
    if ( my $cb = delete $self->{_cb} ) {

        # return response, if callback is defined
        $cb->( blessed $_[1] ? $_[1] : status splice @_, 1 );
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
