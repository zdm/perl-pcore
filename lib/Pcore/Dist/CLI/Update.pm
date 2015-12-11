package Pcore::Dist::CLI::Update;

use Pcore qw[-class];

with qw[Pcore::Dist::CLI];

no Pcore;

sub cli_abstract ($self) {
    return 'update README.md and LICENSE';
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run;

    return;
}

sub run ($self) {
    $self->dist->build->update;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Update - update README.md and LICENSE

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
