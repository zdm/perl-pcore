package Pcore::Dist::CLI::Docker::Remove;

use Pcore -class1;

extends qw[Pcore::Dist::CLI];

sub CLI ($self) {
    return {
        abstract => 'remove tags',
        name     => 'rm',

        opt => {
            keep => {
                desc    => 'Number of builds to keep',
                isa     => 'PositiveInt',
                default => 2,
            },
        },

        arg => [
            tag => {
                desc => 'tag',
                isa  => 'Str',
                min  => 0,
                max  => 0,
            },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dist = $self->get_dist;

    $dist->build->docker->remove_tag( $opt->{keep}, $arg->{tag} );

    $dist->build->docker->status;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Docker::Remove - remove tag

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
