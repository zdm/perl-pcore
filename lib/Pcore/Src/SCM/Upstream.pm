package Pcore::Src::SCM::Upstream;

use Pcore -class;

has uri => ( is => 'ro', isa => InstanceOf ['Pcore::Util::URI'], required => 1 );
has clone_is_git => ( is => 'ro', isa => Bool, default => 0 );
has clone_is_hg  => ( is => 'ro', isa => Bool, default => 0 );

has is_bitbucket => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_github    => ( is => 'lazy', isa => Bool, init_arg => undef );
has username     => ( is => 'lazy', isa => Str,  init_arg => undef );
has _reponame    => ( is => 'lazy', isa => Str,  init_arg => undef );    # reponame with possible .git suffix
has reponame     => ( is => 'lazy', isa => Str,  init_arg => undef );
has is_git       => ( is => 'lazy', isa => Bool, init_arg => undef );
has is_hg        => ( is => 'lazy', isa => Bool, init_arg => undef );
has host         => ( is => 'lazy', isa => Str,  init_arg => undef );

has clone_uri_https       => ( is => 'lazy', isa => Str, init_arg => undef );
has clone_uri_ssh         => ( is => 'lazy', isa => Str, init_arg => undef );
has clone_uri_https_hggit => ( is => 'lazy', isa => Str, init_arg => undef );
has clone_uri_ssh_hggit   => ( is => 'lazy', isa => Str, init_arg => undef );

has meta_resources => ( is => 'lazy', isa => HashRef, init_arg => undef );

# NOTE https://bitbucket.org/username/reponame - upstream SCM type can't be recognized correctly, use ".git" suffix fot git repositories

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

sub _build_username ($self) {
    my $username;

    if ( $self->uri->port ) {
        $username = $self->uri->port;
    }
    else {
        $username = ( split m[/]sm, $self->uri->path )[1];
    }

    return $username;
}

sub _build__reponame ($self) {
    my $reponame;

    my @path = split m[/]sm, $self->uri->path;

    if ( $self->uri->port ) {
        $reponame = $path[1];
    }
    else {
        $reponame = $path[2];
    }

    return $reponame;
}

sub _build_reponame ($self) {
    return $self->_reponame =~ s/[.]git\z//smir;
}

sub _build_is_git ($self) {
    return 1 if $self->clone_is_git;

    return 1 if $self->is_github;

    return 1 if $self->uri->scheme =~ /git/sm;

    return 1 if $self->_reponame =~ /[.]git\z/smi;

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
    return 'https://' . $self->host . q[/] . $self->username . q[/] . $self->reponame . ( $self->is_git ? '.git' : q[] );
}

sub _build_clone_uri_ssh ($self) {
    if ( $self->is_hg ) {    # hg@bitbucket
        return 'ssh://hg@bitbucket.org/' . $self->username . q[/] . $self->reponame;
    }
    else {
        return 'git@' . $self->host . q[:] . $self->username . q[/] . $self->reponame . '.git';
    }
}

sub _build_clone_uri_https_hggit ($self) {
    return ( $self->is_git ? 'git+' : q[] ) . $self->clone_uri_https;
}

sub _build_clone_uri_ssh_hggit ($self) {
    return ( $self->is_git ? 'git+ssh://' : q[] ) . $self->clone_uri_ssh;
}

sub _build_meta_resources ($self) {
    return {
        homepage => 'https://' . $self->host . q[/] . $self->username . q[/] . $self->reponame . ( $self->is_bitbucket ? '/overview' : q[] ),
        bugtracker => {    #
            web => 'https://' . $self->host . q[/] . $self->username . q[/] . $self->reponame . '/issues' . ( $self->is_bitbucket ? '?status=new&status=open' : '?q=is%3Aopen+is%3Aissue' ),
        },
        repository => {
            type => $self->is_git ? 'git' : 'hg',
            url => $self->clone_uri_https,
            web => 'https://' . $self->host . q[/] . $self->username . q[/] . $self->reponame . ( $self->is_bitbucket ? '/overview' : q[] ),
        },
    };
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::SCM::Upstream

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
