package Pcore::AnyEvent::Crawler::Request;

use Pcore qw[-role];
use Const::Fast qw[];

Const::Fast::const our $PROXY_NO     => 1;
Const::Fast::const our $PROXY_MAYBE  => 2;
Const::Fast::const our $PROXY_ALWAYS => 3;

requires qw[_build_type process_response];

has id => ( is => 'lazy', isa => Maybe [Str] );

# TODO make lazy
has url => ( is => 'lazy', isa => Str );

has use_proxy => ( is => 'ro', isa => Enum [ $PROXY_NO, $PROXY_MAYBE, $PROXY_ALWAYS ], default => $PROXY_NO );

has crawler => ( is => 'ro', isa => InstanceOf ['Pcore::AnyEvent::Crawler'], writer => 'set_crawler', weak_ref => 1, init_arg => undef );

has type => ( is => 'lazy', isa => Str, init_arg => undef );

# response related attributes
has res => ( is => 'ro', writer => 'set_res', clearer => 1, init_arg => undef );
has results => ( is => 'lazy', isa => HashRef, default => sub { {} }, clearer => 1, init_arg => undef );

around process_response => sub ( $orig, $self, $res, $responder ) {
    my $action = $self->$orig($res);

    if ( ref $action eq 'CODE' ) {
        $action->( $self, $responder );
    }
    else {
        $responder->($action);
    }

    return;
};

no Pcore;

sub _build_id ($self) {
    return;
}

sub status ($self) {
    return $self->res->status;
}

sub reason ($self) {
    return $self->res->reason;
}

sub clear ($self) {
    $self->clear_proxy;

    $self->clear_results;

    $self->clear_res;

    return;
}

# EXIT CODES
# used by default
sub done ($self) {
    return $Pcore::AnyEvent::Crawler::REQ_DONE;
}

# repeat request with new proxy
sub repeat ($self) {
    return $Pcore::AnyEvent::Crawler::REQ_REPEAT;
}

# do not call request store subroutine
sub reject ($self) {
    return $Pcore::AnyEvent::Crawler::REQ_REJECT;
}

# PROXY
sub disable_proxy ($self) {
    $self->proxy->disable if $self->has_proxy;

    return;
}

sub ban_proxy ($self) {
    $self->proxy->ban if $self->has_proxy;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Crawler::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
