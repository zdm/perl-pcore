package Pcore::CDN::Bucket::s3;

use Pcore -class;
use Pcore::API::S3;

with qw[Pcore::CDN::Bucket];

has bucket   => ( required => 1 );
has region   => ( required => 1 );
has endpoint => ( required => 1 );
has key      => ( required => 1 );
has secret   => ( required => 1 );

has prefix => ( init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->{prefix} = "https://$self->{bucket}.$self->{region}.$self->{endpoint}";

    return;
}

sub get_url ( $self, $path ) {
    return $self->{prefix} . $path;
}

sub get_nginx_cfg ($self) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN::Bucket::s3

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
