package Pcore::CDN::Bucket::s3;

use Pcore -class;
use Pcore::API::S3;

with qw[Pcore::CDN::Bucket];

has bucket   => ( required => 1 );
has region   => ( required => 1 );
has endpoint => ( required => 1 );
has key      => ();
has secret   => ();
has service  => 's3';

has prefix => ( init_arg => undef );
has s3     => ( init_arg => undef );    # InstanceOf['Pcore::API::S3']

sub BUILD ( $self, $args ) {
    $self->{prefix} = "https://$self->{bucket}.$self->{region}.$self->{endpoint}";

    $self->{can_upload} = 1 if defined $self->{key} && defined $self->{secret};

    return;
}

sub s3 ($self) {
    if ( !exists $self->{s3} ) {
        $self->{s3} = Pcore::API::S3->new( $self->%{qw[key secret bucket region endpoint service]} );
    }

    return $self->{s3};
}

sub upload ( $self, $path, $data, @args ) {
    die q[Can't upload to bucket] if !$self->{can_upload};

    return $self->s3->upload( $path, $data, cache_control => $self->find_cache_control("/$path"), @args );
}

sub sync ( $self, @args ) {
    return $self->s3->sync(@args);
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
