package Pcore::API::Majestic;

use Pcore -class, -res;

has api_key     => ( required => 1 );
has max_threads => 3;
has proxy       => ();

has _semaphore => sub ($self) { Coro::Semaphore->new( $self->{max_threads} ) }, is => 'lazy';

sub get_backlinks ( $self, $domain, %args ) {
    my $params = {
        cmd                  => 'GetAnchorText',
        datasource           => 'fresh',
        item                 => $domain,
        Count                => $args{num_anchors} || 10,    # Number of results to be returned back. Max. 1_000
        TextMode             => 0,
        Mode                 => 0,
        FilterAnchorText     => undef,
        FilterAnchorTextMode => 0,
        FilterRefDomain      => undef,
        UsePrefixScan        => 0,
    };

    return $self->_req($params);
}

sub _req ( $self, $params ) {
    my $guard = $self->{max_threads} && $self->_semaphore->guard;

    my $url = "http://api.majestic.com/api/json?app_api_key=$self->{api_key}&" . P->data->to_uri($params);

    my $res = P->http->get( $url, proxy => $self->{proxy} );

    return $res if !$res;

    my $data = eval { P->data->from_json( $res->{data} ) };

    return res [ 500, 'Error decoding response' ] if $@;

    if ( $data->{Code} ne 'OK' ) {
        return res [ 400, $data->{ErrorMessage} ];
    }

    return res 200, $data;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Majestic

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
