package Pcore::Dist::CLI;

use Pcore qw[-role];
use Pcore::Dist;

with qw[Pcore::Core::CLI::Cmd];

has require_dist => ( is => 'ro', isa => Bool, default => 1, init_arg => undef );
has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], init_arg => undef );

around run => sub ( $orig, $self ) {
    if ( $self->require_dist ) {
        if ( my $dist = Pcore::Dist->new( $PROC->{START_DIR} ) ) {
            $self->{dist} = $dist;

            chdir $dist->root or die;
        }
        else {
            say 'Pcore distribution was not found' . $LF;

            exit 3;
        }
    }

    return $self->$orig;
};

no Pcore;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
