package Pcore::Src::SCM::Git;

use Pcore -class;

extends qw[Pcore::Src::SCM];

has '+is_git' => ( default => 1 );

sub _build_upstream ($self) {
    if ( -f $self->root . '/.git/config' ) {
        my $config = P->file->read_text( $self->root . '/.git/config' );

        return Pcore::Src::SCM::Upstream->new( { uri => $1, clone_is_git => 1 } ) if $config->$* =~ /\s*url\s*=\s*(.+?)$/sm;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::SCM::Git

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
