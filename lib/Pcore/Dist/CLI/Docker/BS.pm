package Pcore::Dist::CLI::Docker::BS;

use Pcore -class;

with qw[Pcore::Dist::CLI1];

sub CLI ($self) {
    return { abstract => 'get DockerHub build status', };
}

sub CLI_RUN ( $self, $opt, $arg, $rest ) {
    my $dist = $self->get_dist;

    $dist->build->docker->build_status;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::CLI::Docker::BS - get DockerHub build status

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
