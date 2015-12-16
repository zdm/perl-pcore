package Pcore::Handle::API::Google::Youtube::Videos;

use Pcore -class;

with qw[Pcore::Handle::API::Google::Youtube];

has api_path => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub _build_api_path {
    my $self = shift;

    return 'youtube/v3/videos/';
}

sub api_read {
    my $self = shift;

    my $json = $self->call(@_);

    my $res = {};

    for my $item ( $json->{items}->@* ) {
        $res->{ $item->{id} } = $item;
    }

    return $res;
}

1;
__END__
=pod

=encoding utf8

=cut
