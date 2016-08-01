package Pcore::App::HTTP::Controller;

use Pcore -role;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App::HTTP'],             required => 1 );
has req => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server::Request'], required => 1 );
has path => ( is => 'ro', isa => Str, required => 1 );
has path_tail => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );

requires qw[run];

sub return_static ($self) {
    if ( $self->path_tail && $self->path_tail->is_file ) {
        if ( my $path = $ENV->share->get( $self->path . $self->path_tail, storage => 'www' ) ) {
            my $data = P->file->read_bin($path);

            $path = P->path($path);

            $self->req->write( 200, [ 'Content-Type' => $path->mime_type ], $data )->finish;
        }
        else {
            $self->req->write(404)->finish;    # not found
        }
    }
    else {
        $self->req->write(403)->finish;        # forbidden
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::HTTP::Controller

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
