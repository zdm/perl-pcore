package Pcore::PSGI::Middleware::Example;

use Pcore qw[-class];
extends qw[Pcore::PSGI::Middleware];

sub call {
    my $self = shift;
    my $env  = shift;

    return $self->app->($env);
}

1;
__END__
=pod

=encoding utf8

=cut
