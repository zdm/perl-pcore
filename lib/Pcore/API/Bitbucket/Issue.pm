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
    minor    => BOLD . GREEN,
    major    => BOLD . YELLOW,
    critical => BOLD . RED,
    blocker  => BOLD . RED,
};

const our $KIND => {
    bug         => 1,
    enhancement => 2,
    proposal    => 3,
    task        => 4,
};

const our $STATUS => {
    new       => 1,
    open      => 2,
    resolved  => 3,
    closed    => 4,
    'on hold' => 5,
    invalid   => 6,
    duplicate => 7,
    wontfix   => 8,
};

has api => ( is => 'ro', isa => InstanceOf ['Pcore::API::Bitbucket'], required => 1 );

has priority_id => ( is => 'lazy', isa => Enum [ values $PRIORITY->%* ], init_arg => undef );
has priority_color      => ( is => 'lazy', isa => Str, init_arg => undef );
has utc_last_updated_ts => ( is => 'lazy', isa => Int, init_arg => undef );
has url                 => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_priority_id ($self) {
    return $PRIORITY->{ $self->{priority} };
}

sub _build_priority_color ($self) {
    return $PRIORITY_COLOR->{ $self->{priority} } . sprintf( '%-8s', $self->{priority} ) . RESET;
}

sub _build_utc_last_updated_ts ($self) {
    return P->date->from_string( $self->{utc_last_updated} =~ s/\s/T/smr )->epoch;
}

sub _build_url ($self) {
    return "https://bitbucket.org/@{[$self->api->account_name]}/@{[$self->api->repo_slug]}/issues/$self->{local_id}/";
}

sub set_version ( $self, $ver, $cb ) {
    my $url = "https://bitbucket.org/api/1.0/repositories/@{[$self->api->account_name]}/@{[$self->api->repo_slug]}/issues/$self->{local_id}/";

    P->http->put(    #
        $url,
        headers => {
            AUTHORIZATION => $self->api->auth,
            CONTENT_TYPE  => 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body      => P->data->to_uri( { version => $ver } ),
        on_finish => sub ($res) {
            $cb->( $res->status == 200 ? 1 : 0 );

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
## │    3 │ 42                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
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
