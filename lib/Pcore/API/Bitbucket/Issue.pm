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
has priority_color => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_priority_id ($self) {
    return $PRIORITY->{ $self->{priority} };
}

sub _build_priority_color ($self) {
    return $PRIORITY_COLOR->{ $self->{priority} } . sprintf( '%-8s', $self->{priority} ) . RESET;
}

# PUT https://api.bitbucket.org/1.0/repositories/{accountname}/{repo_slug}/issues/{issue_id}  --data "parameter=value&parameter=value"
# return issue object
sub set_version ( $self, $ver ) {
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
