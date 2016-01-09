package Pcore::API::Bitbucket::Issue;

use Pcore -class;

has api => ( is => 'ro', isa => InstanceOf ['Pcore::API::Bitbucket'], required => 1 );

sub set_milestone ($self) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Bitbucket::Issue

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
