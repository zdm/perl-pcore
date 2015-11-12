package Pcore::Core::Dist::SCM::Hg;

use Pcore qw[-class];

extends qw[Pcore::Core::Dist::SCM];

has '+is_hg' => ( default => 1 );

no Pcore;

sub _build_upstream ($self) {
    if ( -f $self->root . '/.hg/hgrc' ) {
        my $hgrc = P->file->read_text( $self->root . '/.hg/hgrc' );

        return Pcore::Core::Dist::SCM::Upstream->new( { uri => $1, clone_is_hg => 1 } ) if $hgrc->$* =~ /default\s*=\s*(.+?)$/sm;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Dist::SCM::Hg

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
