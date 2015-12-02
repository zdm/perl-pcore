package Pcore::Dist::CLI::Release;

use Pcore qw[-class];

with qw[Pcore::Dist::CLI];

no Pcore;

sub cli_arg ($self) {
    return [    #
        {   name => 'release_type',
            isa  => [qw[major minor bugfix]],
        },
    ];
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run( $arg->{release_type} );

    return;
}

sub run ( $self, $release_type ) {
    $self->dist->build->release($release_type);

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Release - release distribution

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
