package Pcore::API::Git::Upstream;

use Pcore -class;
use Pcore::API::Git qw[:ALL];

has repo_namespace => ( required => 1 );    # Str
has repo_name      => ( required => 1 );    # Str
has repo_id        => ( required => 1 );    # Str

# TODO
sub git_wiki_clone_url ( $self, $url_type = $GIT_UPSTREAM_URL_SSH ) {
    my $repo_id;

    # my $repo_id = $self->{hosting} eq $SCM_HOSTING_BITBUCKET ? "$self->{repo_id}/wiki" : "$self->{repo_id}.wiki";

    # ssh
    if ( $url_type == $GIT_UPSTREAM_URL_SSH ) {
        return "git\@$GIT_UPSTREAM_HOST->{$self->{upstream}}:$repo_id.git";
    }

    # https
    else {
        return "https://$GIT_UPSTREAM_HOST->{$self->{upstream}}/$repo_id.git";
    }
}

sub git_cpan_meta ($self) {
    my $cpan_meta;

    if ( $self->{hosting} eq $SCM_HOSTING_BITBUCKET ) {
        $cpan_meta = {
            homepage   => "https://bitbucket.org/$self->{repo_id}/overview",
            bugtracker => {                                                    #
                web => "https://bitbucket.org/$self->{repo_id}/issues?status=new&status=open",
            },
            repository => {
                type => $self->{scm_type},
                url  => $self->get_clone_url( $SCM_URL_TYPE_HTTPS, $self->{scm_type} ),
                web  => "https://bitbucket.org/$self->{repo_id}/overview",
            },
        };
    }
    elsif ( $self->{hosting} eq $SCM_HOSTING_GITHUB ) {
        $cpan_meta = {
            homepage   => "https://github.com/$self->{repo_id}",
            bugtracker => {                                        #
                web => "https://github.com/$self->{repo_id}/issues?q=is%3Aopen+is%3Aissue",
            },
            repository => {
                type => 'git',
                url  => $self->get_clone_url( $SCM_URL_TYPE_HTTPS, $SCM_TYPE_GIT ),
                web  => "https://github.com/$self->{repo_id}",
            },
        };
    }

    return $cpan_meta;
}

# TODO
sub git_clone_url ( $self, $url_type = $GIT_UPSTREAM_URL_SSH ) {

    # ssh
    if ( $url_type == $GIT_UPSTREAM_URL_SSH ) {
        return "git\@$GIT_UPSTREAM_HOST->{$self->{upstream}}:$self->{repo_id}.git";
    }

    # https
    else {
        return "https://$GIT_UPSTREAM_HOST->{$self->{upstream}}/$self->{repo_id}.git";
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 11, 61               | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Git::Upstream

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
