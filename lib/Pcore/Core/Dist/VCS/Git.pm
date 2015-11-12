package Pcore::Core::Dist::VCS::Git;

use Pcore qw[-class];

extends qw[Pcore::Core::Dist::VCS];

has '+is_git' => ( default => 1 );

no Pcore;

sub _build_upstream ($self) {
    if ( -f $self->root . '/.git/config' ) {
        my $config = P->file->read_text( $self->root . '/.git/config' );

        return Pcore::Core::Dist::VCS::Upstream->new( { uri => $1, clone_is_git => 1 } ) if $config->$* =~ /\s*url\s*=\s*(.+?)$/sm;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Dist::VCS::Git

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
