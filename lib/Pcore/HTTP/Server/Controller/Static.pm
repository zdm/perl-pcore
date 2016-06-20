package Pcore::HTTP::Server::Controller::Static;

use Pcore -role;

with qw[Pcore::HTTP::Server::Controller];

sub run ($self) {
    if ( my $path = $ENV->share->get( $self->path . $self->path_tail, storage => 'www' ) ) {
        my $data = P->file->read_bin($path);

        $path = P->path($path);

        return [ 200, [ 'Content-Type' => $path->mime_type ], $data ];
    }
    else {
        return [404];
    }
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Controller::Static

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
