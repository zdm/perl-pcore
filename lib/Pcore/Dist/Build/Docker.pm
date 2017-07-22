package Pcore::Dist::Build::Docker;

use Pcore -class, -ansi;
use Pcore::API::DockerHub qw[:CONST];

has dist          => ( is => 'ro',   isa => InstanceOf ['Pcore::Dist'],           required => 1 );
has dockerhub_api => ( is => 'lazy', isa => InstanceOf ['Pcore::API::DockerHub'], init_arg => undef );

sub _build_dockerhub_api($self) {
    return Pcore::API::DockerHub->new;
}

sub init ( $self, $args ) {
    if ( $self->{dist}->docker ) {
        say qq[Dist is already linked to "$self->{dist}->{docker}->{repo_id}"];

        exit 3;
    }

    my $repo_namespace = $args->{namespace} || $ENV->user_cfg->{DOCKERHUB}->{default_namespace} || $ENV->user_cfg->{DOCKERHUB}->{username};

    if ( !$repo_namespace ) {
        say 'DockerHub repo namespace is not defined';

        exit 3;
    }

    my $repo_name = $args->{name} || lc $self->dist->name;

    my $repo_id = "$repo_namespace/$repo_name";

    my $confirm = P->term->prompt( qq[Create DockerHub repository "$repo_id"?], [qw[yes no]], enter => 1 );

    if ( $confirm eq 'no' ) {
        exit 3;
    }

    my $api = $self->dockerhub_api;

    my $upstream = $self->dist->scm->upstream;

    print q[Creating DockerHub repository ... ];

    my $res = $api->create_autobuild(    #
        $repo_id,                        #
        $upstream->hosting == $Pcore::API::SCM::Upstream::SCM_HOSTING_BITBUCKET ? $DOCKERHUB_PROVIDER_BITBUCKET : $DOCKERHUB_PROVIDER_GITHUB,
        "@{[$upstream->namespace]}/@{[$upstream->repo_name]}",
        $self->dist->module->abstract || $self->dist->name,
        private => 0,
        active  => 1
    );

    say $res->reason;

    if ( !$res->is_success ) {
        exit 3;
    }
    else {
        require Pcore::Util::File::Tree;

        # copy files
        my $files = Pcore::Util::File::Tree->new;

        $files->add_dir( $ENV->share->get_storage( 'pcore', 'Pcore' ) . '/docker/' );

        $files->render_tmpl(
            {   author                        => $self->dist->cfg->{author},
                dist_path                     => lc $self->dist->name,
                dockerhub_dist_repo_namespace => $repo_namespace,
                dockerhub_dist_repo_name      => $repo_name,
                dockerhub_pcore_repo_id       => $ENV->pcore->docker->{repo_id},
            }
        );

        $files->write_to( $self->dist->root );
    }

    return;
}

sub set_from_tag ( $self, $tag ) {
    my $dockerfile = P->file->read_bin( $self->dist->root . 'Dockerfile' );

    if ( $dockerfile->$* =~ s/^FROM\s+([^:]+)(.*?)$/FROM $1:$tag/sm ) {
        if ( "$1$2" eq "$1:$tag" ) {
            say qq[Docker base image wasn't changed];
        }
        else {
            P->file->write_bin( $self->dist->root . 'Dockerfile', $dockerfile );

            {
                # cd to repo root
                my $chdir_guard = P->file->chdir( $self->dist->root );

                my $res = $self->dist->scm->scm_commit( qq[Docker base image changed from "$1$2" to "$1:$tag"], 'Dockerfile' );

                die "$res" if !$res;
            }

            $self->dist->clear_docker;

            say qq[Docker base image changed from "$1$2" to "$1:$tag"];
        }
    }
    else {
        say q[Error updating docker base image];
    }

    return;
}

sub status ( $self ) {
    my $cv = AE::cv;

    my ( $tags, $build_history, $build_settings );

    $cv->begin;
    $self->dockerhub_repo->tags(
        cb => sub ($res) {
            $tags = $res;

            $cv->end;

            return;
        }
    );

    $cv->begin;
    $self->dockerhub_repo->build_history(
        cb => sub ($res) {
            $build_history = $res;

            $cv->end;

            return;
        }
    );

    $cv->begin;
    $self->dockerhub_repo->build_settings(
        cb => sub ($res) {
            $build_settings = $res;

            $cv->end;

            return;
        }
    );

    $cv->recv;

    my $tbl = P->text->table(
        cols => [
            tag => {
                title => 'TAG NAME',
                width => 15,
            },
            is_build_tag => {
                title  => "BUILD\nTAG",
                width  => 7,
                align  => 1,
                format => sub ( $val, $id, $row ) {
                    if ( !$val ) {
                        return $BOLD . $WHITE . $ON_RED . ' no ' . $RESET;
                    }
                    else {
                        return $BLACK . $ON_GREEN . q[ yes ] . $RESET;
                    }
                }
            },
            size => {
                title  => 'IMAGE SIZE',
                width  => 15,
                align  => 1,
                format => sub ( $val, $id, $row ) {
                    return $val ? P->text->add_num_sep($val) : q[-];
                }
            },
            last_updated => {
                title  => 'IMAGE LAST UPDATED',
                width  => 35,
                align  => 1,
                format => sub ( $val, $id, $row ) {
                    return $val ? P->date->from_string($val)->to_http_date : q[-];
                }
            },
            build_status => {
                title  => 'LATEST BUILD STATUS',
                width  => 15,
                format => sub ( $val, $id, $row ) {
                    return $val || q[-];
                }
            },
            build_status_updated => {
                title  => 'BUILD STATUS UPDATED',
                width  => 35,
                align  => 1,
                format => sub ( $val, $id, $row ) {
                    return q[-] if !$val;

                    my $now = P->date->now_utc;

                    my $date = P->date->from_string($val);

                    my $delta_minutes = $date->delta_minutes($now);

                    my $minutes = $delta_minutes % 60;

                    my $delta_hours = int( $delta_minutes / 60 );

                    my $hours = $delta_hours % 24;

                    my $days = int( $delta_hours / 24 );

                    my $res = q[];

                    $res .= "$days days " if $days;

                    $res .= "$hours hours " if $hours;

                    return "${res}$minutes minutes ago";
                }
            },
        ],
    );

    my $report;

    # index tags
    for my $tag ( values $tags->{data}->%* ) {
        $report->{ $tag->name } = {
            size         => $tag->full_size,
            last_updated => $tag->last_updated,
        };
    }

    # index build tags
    for my $build_tag ( values $build_settings->{data}->{build_tags}->%* ) {
        $report->{ $build_tag->name }->{is_build_tag} = 1 if $build_tag->name ne '{sourceref}';
    }

    # index builds
    for my $build ( $build_history->{data}->@* ) {
        if ( !exists $report->{ $build->dockertag_name }->{build_status} ) {
            if ( $build->build_status_name eq 'Error' ) {
                $report->{ $build->dockertag_name }->{build_status} = $BOLD . $WHITE . $ON_RED;
            }
            elsif ( $build->build_status_name eq 'Success' ) {
                $report->{ $build->dockertag_name }->{build_status} = $BLACK . $ON_GREEN;
            }
            else {
                $report->{ $build->dockertag_name }->{build_status} = $BLACK . $ON_WHITE;
            }

            $report->{ $build->dockertag_name }->{build_status} .= q[ ] . $build->build_status_name . q[ ] . $RESET;

            $report->{ $build->dockertag_name }->{build_status_updated} = $build->last_updated;
        }
    }

    if ( keys $report->%* ) {
        my $version_tags = [];

        my $named_tags = [];

        for ( keys $report->%* ) {
            $report->{$_}->{tag} = $_;

            if    (/\Av\d+[.]\d+[.]\d+\z/sm) { push $version_tags->@*, $_ }
            elsif ( $_ ne 'latest' )         { push $named_tags->@*,   $_ }
        }

        print $tbl->render_all( [ map { $report->{$_} } ( sort $version_tags->@* ), $report->{latest} ? 'latest' : (), ( sort $named_tags->@* ) ] );

        say 'NOTE: if build tag is not set - repository will not be builded automatically, when build link will be updated';
    }
    else {
        say q[No docker tags were found.];
    }

    return;
}

sub create_tag ( $self, $tag ) {
    print qq[Creating build tag "$tag" ... ];

    my $build_settings = $self->dockerhub_repo->build_settings;

    if ( !$build_settings ) {
        say $build_settings->reason;
    }
    else {
        for ( values $build_settings->{data}->{build_tags}->%* ) {
            if ( $_->name eq $tag || $_->source_name eq $tag ) {
                say q[tag already exists];

                $self->status;

                return 1;
            }
        }
    }

    my $res = $self->dockerhub_repo->create_build_tag( name => $tag, source_name => $tag );

    if ( $res->status ) {
        say 'OK';

        $self->status;

        return 1;
    }
    else {
        say $res->reason;

        return 0;
    }
}

sub remove_tag ( $self, $tag ) {
    print qq[Removing tag "$tag" ... ];

    my $tags = $self->dockerhub_repo->tags;

    if ( !$tags->{data}->{$tag} ) {
        say 'Tag does not exists';
    }
    else {
        my $res = $tags->{data}->{$tag}->remove;

        say $res->status ? 'OK' : $res->reason;
    }

    # remove build tag
    print qq[Removing build tag "$tag" ... ];

    my $build_settings = $self->dockerhub_repo->build_settings;

    if ( !$build_settings ) {
        say $build_settings->reason;
    }
    else {
        my $build_tag;

        for ( values $build_settings->{data}->{build_tags}->%* ) {
            if ( $_->name eq $tag ) {
                $build_tag = $_;

                last;
            }
        }

        if ( !$build_tag ) {
            say 'Tag does not exists';
        }
        else {
            my $res1 = $build_tag->remove;

            say $res1->status ? 'OK' : $res1->reason;
        }
    }

    $self->status;

    return;
}

sub trigger_build ( $self, $tag ) {
    print qq[Triggering build for tag "$tag" ... ];

    my $res = $self->dockerhub_api->trigger_autobuild( $self->dist->docker->{repo_id}, $tag );

    if ( $res->is_success ) {
        say 'OK';

        $self->status;

        return 1;
    }
    else {
        say $res->reason;

        return 0;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 86                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 112                  | Subroutines::ProhibitExcessComplexity - Subroutine "status" with high complexity score (23)                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
