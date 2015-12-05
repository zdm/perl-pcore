package Pcore::Dist::Build::PAR::Script;

use Pcore qw[-class];
use Archive::Zip qw[];
use PAR::Filter;
use Pcore::Src::File;
use Term::ANSIColor qw[:constants];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );
has script  => ( is => 'ro', isa => Str,     required => 1 );
has release => ( is => 'ro', isa => Bool,    required => 1 );
has crypt   => ( is => 'ro', isa => Bool,    required => 1 );
has upx     => ( is => 'ro', isa => Bool,    required => 1 );
has clean   => ( is => 'ro', isa => Bool,    required => 1 );
has pardeps => ( is => 'ro', isa => HashRef, required => 1 );
has resources => ( is => 'ro', isa => Maybe [ArrayRef] );

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

Pcore::Dist::Build::PAR::Script

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
