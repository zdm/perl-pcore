package Pcore::Util::PM::Process::RPC;

use Pcore -role;

has cv  => ( is => 'ro', isa => InstanceOf ['AnyEvent::CondVar'], required => 1 );
has in  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], required => 1 );
has out => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], required => 1 );

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::Process::RPC

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
