package Pcore::API::SCM::Upstream;

use Pcore -class;
use Pcore::API::SCM::Const qw[:ALL];

has local_scm_type => ();                   # Enum [ $SCM_TYPE_HG, $SCM_TYPE_GIT ]
has scm_type       => ( required => 1 );    # Enum [ $SCM_TYPE_HG, $SCM_TYPE_GIT ]
has hosting        => ( required => 1 );    # Enum [ $SCM_HOSTING_BITBUCKET, $SCM_HOSTING_GITHUB ]

has repo_namespace => ( required => 1 );    # Str
has repo_name      => ( required => 1 );    # Str
has repo_id        => ( required => 1 );    # Str

sub BUILDARGS ( $self, $args ) {
    if ( $args->{uri} ) {
        my $uri = P->uri( $args->{uri} );

        if ( $uri->{scheme} ) {
            if ( $args->{uri} =~ m[(bitbucket[.]org|github[.]com)[/:]([[:alnum:]-]+)/([[:alnum:]_-]+)([.]git)?]sm ) {
                my $has_git_suffix = $4;

                $args->{repo_namespace} = $2;
                $args->{repo_name}      = $3;
                $args->{repo_id}        = "$2/$3";

                if ( $1 eq 'github.com' ) {
                    $args->{hosting}  = $SCM_HOSTING_GITHUB;
                    $args->{scm_type} = $SCM_TYPE_GIT;
                }
                else {
                    $args->{hosting} = $SCM_HOSTING_BITBUCKET;

                    if ( !$args->{scm_type} ) {
                        if ($has_git_suffix) {
                            $args->{scm_type} = $SCM_TYPE_GIT;
                        }

                        # git_ssh://, git://, git@
                        elsif ( substr( $args->{uri}, 0, 3 ) eq 'git' ) {
                            $args->{scm_type} = $SCM_TYPE_GIT;
                        }

                        # ssh://
                        elsif ( substr( $args->{uri}, 0, 6 ) eq 'ssh://' ) {
                            $args->{scm_type} = $SCM_TYPE_HG;
                        }
                        else {
                            if ( $args->{local_scm_type} && $args->{local_scm_type} eq $SCM_TYPE_GIT ) {
                                $args->{scm_type} = $SCM_TYPE_GIT;
                            }
                            else {

                                # NOTE uri is ambiguous, better is to use .git suffix for git repositories
                                $args->{scm_type} = $SCM_TYPE_HG;
                            }
                        }
                    }
                }
            }
            else {
                die 'SCM upstream URL is invalid or is not supported';
            }
        }
        else {

            # uri is file://
            $args->{hosting}  //= undef;
            $args->{scm_type} //= $args->{local_scm_type};
            $args->{repo_namespace} = undef;
            $args->{repo_name}      = undef;
            $args->{repo_id}        = undef;
        }
    }
    else {
        $args->{scm_type} = $SCM_TYPE_GIT if $args->{hosting} eq $SCM_HOSTING_GITHUB;

        if ( $args->{repo_id} ) {
            ( $args->{repo_namespace}, $args->{repo_name} ) = split m[/]sm, $args->{repo_id};
        }
        else {
            $args->{repo_id} = "$args->{repo_namespace}/$args->{repo_name}";
        }
    }

    return $args;
}

sub get_clone_url ( $self, $scm_url_type = $SCM_URL_TYPE_SSH, $local_scm_type = $SCM_TYPE_HG ) {
    die q[SCM URL type is invalid] if $scm_url_type ne $SCM_URL_TYPE_SSH && $scm_url_type ne $SCM_URL_TYPE_HTTPS;

    if ( $local_scm_type eq $SCM_TYPE_HG ) {
        if ( $self->{scm_type} eq $SCM_TYPE_GIT ) {

            # ssh hggit
            if ( $scm_url_type eq $SCM_URL_TYPE_SSH ) {
                return "git+ssh://git\@$SCM_HOSTING_HOST->{$self->{hosting}}:$self->{repo_id}.git";
            }

            # https hggit
            else {
                return "git://$SCM_HOSTING_HOST->{$self->{hosting}}/$self->{repo_id}.git";
            }
        }
        else {

            # ssh hg
            if ( $scm_url_type eq $SCM_URL_TYPE_SSH ) {
                return "ssh://hg\@$SCM_HOSTING_HOST->{$self->{hosting}}/$self->{repo_id}";
            }

            # https hg
            else {
                return "https://$SCM_HOSTING_HOST->{$self->{hosting}}/$self->{repo_id}";
            }
        }
    }
    elsif ( $local_scm_type eq $SCM_TYPE_GIT ) {
        if ( $self->{scm_type} eq $SCM_TYPE_GIT ) {

            # ssh git
            if ( $scm_url_type eq $SCM_URL_TYPE_SSH ) {
                return "git\@$SCM_HOSTING_HOST->{$self->{hosting}}:$self->{repo_id}.git";
            }

            # https git
            else {
                return "https://$SCM_HOSTING_HOST->{$self->{hosting}}/$self->{repo_id}.git";
            }
        }
        else {
            die q[can't generate upstream hg url for local git];
        }
    }
    else {
        die 'local SCM type is invalid';
    }

    return;
}

sub get_wiki_clone_url ( $self, $scm_url_type = $SCM_URL_TYPE_SSH, $local_scm_type = $SCM_TYPE_HG ) {
    die q[SCM URL type is invalid] if $scm_url_type ne $SCM_URL_TYPE_SSH && $scm_url_type ne $SCM_URL_TYPE_HTTPS;

    my $repo_id = $self->{hosting} eq $SCM_HOSTING_BITBUCKET ? "$self->{repo_id}/wiki" : "$self->{repo_id}.wiki";

    if ( $local_scm_type eq $SCM_TYPE_HG ) {
        if ( $self->{scm_type} eq $SCM_TYPE_GIT ) {

            # ssh hggit
            if ( $scm_url_type eq $SCM_URL_TYPE_SSH ) {
                return "git+ssh://git\@$SCM_HOSTING_HOST->{$self->{hosting}}:$repo_id.git";
            }

            # https hggit
            else {
                return "git://$SCM_HOSTING_HOST->{$self->{hosting}}/$repo_id.git";
            }
        }
        else {

            # ssh hg
            if ( $scm_url_type eq $SCM_URL_TYPE_SSH ) {
                return "ssh://hg\@$SCM_HOSTING_HOST->{$self->{hosting}}/$repo_id";
            }

            # https hg
            else {
                return "https://$SCM_HOSTING_HOST->{$self->{hosting}}/$repo_id";
            }
        }
    }
    elsif ( $local_scm_type eq $SCM_TYPE_GIT ) {
        if ( $self->{scm_type} eq $SCM_TYPE_GIT ) {

            # ssh git
            if ( $scm_url_type eq $SCM_URL_TYPE_SSH ) {
                return "git\@$SCM_HOSTING_HOST->{$self->{hosting}}:$repo_id.git";
            }

            # https git
            else {
                return "https://$SCM_HOSTING_HOST->{$self->{hosting}}/$repo_id.git";
            }
        }
        else {
            die q[can't generate upstream hg url for local git];
        }
    }
    else {
        die 'local SCM type is invalid';
    }

    return;
}

sub get_cpan_meta ( $self) {
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

sub get_hosting_api ( $self, $args = undef ) {
    if ( $self->{hosting} eq $SCM_HOSTING_BITBUCKET ) {
        require Pcore::API::Bitbucket;

        return Pcore::API::Bitbucket->new( $args // () );
    }
    elsif ( $self->{hosting} eq $SCM_HOSTING_GITHUB ) {
        require Pcore::API::GitHub;

        return Pcore::API::GitHub->new( $args // () );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 19                   | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 34, 48               | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 88, 141              | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
