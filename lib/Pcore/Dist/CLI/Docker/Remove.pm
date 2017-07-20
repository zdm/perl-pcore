package Pcore::Dist::CLI::Docker::Remove;

use Pcore -class;

with qw[Pcore::Dist::CLI1];

sub CLI ($self) {
    return {
        abstract => 'remove tag',
        arg      => [
            tag => {
                desc => 'tag',
                isa  => 'Str',
            },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dist = $self->get_dist;

    $dist->build->docker->remove_tag( $arg->{tag} );

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
