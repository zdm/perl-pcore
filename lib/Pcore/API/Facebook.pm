package Pcore::API::Facebook;

use Pcore -const, -class, -res;
use Pcore::Lib::Data qw[to_uri from_json];
use Pcore::Lib::Scalar qw[is_plain_arrayref];

with qw[
  Pcore::API::Facebook::User
  Pcore::API::Facebook::Marketing
];

has token       => ( required => 1 );
has max_threads => 1;

has _threads => ( 0, init_arg => undef );
has _queue   => ( init_arg    => undef );

const our $DEFAULT_LIMIT => 500;

sub _req ( $self, $method, $path, $params = undef, $data = undef ) {

    # block thread
    if ( $self->{max_threads} && $self->{_threads} == $self->{max_threads} ) {
        my $cv = P->cv;

        push $self->{_queue}->@*, $cv;

        $cv->recv;
    }

    $self->{_threads}++;

    my $url = "https://graph.facebook.com/$path?access_token=$self->{token}";

    my $limit;

    if ($params) {
        $limit = delete $params->{limit};

        $params->{fields} = join ',', $params->{fields}->@* if is_plain_arrayref $params->{fields};

        $url .= '&' . to_uri $params;
    }

    if ($limit) {
        $url .= "&limit=$limit";
    }
    else {
        $url .= "&limit=$DEFAULT_LIMIT";
    }

    my $result = res 200;

  GET_NEXT_PAGE:
    my $res = P->http->request(
        method => $method,
        url    => $url,
        data   => $data,
    );

    my $res_data = $res->{data} ? from_json $res->{data} : undef;

    if ($res) {
        if ($res_data) {
            if ( $res_data->{paging} || is_plain_arrayref $res_data->{data} ) {
                push $result->{data}->@*, $res_data->{data}->@*;

                # get all records
                if ( !$limit && ( $url = $res_data->{paging}->{next} ) ) {
                    goto GET_NEXT_PAGE;
                }
            }
            else {
                $result->{data} = $res_data;
            }
        }
    }

    # request error
    else {
        $result = res [ $res->{status}, $res_data->{error}->{message} ];
    }

    $self->{_threads}--;

    if ( my $cv = shift $self->{_queue}->@* ) { $cv->() }

    return $result;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 20                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_req' declared but not used         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Facebook

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
