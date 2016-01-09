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
        {   account_name => $scm_upstream->username,
            repo_slug    => $scm_upstream->reponame,
            username     => $self->dist->build->user_cfg->{Bitbucket}->{api_username},
            password     => $self->dist->build->user_cfg->{Bitbucket}->{api_password},
        }
    );
}

sub get ( $self, @ ) {
    my %args = (
        id       => undef,
        all      => undef,
        open     => undef,
        resolved => undef,
        closed   => undef,
        splice @_, 1,
    );

    my $id = $args{id};

    my $cv = AE::cv;

    my $status;

    if ( $args{all} ) {
        $status = [ 'new', 'open', 'resolved', 'closed' ];
    }
    elsif ( $args{open} ) {
        $status = [ 'new', 'open' ];
    }
    elsif ( $args{resolved} ) {
        $status = 'resolved';
    }
    elsif ( $args{closed} ) {
        $status = 'closed';
    }
    else {
        $status = [ 'new', 'open' ];
    }

    my $issues;

    $self->api->issues(
        id      => $id,
        status  => $status,
        version => undef,
        sub ($res) {
            $issues = $res;

            $cv->send;

            return;
        }
    );

    $cv->recv;

    return $issues;
}

sub print_issues ( $self, $issues ) {
    if ( !$issues ) {
        say 'No issues';
    }
    else {
        say sprintf '%4s  %-8s  %-9s  %-11s  %s', qw[ID PRIORITY STATUS KIND TITLE];

        if ( blessed $issues ) {
            my $issue = $issues;

            say sprintf '%4s  %s  %-9s  %-11s  %s', $issue->{local_id}, $issue->priority_color, $issue->{status}, $issue->{metadata}->{kind}, $issue->{title};

            say $LF, $issue->{content} || 'No content';
        }
        else {
            for my $issue ( sort { $b->utc_last_updated_ts <=> $a->utc_last_updated_ts or $b->priority_id <=> $a->priority_id } $issues->@* ) {
                say sprintf '%4s  %s  %-9s  %-11s  %s', $issue->{local_id}, $issue->priority_color, $issue->{status}, $issue->{metadata}->{kind}, $issue->{title};
            }
        }
    }

    return;
}

sub create_version ( $self, $ver, $cb ) {
    return $self->api->create_version( $ver, $cb );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 24                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 99                   │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
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
