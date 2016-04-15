package Pcore::Dist::Build::Issues;

use Pcore -class;
use Pcore::Util::Scalar qw[blessed];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has api => ( is => 'lazy', isa => InstanceOf ['Pcore::API::Bitbucket'], init_arg => undef );

around new => sub ( $orig, $self, $args ) {
    my $scm = $args->{dist}->scm;

    return if !$scm || !$scm->upstream;

    return $self->$orig($args);
};

sub _build_api ($self) {
    state $init = !!require Pcore::API::Bitbucket;

    my $scm_upstream = $self->dist->scm->upstream;

    return Pcore::API::Bitbucket->new(
        {   namespace => $scm_upstream->namespace,
            repo_name => $scm_upstream->repo_name,
        }
    );
}

sub get ( $self, @ ) {
    my %args = (
        id        => undef,
        active    => undef,
        new       => undef,
        open      => undef,
        resolved  => undef,
        closed    => undef,
        hold      => undef,
        invalid   => undef,
        duplicate => undef,
        wontfix   => undef,
        splice @_, 1,
    );

    my $status = {};

    $status->@{qw[open resolved closed]} = () if $args{active};

    $status->{new} = undef if $args{new};

    $status->{open} = undef if $args{open};

    $status->{resolved} = undef if $args{resolved};

    $status->{closed} = undef if $args{closed};

    $status->{'on hold'} = undef if $args{hold};

    $status->{invalid} = undef if $args{invalid};

    $status->{duplicate} = undef if $args{duplicate};

    $status->{wontfix} = undef if $args{wontfix};

    # default
    $status->@{qw[open resolved closed]} = () if !$args{id} && !$status->%*;

    my $cv = AE::cv;

    my @status = keys $status->%*;

    if ( $args{id} && @status ) {

        # impossible to set multiple statuses
        croak q[Can't set multiply issue statuses] if @status > 1;

        my $issue;

        $self->api->set_issue_status(
            $args{id},
            $status[0],
            sub ($res) {
                $issue = $res;

                $cv->send;

                return;
            }
        );

        $cv->recv;

        return $issue;
    }
    else {
        my $issues;

        $self->api->issues(
            id        => $args{id},
            status    => \@status,
            milestone => $args{milestone},
            sub ($res) {
                $issues = $res;

                $cv->send;

                return;
            }
        );

        $cv->recv;

        return $issues;
    }
}

sub print_issues ( $self, $issues, $content = 1 ) {
    if ( !$issues ) {
        say 'No issues';
    }
    else {
        my $tbl = P->text->table;

        $tbl->set_cols(qw[ID STATUS PRIORITY KIND TITLE]);
        $tbl->set_col_width( 'TITLE', 100, 1 );
        $tbl->align_col( 'ID', 'right' );

        if ( blessed $issues ) {
            my $issue = $issues;

            $tbl->add_row( $issue->{local_id}, $issue->status_color, $issue->priority_color, $issue->kind_color, $issue->{title} );

            print $tbl->render;

            say $LF, $issue->{content} || 'No content' if $content;
        }
        else {
            for my $issue ( sort { $a->status_id <=> $b->status_id or $b->priority_id <=> $a->priority_id or $b->utc_last_updated_ts <=> $a->utc_last_updated_ts } $issues->@* ) {
                $tbl->add_row( $issue->{local_id}, $issue->status_color, $issue->priority_color, $issue->kind_color, $issue->{title} );
            }

            print $tbl->render;

            say 'max. 50 first issues shown';
        }
    }

    return;
}

sub create_version ( $self, $ver, $cb ) {
    return $self->api->create_version( $ver, $cb );
}

sub create_milestone ( $self, $milestone, $cb ) {
    return $self->api->create_milestone( $milestone, $cb );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 66, 70               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 138                  │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Issues

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
