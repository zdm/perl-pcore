package Pcore::Util::Status;

use Pcore -const, -class;

use overload    #
  q[bool] => sub {
    return $_[0]->is_success;
  },
  q[0+] => sub {
    return $_[0]->{status};
  },
  q[""] => sub {
    return "$_[0]->{status} $_[0]->{reason}";
  },
  q[<=>] => sub {
    return !$_[2] ? $_[0]->{status} <=> $_[1] : $_[1] <=> $_[0]->{status};
  },
  q[&{}] => sub {
    my $self = $_[0];

    return sub {
        if ( ref $_[0] eq 'ARRAY' ) {
            $self->{status} = $_[0]->[0];

            $self->{reason} = $_[0]->[1];
        }
        else {
            $self->{status} = $_[0];

            $self->{reason} = get_reason->( undef, $_[0], $self->{status_reason} );
        }

        return;
    };
  },
  q[@{}] => sub {
    return [ $_[0]->{status}, $_[0]->{reason} ];
  },
  fallback => undef;

has status => ( is => 'ro', isa => PositiveInt, writer => undef, required => 1 );
has reason => ( is => 'ro', isa => Str,         writer => undef, required => 1 );

has status_reason => ( is => 'ro', isa => Maybe [HashRef] );

# http://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
const our $STATUS_REASON => {

    # 100
    '1xx' => 'Informational',
    100   => 'Continue',
    101   => 'Switching Protocols',
    102   => 'Processing',

    # 200
    '2xx' => 'Success',
    200   => 'OK',
    201   => 'Created',
    202   => 'Accepted',
    203   => 'Non-Authoritative Information',
    204   => 'No Content',
    205   => 'Reset Content',
    206   => 'Partial Content',
    207   => 'Multi-Status',
    208   => 'Already Reported',
    226   => 'IM Used',

    # 300
    '3xx' => 'Redirection',
    300   => 'Multiple Choices',
    301   => 'Moved Permanently',
    302   => 'Found',
    303   => 'See Other',
    304   => 'Not Modified',
    305   => 'Use Proxy',
    307   => 'Temporary Redirect',
    308   => 'Permanent Redirect',

    # 400
    '4xx' => 'Client Error',
    400   => 'Bad Request',
    401   => 'Unauthorized',
    402   => 'Payment Required',
    403   => 'Forbidden',
    404   => 'Not Found',
    405   => 'Method Not Allowed',
    406   => 'Not Acceptable',
    407   => 'Proxy Authentication Required',
    408   => 'Request Timeout',
    409   => 'Conflict',
    410   => 'Gone',
    411   => 'Length Required',
    412   => 'Precondition Failed',
    413   => 'Payload Too Large',
    414   => 'URI Too Long',
    415   => 'Unsupported Media Type',
    416   => 'Range Not Satisfiable',
    417   => 'Expectation Failed',
    421   => 'Misdirected Request',
    422   => 'Unprocessable Entity',
    423   => 'Locked',
    424   => 'Failed Dependency',
    426   => 'Upgrade Required',
    428   => 'Precondition Required',
    429   => 'Too Many Requests',
    431   => 'Request Header Fields Too Large',
    451   => 'Unavailable For Legal Reasons',

    # 500
    '5xx' => 'Server Error',
    500   => 'Internal Server Error',
    501   => 'Not Implemented',
    502   => 'Bad Gateway',
    503   => 'Service Unavailable',
    504   => 'Gateway Timeout',
    505   => 'HTTP Version Not Supported',
    506   => 'Variant Also Negotiates',
    507   => 'Insufficient Storage',
    508   => 'Loop Detected',
    510   => 'Not Extended',
    511   => 'Network Authentication Required',
};

sub BUILDARGS ( $self, $status, $status_reason = undef ) {
    my $reason;

    if ( ref $status eq 'ARRAY' ) {
        $reason = $status->[1];

        $status = $status->[0];
    }
    else {
        $reason = get_reason->( undef, $status, $status_reason );
    }

    return {
        status        => $status,
        reason        => $reason,
        status_reason => $status_reason,
    };
}

sub get_reason ( $self, $status, $status_reason = undef ) {
    if ( $status_reason && $status_reason->{$status} ) { return $status_reason->{$status} }
    elsif ( exists $STATUS_REASON->{$status} ) { return $STATUS_REASON->{$status} }
    elsif ( $status < 200 ) { return $STATUS_REASON->{'1xx'} }
    elsif ( $status >= 200 && $status < 300 ) { return $STATUS_REASON->{'2xx'} }
    elsif ( $status >= 300 && $status < 400 ) { return $STATUS_REASON->{'3xx'} }
    elsif ( $status >= 400 && $status < 500 ) { return $STATUS_REASON->{'4xx'} }
    else                                      { return $STATUS_REASON->{'5xx'} }
}

# STATUS METHODS
sub is_info ($self) {
    return $self->{status} < 200;
}

sub is_success ($self) {
    return $self->{status} >= 200 && $self->{status} < 300;
}

sub is_redirect ($self) {
    return $self->{status} >= 300 && $self->{status} < 400;
}

sub is_error ($self) {
    return $self->{status} >= 400;
}

sub is_client_error ($self) {
    return $self->{status} >= 400 && $self->{status} < 500;
}

sub is_server_error ($self) {
    return $self->{status} >= 500;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Status

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
