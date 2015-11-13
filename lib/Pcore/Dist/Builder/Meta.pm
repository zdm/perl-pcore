package Dist::Zilla::Plugin::Pcore::Meta;

use Moose;
use Pcore;
use Pcore::Devel::VCSInfo;

with qw[Dist::Zilla::Role::MetaProvider];

has vcs => ( is => 'ro', isa => 'Object', lazy => 1, builder => '_build_vcs', init_arg => undef );

no Pcore;
no Moose;

sub _build_vcs ($self) {
    return Pcore::Devel::VCSInfo->new( { root => q[.] } );
}

sub metadata ($self) {
    my $cfg = P->cfg->load('./share/dist.perl');

    $cfg = exists $cfg->{dist}->{meta} ? $cfg->{dist}->{meta} : {};

    my $meta = {};

    $meta->{resources}->{homepage}           = $cfg->{homepage}           || $self->vcs->homepage       if $cfg->{homepage}           || $self->vcs->homepage;
    $meta->{resources}->{repository}->{web}  = $cfg->{repository}->{web}  || $self->vcs->repo_web       if $cfg->{repository}->{web}  || $self->vcs->repo_web;
    $meta->{resources}->{repository}->{url}  = $cfg->{repository}->{url}  || $self->vcs->repo_url       if $cfg->{repository}->{url}  || $self->vcs->repo_url;
    $meta->{resources}->{repository}->{type} = $cfg->{repository}->{type} || $self->vcs->repo_type      if $cfg->{repository}->{type} || $self->vcs->repo_type;
    $meta->{resources}->{bugtracker}->{web}  = $cfg->{bugtracker}->{web}  || $self->vcs->bugtracker_web if $cfg->{bugtracker}->{web}  || $self->vcs->bugtracker_web;

    return $meta;
}

__PACKAGE__->meta->make_immutable;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::Plugin::Pcore::Meta

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
