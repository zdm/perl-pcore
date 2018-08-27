package <: $module_name ~ "::RPC::Worker" :>;

use Pcore -class, -const;
use <: $module_name ~ "::Const qw[:CONST]" :>;

with qw[<: $module_name ~ "::RPC" :>];

const our $NODE_REQUIRES => {

    # '*' => 'test',
    # 'main' => ['test'],    # list of required events
};

sub NODE_ON_EVENT ( $self, $ev ) {
    P->forward_event($ev);

    return;
}

sub BUILD ( $self, $args ) {
    $self->{node}->wait_online;

    return;
}

sub API_test ( $self, $req, @args ) {
    $req->( 200, time );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 1, 4                 | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 46                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 50 does not match the package declaration       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

<: $module_name ~ "::RPC::Worker" :>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
