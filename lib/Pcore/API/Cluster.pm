package Pcore::API::Cluster;

use Pcore -class;

extends qw[Pcore::API::Client];

with qw[Pcore::API::Server::Auth];

sub set_root_password ( $self, $password = undef, $cb ) {

    # can't set root password on remote cluster
    return;
}

sub upload_api_map ( $self, $api_map, $cb ) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Cluster

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
