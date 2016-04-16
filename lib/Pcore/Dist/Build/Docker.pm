package Pcore::Dist::Build::Docker;

use Pcore -class;
use Pcore::API::DockerHub;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

around new => sub ( $orig, $self, $args ) {
    return if !$args->{dist}->docker_cfg;

    return $self->$orig($args);
};

sub run ( $self, $args ) {
    my $dockerhub_api = Pcore::API::DockerHub->new( { namespace => $self->dist->docker_cfg->{namespace} } );

    my $dockerhub_repo = $dockerhub_api->get_repo( lc $self->dist->name );

    my $tags = $dockerhub_repo->tags;

    for my $tag ( values $tags->{result}->%* ) {
        say qq[$tag->{name} - $tag->{full_size} - $tag->{last_updated}];
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 21                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Docker

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
