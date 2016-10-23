package Pcore::Util::Promise;

use Pcore -class, -export => { PROMISE => [qw[promise then]] };
use Pcore::Util::Promise::Request;
use overload    #
  q[&{}] => sub ( $self, @ ) {
    return sub { return _run( $self, @_ ) };
  },
  fallback => 1;

has _promise => ( is => 'ro', isa => CodeRef, required => 1 );
has _then => ( is => 'ro', isa => Maybe [ ArrayRef [CodeRef] ], default => sub { [] } );

sub promise ( $code, @then ) : prototype(&@) {
    return bless {
        _promise => $code,
        _then    => \@then,
      },
      __PACKAGE__;
}

sub then ( $code, @then ) : prototype(&@) {
    return @_;
}

sub _run ( $self, @ ) {
    my $cb = $_[-1];

    my $req = bless {
        _promise   => $self,
        _cb        => $cb,
        _then_idx  => 0,
        _responded => 0,
      },
      'Pcore::Util::Promise::Request';

    eval { $self->{_promise}->( $req, splice @_, 1, -1 ) };

    if ($@) {
        $@->sendlog;

        $req->done(500);
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
## |    3 | 37                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Promise

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
