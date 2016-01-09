package Pcore::Dist::CLI::Issues;

use Pcore -class;

with qw[Pcore::Dist::CLI];

sub cli_abstract ($self) {
    return 'view project issues';
}

sub cli_opt ($self) {
    return {    #
        pcore => { desc => 'show info about currently used Pcore distribution', },
    };
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run( $opt->{pcore} );

    return;
}

sub run ( $self, $pcore = 0 ) {
    state $init = !!require Pcore::API::Bitbucket;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Issues

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
