package Pcore::Dist::Build::Docker;

use Pcore -class, -ansi;
use Pcore::API::DockerHub;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

around new => sub ( $orig, $self, $args ) {
    return if !$args->{dist}->docker_cfg;

    return $self->$orig($args);
};

sub run ( $self, $args ) {
    if ( $args->{from} ) {
        my $dockerfile = P->file->read_bin( $self->dist->root . 'Dockerfile' );

        if ( $dockerfile->$* =~ s/^FROM\s+([^:]+)(.*?)$/FROM $1:$args->{from}/sm ) {
            if ( "$1$2" eq "$1:$args->{from}" ) {
                say qq[Docker base image wasn't changed];
            }
            else {
                P->file->write_bin( $self->dist->root . 'Dockerfile', $dockerfile );

                $self->dist->scm->scm_commit( qq[Docker base image changed from "$1$2" to "$1:$args->{from}"], 'Dockerfile' ) or die;

                say qq[Docker base image changed from "$1$2" to "$1:$args->{from}"];
            }
        }
        else {
            say q[Error updating docker base image];
        }

        return;
    }

    my $dockerhub_api = Pcore::API::DockerHub->new( { namespace => $self->dist->docker_cfg->{namespace} } );

    my $dockerhub_repo = $dockerhub_api->get_repo( lc $self->dist->name );

    if ( $args->{trigger} ) {
        print qq[Triggering build for tag "$args->{trigger}" ... ];

        my $res = $dockerhub_repo->trigger_build( $args->{trigger} );

        say $res->status ? 'OK' : $res->reason;
    }

    # remove tag
    if ( $args->{remove} ) {
        print qq[Removing tag "$args->{remove}" ... ];

        my $tags = $dockerhub_repo->tags;

        if ( !$tags->{result}->{ $args->{remove} } ) {
            say 'Tag does not exists';
        }
        else {
            my $res = $tags->{result}->{ $args->{remove} }->remove;

            say $res->status ? 'OK' : $res->reason;
        }

        # remove build tag
        print qq[Removing build tag "$args->{remove}" ... ];

        my $build_settings = $dockerhub_repo->build_settings;

        if ( !$build_settings ) {
            say $build_settings->reason;
        }
        else {
            my $build_tag;

            for ( values $build_settings->{result}->{build_tags}->%* ) {
                if ( $_->name eq $args->{remove} ) {
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
    }

    my $cv = AE::cv;

    my ( $tags, $build_history );

    $cv->begin;
    $dockerhub_repo->tags(
        cb => sub ($res) {
            $tags = $res;

            $cv->end;

            return;
        }
    );

    $cv->begin;
    $dockerhub_repo->build_history(
        cb => sub ($res) {
            $build_history = $res;

            $cv->end;

            return;
        }
    );

    $cv->recv;

    my $tbl = P->text->table(
        cols => [
            tag => {
                title => 'TAG NAME',
                width => 20,
            },
            size => {
                width  => 15,
                align  => 1,
                format => sub ( $val, $id, $row ) {
                    return $val ? P->text->format_num($val) : q[-];
                }
            },
            last_updated => {
                title  => 'LAST UPDATED',
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
    for my $tag ( values $tags->{result}->%* ) {
        $report->{ $tag->name } = {
            size         => $tag->full_size,
            last_updated => $tag->last_updated,
        };
    }

    # index builds
    for my $build ( $build_history->{result}->@* ) {
        if ( !exists $report->{ $build->dockertag_name }->{build_status} ) {
            if ( $build->build_status_name eq 'Error' ) {
                $report->{ $build->dockertag_name }->{build_status} = BOLD WHITE ON_RED;
            }
            elsif ( $build->build_status_name eq 'Success' ) {
                $report->{ $build->dockertag_name }->{build_status} = BLACK ON_GREEN;
            }
            else {
                $report->{ $build->dockertag_name }->{build_status} = BLACK ON_WHITE;
            }

            $report->{ $build->dockertag_name }->{build_status} .= q[ ] . $build->build_status_name . q[ ] . RESET;

            $report->{ $build->dockertag_name }->{build_status_updated} = $build->last_updated;
        }
    }

    my $version_tags = [];

    my $named_tags = [];

    for ( keys $report->%* ) {
        $report->{$_}->{tag} = $_;

        if    (/\Av\d+[.]\d+[.]\d+\z/sm) { push $version_tags->@*, $_ }
        elsif ( $_ ne 'latest' )         { push $named_tags->@*,   $_ }
    }

    print $tbl->render_all( [ map { $report->{$_} } ( sort $version_tags->@* ), $report->{latest} ? 'latest' : (), ( sort $named_tags->@* ) ] );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 14                   | Subroutines::ProhibitExcessComplexity - Subroutine "run" with high complexity score (36)                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 20                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 75, 186, 216         | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
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
