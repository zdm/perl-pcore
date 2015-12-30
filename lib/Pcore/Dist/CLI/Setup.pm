package Pcore::Dist::CLI::Setup;

use Pcore -class;

with qw[Pcore::Core::CLI::Cmd];

sub cli_abstract ($self) {
    return 'setup pcore.ini';
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run;

    return;
}

sub run ($self) {
    state $init = !!require Pcore::Dist::Build;

    Pcore::Dist::Build->new->setup;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Setup - setup pcore.ini

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
