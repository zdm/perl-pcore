package Pcore::App::API::Auth::Backend::Cluster;

use Pcore -class;

with qw[Pcore::App::API::Auth::Backend];

has uri => ( is => 'ro', isa => ConsumerOf ['Pcore::Util::URI'], required => 1 );

sub init ( $self, $cb ) {
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
