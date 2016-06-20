package Pcore::HTTP::Server::Controller;

use Pcore -role;

has env => ( is => 'ro', isa => HashRef, required => 1 );
has router => ( is => 'ro', isa => ConsumerOf ['Pcore::HTTP::Server::Router'], required => 1 );
has path      => ( is => 'ro', isa => Str, required => 1 );
has path_tail => ( is => 'ro', isa => Str, required => 1 );

requires qw[run];

sub return_static ($self) {
    if ( $self->path_tail && $self->path_tail->is_file ) {
        if ( my $path = $ENV->share->get( $self->path . $self->path_tail, storage => 'www' ) ) {
            my $data = P->file->read_bin($path);

            $path = P->path($path);

            return [ 200, [ 'Content-Type' => $path->mime_type ], $data ];
        }
        else {
            return [ 404, [], [] ];    # Not Found
        }
    }
    else {
        return [ 403, [], [] ];        # Forbidden
    }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Controller

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
