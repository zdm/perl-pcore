package Pcore::Proxy::Pool::Proxy;

use Pcore qw[-class];

extends qw[Pcore::Proxy];

has _source => ( is => 'ro', isa => ConsumerOf ['Pcore::Proxy::Source'], required => 1, weak_ref => 1 );

has threads => ( is => 'ro', default => 0, init_arg => undef );    # current threads (running request through this proxy)

has _check_enqueued  => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # proxy already in check queue
has _check_next_time => ( is => 'ro', isa => Int,  default => 0, init_arg => undef );    # next disabled proxy check time
has _check_failure   => ( is => 'ro', isa => Int,  default => 0, init_arg => undef );    # number of serial check failures

around new => sub ( $orig, $self, $uri, $source ) {
    if ( my $args = $self->_parse_uri($uri) ) {
        $args->{_source} = $source;

        $self->$orig($args);
    }
    else {
        return;
    }
};

no Pcore;

sub disable ( $self, $timeout = undef ) {
    $self->_source->disable_proxy( $self, $timeout );

    return;
}

sub ban ( $self, $key, $timeout = undef ) {
    $self->_source->ban_proxy( $self, $key, $timeout );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Proxy::Pool::Proxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
