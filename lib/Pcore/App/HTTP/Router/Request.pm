package Pcore::App::HTTP::Router::Request;

use Pcore -class;

has env       => ( is => 'ro', isa => HashRef, required => 1 );
has responder => ( is => 'ro', isa => CodeRef, required => 1 );

has _headers_written => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has _body_written    => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

sub write_headers ( $self, $status, $headers = undef ) {
    die qq[Headers already written] if $self->{_headers_written};

    $self->{_headers_written} = 1;

    $self->{responder} = $self->{responder}->( [ $status, $headers // [] ] );

    return $self;
}

sub write ( $self, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    if ( !$self->{_headers_written} ) {
        $self->{_headers_written} = 1;

        $self->{_body_written} = 1;

        $self->{responder}->( [ splice @_, 1 ] );
    }
    else {
        die if !$self->{_headers_written};

        die if $self->{_body_written};

        $self->{responder}->write( $_[1] );
    }

    return $self;
}

sub finish ( $self, $trailing_headers = undef ) {
    die if !$self->{_headers_written};

    die if $self->{_body_written};

    $self->{_body_written} = 1;

    $self->{responder}->close($trailing_headers);

    undef $self->{responder};

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 12                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::HTTP::Router::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
