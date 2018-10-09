package Pcore::CDN::Bucket::digitalocean;

use Pcore -class;
use Pcore::API::S3;

extends qw[Pcore::CDN::Bucket::s3];

has bucket => ( required => 1 );
has region => ( required => 1 );
has key    => ( required => 1 );
has secret => ( required => 1 );
has edge_default => 0;

has service => ( 's3', init_arg => undef );
has endpoint => ( 'digitaloceanspaces.com', init_arg => undef );
has prefix      => ( init_arg => undef );
has prefix_edge => ( init_arg => undef );
has s3          => ( init_arg => undef );    # InstanceOf['Pcore::API::S3']

sub BUILD ( $self, $args ) {
    $self->{prefix} = "https://$self->{bucket}.$self->{region}.$self->{endpoint}";

    $self->{prefix_edge} = "https://$self->{bucket}.$self->{region}.cdn.$self->{endpoint}";

    return;
}

sub get_nginx_cfg ($self) {
    return;
}

sub s3 ($self) {
    if ( !exists $self->{s3} ) {
        $self->{s3} = Pcore::API::S3->new( $self->%{qw[key secret bucket region endpoint service]} );
    }

    return $self->{s3};
}

sub write ( $self, $path, $data, @args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return $self->s3->upload( $path, $data, @args );
}

sub get_url ( $self, $path ) {
    if ( $self->{edge_default} ) {
        return $self->{prefix_edge} . $path;
    }
    else {
        return $self->{prefix} . $path;
    }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN::Bucket::digitalocean

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
