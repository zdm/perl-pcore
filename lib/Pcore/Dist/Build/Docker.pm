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
        {   cols => [
                name      => { width => 20, },
                full_size => {
                    title  => 'SIZE',
                    width  => 15,
                    align  => 1,
                    format => sub ( $val, $id, $row ) {
                        return P->text->format_num($val);
                    }
                },
                last_updated => {
                    title  => 'LAST UPDATED',
                    width  => 35,
                    format => sub ( $val, $id, $row ) {
                        return P->date->from_string($val)->to_http_date;
                    }
                },
                latest_build => {
                    title  => 'LATEST BUILD STATUS',
                    width  => 15,
                    format => sub ( $val, $id, $row ) {
                        return $val->build_status_name || 'unknown' if $val;
                    }
                },
                latest_build_update => {
                    title  => 'LATEST BUILD UPDATED',
                    width  => 35,
                    format => sub ( $val, $id, $row ) {
                        return P->date->from_string( $row->{latest_build}->{last_updated} )->to_http_date;
                    }
                },
            ],
        }
    );

    print $tbl->render_header;

    for my $tag ( values $tags->{result}->%* ) {

        # find latest build for this tag
        for my $build ( $build_history->{result}->@* ) {
            if ( $build->dockertag_name eq $tag->name ) {
                $tag->{latest_build} = $build;

                last;
            }
        }

        print $tbl->render_row($tag);
    }

    print $tbl->finish;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 85                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
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
