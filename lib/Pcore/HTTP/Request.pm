package Pcore::HTTP::Request;

use Pcore qw[-class -const];
use Pcore::HTTP::UA;
use Pcore::HTTP::Response;
use Pcore::HTTP::CookieJar;

extends qw[Pcore::HTTP::Message];

# METHOD => $ALLOW_BODY
const our $HTTP_METHODS => {
    OPTIONS => 1,
    GET     => 0,
    HEAD    => 0,
    POST    => 1,
    PUT     => 1,
    DELETE  => 0,
    TRACE   => 0,
    CONNECT => 0,
};

has blocking => ( is => 'ro', isa => Bool | InstanceOf ['AnyEvent::CondVar'] );
has method => ( is => 'ro', isa => Enum [ keys $HTTP_METHODS ], required => 1 );
has url => ( is => 'ro', isa => Str, required => 1 );

has recurse    => ( is => 'ro', isa => PositiveOrZeroInt );
has timeout    => ( is => 'ro', isa => PositiveOrZeroInt );
has persistent => ( is => 'ro', isa => Bool );
has session    => ( is => 'ro', isa => Str );
has cookie_jar => ( is => 'ro', isa => Ref );
has tls_ctx    => ( is => 'ro', isa => Maybe [ Enum [ $Pcore::HTTP::UA::TLS_CTX_LOW, $Pcore::HTTP::UA::TLS_CTX_HIGH ] | HashRef ] );

has handle_params => ( is => 'ro', isa => HashRef );

has accept_compressed => ( is => 'ro', default => 1 );
has decompress        => ( is => 'ro', default => 1 );

has proxy => ( is => 'ro', writer => 'set_proxy', predicate => 1, clearer => 1 );

has on_header   => ( is => 'ro', isa => CodeRef );
has on_body     => ( is => 'ro', isa => CodeRef );
has on_progress => ( is => 'ro', isa => CodeRef );
has on_finish   => ( is => 'ro', isa => CodeRef );

no Pcore;

sub BUILDARGS ( $self, $args = undef ) {
    $args //= {};

    if ( $args->{on_progress} && ref $args->{on_progress} ne 'CODE' ) {
        $args->{on_progress} = $self->_get_progress_bar_cb( ref $args->{on_progress} eq 'HASH' ? $args->{on_progress}->%* : () );
    }
    else {
        delete $args->{on_progress};
    }

    $args->{cookie_jar} = Pcore::HTTP::CookieJar->new if $args->{cookie_jar} && $args->{cookie_jar} == 1;

    return $args;
}

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->headers->set( $args->{headers} ) if $args->{headers};

    $self->set_body( $args->{body} ) if $args->{body};

    return;
}

sub _get_progress_bar_cb ( $self, %args ) {
    return sub ( $res, $content_length, $bytes_received ) {
        state $indicator;

        if ( !$bytes_received ) {    # called after headers received
            $args{network} = 1;

            $args{total} = $content_length;

            $indicator = P->progress->get_indicator(%args);
        }
        else {
            $indicator->update( value => $bytes_received );
        }

        return;
    };
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 51                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
