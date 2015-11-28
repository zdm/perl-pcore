package Pcore::Dist::Builder;

use Pcore qw[-role];
use Pcore::Dist;

# perl CPAN distribution
# http://www.perlmonks.org/?node_id=1009586

with qw[Pcore::Core::CLI::Cmd Pcore::Dist::BuilderUtil];

has dist => ( is => 'lazy', isa => InstanceOf ['Pcore::Dist'] );

around cli_run => sub ( $orig, $self, @args ) {
    my $chdir_guard = P->file->chdir( $self->dist->root );

    return $self->$orig(@args);
};

no Pcore;

sub _build_dist ($self) {
    return Pcore::Dist->new(q[.]);
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
