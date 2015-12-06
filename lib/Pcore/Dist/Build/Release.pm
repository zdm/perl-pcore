package Pcore::Dist::Build::Release;

use Pcore qw[-class];
use Pod::Markdown;
use CPAN::Meta;
use Module::Metadata;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has major  => ( is => 'ro', isa => Bool, default => 0 );
has minor  => ( is => 'ro', isa => Bool, default => 0 );
has bugfix => ( is => 'ro', isa => Bool, default => 0 );

no Pcore;

sub run ($self) {
    say dump $self;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Release

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
