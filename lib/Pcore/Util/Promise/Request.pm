package Pcore::Util::Promise::Request;

use Pcore -class;
use Pcore::Util::Response;
use Pcore::Util::Scalar qw[blessed];
use overload    #
  q[bool] => sub {
    return $_[0]->{reponse}->{status} >= 200 && $_[0]->{response}->{status} < 300;
  },
  q[0+] => sub {
    return $_[0]->{response}->{status};
  },
  q[""] => sub {
    return "$_[0]->{response}->{status} $_[0]->{response}->{reason}";
  },
  q[<=>] => sub {
    return !$_[2] ? $_[0]->{response}->{status} <=> $_[1] : $_[1] <=> $_[0]->{response}->{status};
  },
  q[@{}] => sub {
    return [ $_[0]->{response}->{status}, $_[0]->{response}->{reason} ];
  },
  q[&{}] => sub ( $self, @ ) {
    return sub { return _respond( $self, @_ ) };
  },
  fallback => 1;

has _promise => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Promise'], required => 1 );
has _cb => ( is => 'ro', isa => CodeRef, required => 1 );
has _self => ( is => 'ro', isa => Object );

has response => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Response'], init_arg => undef );

has _then_idx  => ( is => 'ro', isa => PositiveInt, default => 1, init_arg => undef );
has _responded => ( is => 'ro', isa => Bool,        default => 0, init_arg => undef );    # already responded

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && !$self->{_responded} ) {

        # request object destroyed without return any result, this is possible run-time error in AE callback
        _respond( $self, 500 );
    }

    return;
}

sub status ($self) {
    return $self->{response}->{status};
}

sub reason ($self) {
    return $self->{response}->{reason};
}

sub done ( $self, @ ) {
    die q[Already responded] if $self->{_responded};

    $self->{_responded} = 1;

    $self->{_cb}->( blessed $_[1] ? $_[1] : Pcore::Util::Response::status splice @_, 1 );

    return;
}

sub _respond ( $self, @ ) {
    die q[Already responded] if $self->{_responded};

    my $res = blessed $_[1] ? $_[1] : Pcore::Util::Response::status splice @_, 1;

    if ( my $then = $self->{_promise}->{_then}->[ $self->{_then_idx} ] ) {
        $self->{response} = $res;

        $self->{_then_idx}++;

        eval { $then->( $self, $self->{_self} // () ) };

        if ($@) {
            $@->sendlog;

            if ( !$self->{_responded} ) {
                $self->{_responded} = 1;

                $self->{_cb}->( status 500 );
            }
        }
    }
    else {
        $self->{_responded} = 1;

        $self->{_cb}->($res);
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 76                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Promise::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
