package Pcore::API::Bitbucket::Issue;

use Pcore -class, -const;
use Term::ANSIColor qw[:constants];

const our $PRIORITY => {
    trivial  => 1,
    minor    => 2,
    major    => 3,
    critical => 4,
    blocker  => 5,
};

const our $PRIORITY_COLOR => {
    trivial  => WHITE,
    minor    => BLACK . ON_WHITE,
    major    => BLACK . ON_YELLOW,
    critical => WHITE . ON_RED,
    blocker  => BOLD . WHITE . ON_RED,
};

const our $KIND => {
    bug         => [ 'bug',  WHITE . ON_RED ],
    enhancement => [ 'enh',  WHITE ],
    proposal    => [ 'prop', WHITE ],
    task        => [ 'task', WHITE ],
};

const our $STATUS => {
    new       => BLACK . ON_WHITE,
    open      => BLACK . ON_WHITE,
    resolved  => WHITE . ON_RED,
    closed    => BLACK . ON_GREEN,
    'on hold' => WHITE . ON_BLUE,
    invalid   => WHITE . ON_BLUE,
    duplicate => WHITE . ON_BLUE,
    wontfix   => WHITE . ON_BLUE,
};

has api => ( is => 'ro', isa => InstanceOf ['Pcore::API::Bitbucket'], required => 1 );

has priority_id => ( is => 'lazy', isa => Enum [ values $PRIORITY->%* ], init_arg => undef );
has priority_color      => ( is => 'lazy', isa => Str, init_arg => undef );
has status_color        => ( is => 'lazy', isa => Str, init_arg => undef );
has kind_color          => ( is => 'lazy', isa => Str, init_arg => undef );
has kind_abbr           => ( is => 'lazy', isa => Str, init_arg => undef );
has utc_last_updated_ts => ( is => 'lazy', isa => Int, init_arg => undef );
has url                 => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_priority_id ($self) {
    return $PRIORITY->{ $self->{priority} };
}

sub _build_priority_color ($self) {
    return $PRIORITY_COLOR->{ $self->{priority} } . " $self->{priority} " . RESET;
}

sub _build_status_color ($self) {
    return $STATUS->{ $self->{status} } . " $self->{status} " . RESET;
}

sub _build_kind_color ($self) {
    return $KIND->{ $self->{metadata}->{kind} }->[1] . " @{[$self->kind_abbr]} " . RESET;
}

sub _build_kind_abbr ($self) {
    return $KIND->{ $self->{metadata}->{kind} }->[0];
}

sub _build_utc_last_updated_ts ($self) {
    return P->date->from_string( $self->{utc_last_updated} =~ s/\s/T/smr )->epoch;
}

sub _build_url ($self) {
    return "https://bitbucket.org/@{[$self->api->account_name]}/@{[$self->api->repo_slug]}/issues/$self->{local_id}/";
}

sub set_status ( $self, $status, $cb ) {
    $self->update( { status => $status }, $cb );

    return;
}

sub set_version ( $self, $ver, $cb ) {
    $self->update( { version => $ver }, $cb );

    return;
}

sub set_milestone ( $self, $milestone, $cb ) {
    $self->update( { milestone => $milestone }, $cb );

    return;
}

sub update ( $self, $args, $cb ) {
    my $url = "https://bitbucket.org/api/1.0/repositories/@{[$self->api->account_name]}/@{[$self->api->repo_slug]}/issues/$self->{local_id}/";

    P->http->put(    #
        $url,
        headers => {
            AUTHORIZATION => $self->api->auth,
            CONTENT_TYPE  => 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body      => P->data->to_uri($args),
        on_finish => sub ($res) {
            if ( $res->status != 200 ) {
                $cb->();
            }
            else {
                my $json = P->data->from_json( $res->body );

                my $issue = $self->new( { api => $self->api } );

                $issue->@{ keys $json->%* } = values $json->%*;

                $cb->($issue);
            }

            return;
        },
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 42, 115              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Bitbucket::Issue

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
