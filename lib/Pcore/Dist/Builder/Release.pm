package Pcore::Dist::Builder::Release;

use Pcore qw[-class];

with qw[Pcore::Dist::Builder];

has type => ( is => 'ro', isa => Enum [qw[major minor bugfix]], required => 1 );

no Pcore;

sub cli_arg ($self) {
    return [    #
        {   name     => 'release_type',
            type     => 'Str',
            required => 1,
        },
    ];
}

sub cli_validate ( $self, $opt, $arg, $rest ) {
    return q[Release type should be specified] if $arg || !( $arg ~~ [qw[major minor bugfix]] );

    return;
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new( { type => $arg->[0] } )->run;

    return;
}

sub run ($self) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder::Release - release distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
