package Pcore::AnyEvent::Proxy::Source::File;

use Pcore qw[-class];

with qw[Pcore::AnyEvent::Proxy::Source];

has path => ( is => 'ro', isa => Str, required => 1 );

no Pcore;

sub load ( $self, $cb ) {
    my $proxies;

    if ( -f $self->path ) {
        for my $uri ( P->file->read_lines( $self->path )->@* ) {
            P->text->trim($uri);

            push $proxies->@*, $uri if $uri;
        }
    }

    $cb->($proxies);

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
