package Pcore::Util::File1::TempDir;

use Pcore -class;
use File::Path qw[];    ## no critic qw[Modules::ProhibitEvilModules]

extends qw[Pcore::Util::Path];

our @DEFERRED_UNLINK;

END {
    for my $path (@DEFERRED_UNLINK) {
        File::Path::remove_tree( $path, safe => 0 );
    }
}

sub DESTROY ($self) {
    $self->rmtree( safe => 0 );

    push @DEFERRED_UNLINK, $self->encoded if -d $self;

    return;
}

around new => sub ( $orig, $self, @args ) { return $self->SUPER::new(@args) };

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File1::TempDir

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
