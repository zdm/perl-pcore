package Pcore::Dist::CLI::Docker::Init;

use Pcore -class;

with qw[Pcore::Dist::CLI1];

sub CLI ($self) {
    return {
        abstract => 'create and link to the DockerHub repository',
        opt      => {
            owner => {
                desc => 'repository owner',
                type => 'STR',
                isa  => 'Str',
            },
            slug => {
                desc => 'repository slug',
                type => 'STR',
                isa  => 'Str',
            },
        },
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dist = $self->get_dist;

    $dist->build->docker->init($opt);

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Docker::Init - init docker repository

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
