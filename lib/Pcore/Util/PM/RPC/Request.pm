package Pcore::Util::PM::RPC::Request;

use Pcore -class;

use overload    #
  q[&{}] => sub ( $self, @ ) {
    use subs qw[write];

    return sub { return write( $self, @_ ) };
  },
  fallback => undef;

has cb => ( is => 'ro', isa => Maybe [CodeRef] );

has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && !$self->{_response_status} && $self->{cb} ) {

        # RPC request object destroyed without return any result, this is possible run-time error in AE callback
        $self->{cb}->(500);
    }

    return;
}

sub write ( $self, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    die q[Already responded] if $self->{_response_status};

    $self->{_response_status} = 1;

    # remove callback
    my $cb = delete $self->{cb};

    # return response, if callback is defined
    $cb->( 200, @_ > 1 ? [ splice @_, 1 ] : () ) if $cb;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 9                    | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
