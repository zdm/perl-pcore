package Pcore::API::SCM::Upstream;

use Pcore -const, -class;
use Pcore::API::SCM qw[:CONST];

has uri => ( is => 'ro', isa => InstanceOf ['Pcore::Util::URI'], required => 1 );
has local_scm_type => ( is => 'lazy', isa => Enum [ $SCM_TYPE_HG, $SCM_TYPE_GIT ] );

has is_bitbucket => ( is => 'lazy', isa => Bool, init_arg => undef );    # upstream is hosted on bitbucket
has is_github    => ( is => 'lazy', isa => Bool, init_arg => undef );    # upstream is hosted on github

has remote_scm_type => ( is => 'lazy', isa => Enum [ $SCM_TYPE_HG, $SCM_TYPE_GIT ], init_arg => undef );

has repo_owner => ( is => 'lazy', isa => Str,  init_arg => undef );      # TODO namespace
has _repo_name => ( is => 'lazy', isa => Str,  init_arg => undef );      # repo_name with possible .git suffix
has repo_name  => ( is => 'lazy', isa => Str,  init_arg => undef );
has is_git     => ( is => 'lazy', isa => Bool, init_arg => undef );      # upstream scm is git
has is_hg      => ( is => 'lazy', isa => Bool, init_arg => undef );      # upstream scm is mercurial
has host       => ( is => 'lazy', isa => Str,  init_arg => undef );      # upstream host name, bitbucket.org, github.com, etc...

has clone_uri_https       => ( is => 'lazy', isa => Str, init_arg => undef );
has clone_uri_ssh         => ( is => 'lazy', isa => Str, init_arg => undef );
has clone_uri_https_hggit => ( is => 'lazy', isa => Str, init_arg => undef );
has clone_uri_ssh_hggit   => ( is => 'lazy', isa => Str, init_arg => undef );

# NOTE https://bitbucket.org/repo_owner/repo_name - upstream SCM type can't be recognized correctly, use ".git" suffix fot git repositories

const our $SCM_HOSTING_BITBUCKET => 1;
const our $SCM_HOSTING_GITHUB    => 2;

const our $SCM_HOSTING_CLASS => {
    $SCM_HOSTING_BITBUCKET => 'Pcore::API::Bitbucket',
    $SCM_HOSTING_GITHUB    => 'Pcore::API::GitHub',
};

# git@bitbucket.org:softvisio/test-git.git/wiki
# https://softvisio@bitbucket.org/softvisio/test-git.git/wiki
# ssh://hg@bitbucket.org/softvisio/test-hg
# ssh://softvisio@bitbucket.org/softvisio/test-hg/wiki
# git@github.com:zdm/test-github.wiki.git
# https://github.com/zdm/test-github.wiki.git

sub BUILDARGS ( $self, $args ) {
    $args->{uri} = P->uri( $args->{uri}, authority => 1 ) if !ref $args->{uri};

    return $args;
}

sub _build_is_bitbucket ($self) {
    return $self->uri->host =~ /bitbucket/sm ? 1 : 0;
}

sub _build_is_github ($self) {
    return $self->uri->host =~ /github/sm ? 1 : 0;
}

sub _build_repo_owner ($self) {
    my $repo_owner;

    if ( $self->uri->port ) {
        $repo_owner = $self->uri->port;
    }
    else {
        $repo_owner = ( split m[/]sm, $self->uri->path )[1];
    }

    return $repo_owner;
}

sub _build__repo_name ($self) {
    my $repo_name;

    my @path = split m[/]sm, $self->uri->path;

    if ( $self->uri->port ) {
        $repo_name = $path[1];
    }
    else {
        $repo_name = $path[2];
    }

    return $repo_name;
}

sub _build_repo_name ($self) {
    return $self->_repo_name =~ s/[.]git\z//smir;
}

sub _build_is_git ($self) {
    return 1 if $self->local_scm_type == $SCM_TYPE_GIT;

    return 1 if $self->is_github;

    return 1 if $self->uri->scheme =~ /git/sm;

    return 1 if $self->_repo_name =~ /[.]git\z/smi;

    return 1 if $self->uri->username eq 'git';

    return 0;
}

sub _build_is_hg ($self) {
    return $self->is_git ? 0 : 1;
}

sub _build_host ($self) {
    return $self->is_bitbucket ? 'bitbucket.org' : 'github.com';
}

sub _build_clone_uri_https ($self) {
    return 'https://' . $self->host . q[/] . $self->repo_owner . q[/] . $self->repo_name . ( $self->is_git ? '.git' : q[] );
}

sub _build_clone_uri_ssh ($self) {
    if ( $self->is_hg ) {    # hg@bitbucket
        return 'ssh://hg@bitbucket.org/' . $self->repo_owner . q[/] . $self->repo_name;
    }
    else {
        return 'git@' . $self->host . q[:] . $self->repo_owner . q[/] . $self->repo_name . '.git';
    }
}

sub _build_clone_uri_https_hggit ($self) {
    return ( $self->is_git ? 'git+' : q[] ) . $self->clone_uri_https;
}

sub _build_clone_uri_ssh_hggit ($self) {
    return ( $self->is_git ? 'git+ssh://' : q[] ) . $self->clone_uri_ssh;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::SCM::Upstream

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
