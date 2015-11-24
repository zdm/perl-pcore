package Pcore::Dist::Builder::Test;

use Pcore qw[-class];

with qw[Pcore::Dist::Builder];

has release => ( is => 'ro', isa => Bool, default => 0 );
has author  => ( is => 'ro', isa => Bool, default => 0 );
has smoke   => ( is => 'ro', isa => Bool, default => 0 );

no Pcore;

sub cli_opt ($self) {
    return {
        release => { desc => 'run release tests', },
        author  => { desc => 'run author tests', },
        smoke   => { desc => 'run smoke tests', },
    };
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new($opt)->run;

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

Pcore::Dist::Builder::Test - test distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
