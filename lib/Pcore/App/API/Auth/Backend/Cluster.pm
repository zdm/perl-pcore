package Pcore::App::API::Auth::Backend::Cluster;

use Pcore -class;

with qw[Pcore::App::API::Auth::Backend];

has uri => ( is => 'ro', isa => ConsumerOf ['Pcore::Util::URI'], required => 1 );

sub _build_host ($self) {
    return $self->uri->hostport;
}

sub init ( $self, $cb ) {
    $cb->( Pcore::Util::Status->new( { status => 200 } ) );

    return;
}

# TODO register app
# TODO upload api methods
sub register_app ( $self, $cb ) {

    # TODO if has instance token locally - create was connection and upload api methods
    # TODO if no instance token - send registration request via https (app_id, host);
    # - check for registration approval on timeout;
    # - on register - store token locally;
    # - upload api methods;

    $cb->( Pcore::Util::Status->new( { status => 200 } ) );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Backend::Cluster

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
