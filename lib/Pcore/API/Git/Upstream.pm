package Pcore::API::Git::Upstream;

use Pcore -class;
use Pcore::API::Git qw[:ALL];

has repo_namespace => ( required => 1 );    # Str
has repo_name      => ( required => 1 );    # Str
has repo_id        => ( required => 1 );    # Str
has hosting        => ( required => 1 );    # Enum [ $GIT_UPSTREAM_BITBUCKET, $GIT_UPSTREAM_GITHUB, $GIT_UPSTREAM_GITLAB ]

# https://github.com/softvisio/phonegap.git
# git://github.com/softvisio/phonegap.git
# ssh://git@github.com/softvisio/phonegap.git
# git@github.com:softvisio/phonegap.git

# https://git-scm.com/docs/git-clone#_git_urls_a_id_urls_a
sub BUILDARGS ( $self, $args ) {
    if ( my $url = delete $args->{url} ) {
        if ( $url =~ m[\Agit@([[:alnum:].-]+?):([[:alnum:]]+?)/([[:alnum:]]+)]sm ) {
            $args->{hosting}        = $1;
            $args->{repo_namespace} = $2;
            $args->{repo_name}      = $3;
        }
        else {
            $url = P->uri($url);

            ...;
        }

        $args->{repo_id} = "$args->{repo_namespace}/$args->{repo_name}";
    }
    else {
        if ( $args->{repo_id} ) {
            ( $args->{repo_namespace}, $args->{repo_name} ) = split m[/]sm, $args->{repo_id};
        }
        else {
            $args->{repo_id} = "$args->{repo_namespace}/$args->{repo_name}";
        }
    }

    return $args;
}

sub get_hosting_api ( $self, $args = undef ) {
    if ( $self->{hosting} eq $GIT_UPSTREAM_BITBUCKET ) {
        require Pcore::API::Bitbucket;

        return Pcore::API::Bitbucket->new( $args // () );
    }
    elsif ( $self->{hosting} eq $GIT_UPSTREAM_GITHUB ) {
        require Pcore::API::GitHub;

        return Pcore::API::GitHub->new( $args // () );
    }
    elsif ( $self->{hosting} eq $GIT_UPSTREAM_GITLAB ) {
        require Pcore::API::GitLab;

        return Pcore::API::GitLab->new( $args // () );
    }

    return;
}

sub get_clone_url ( $self, $url_type = $GIT_UPSTREAM_URL_SSH ) {
    my $url = $url_type == $GIT_UPSTREAM_URL_HTTPS ? 'https://' : 'ssh://git@';

    $url .= "$GIT_UPSTREAM_HOST->{$self->{hosting}}/$self->{repo_id}";

    return $url;
}

=pod

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

=cut

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 27                   | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 64                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 72                   | Documentation::RequirePodAtEnd - POD before __END__                                                            |
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
