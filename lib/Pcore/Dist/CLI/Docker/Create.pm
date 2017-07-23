package Pcore::Dist::CLI::Docker::Create;

use Pcore -class;

with qw[Pcore::Dist::CLI1];

sub CLI ($self) {
    return {
        abstract => 'create autobuild tag',
        opt      => {
            type => {
                desc    => q[scm tag type, allowed values: 'tag', 'branch'],
                type    => 'STR',
                isa     => [ 'tag', 'branch' ],
                default => 'tag',
            },
            name => {
                desc => q[scm source tag name],
                type => 'STR',
                isa  => 'Str',
            },
            dockerfile_location => {
                desc    => q[Dockerfile location],
                type    => 'STR',
                isa     => 'Str',
                default => '/',
            },
        },
        arg => [
            tag => {
                desc => 'tag',
                isa  => 'Str',
            },
        ],
    };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dist = $self->get_dist;

    $dist->build->docker->create_tag( $arg->{tag}, $opt->{name} // $opt->{type}, $opt->{type}, $opt->{dockerfile_location} );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Docker::Create - create autobuild tag

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
