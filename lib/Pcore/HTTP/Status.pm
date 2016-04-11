package Pcore::HTTP::Status;

use Pcore -const, -role;

use overload    #
  q[bool] => sub {
    return $_[0]->is_success;
  },
  q[0+] => sub {
    return $_[0]->status;
  },
  q[<=>] => sub {
    return !$_[2] ? $_[0]->status <=> $_[1] : $_[1] <=> $_[0]->status;
  },
  fallback => undef;

has status => ( is => 'ro', isa => PositiveInt, writer => 'set_status', default => 200 );
has reason => ( is => 'ro', isa => Str );

# stolen from HTTP::Status
const our $STATUS_REASON => {

    # 100
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',            # RFC 2518 (WebDAV)

    # 200
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
    208 => 'Already Reported',                # RFC 5842

    # 300
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect',              # RFC 7238

    # 400
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Request Range Not Satisfiable',
    417 => 'Expectation Failed',
    418 => 'I\'m a teapot',                     # RFC 2324
    422 => 'Unprocessable Entity',              # RFC 2518 (WebDAV)
    423 => 'Locked',                            # RFC 2518 (WebDAV)
    424 => 'Failed Dependency',                 # RFC 2518 (WebDAV)
    425 => 'No code',                           # WebDAV Advanced Collections
    426 => 'Upgrade Required',                  # RFC 2817
    428 => 'Precondition Required',
    429 => 'Too Many Requests',
    431 => 'Request Header Fields Too Large',
    449 => 'Retry with',                        # unofficial Microsoft

    # 500
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates',           # RFC 2295
    507 => 'Insufficient Storage',              # RFC 2518 (WebDAV)
    509 => 'Bandwidth Limit Exceeded',          # unofficial
    510 => 'Not Extended',                      # RFC 2774
    511 => 'Network Authentication Required',
};

# COMMON REASON BUILDER
around reason => sub ( $orig, $self ) {
    my $status = $self->status;

    if    ( exists $self->{reason} )           { return $self->{reason} }
    elsif ( exists $STATUS_REASON->{$status} ) { return $STATUS_REASON->{$status} }
    elsif ( $status >= 100 && $status < 200 ) { return 'INFO' }
    elsif ( $status >= 200 && $status < 300 ) { return 'OK' }
    elsif ( $status >= 300 && $status < 400 ) { return 'REDIRECT' }
    elsif ( $status >= 400 && $status < 500 ) { return 'CLIENT ERROR' }
    elsif ( $status >= 500 && $status < 600 ) { return 'SERVER ERROR' }
    else                                      { return 'UNKNOWN' }
};

# STATUS WRITER
around set_status => sub ( $orig, $self, $status, $reason = undef ) {
    $self->$orig($status);

    if ( defined $reason ) { $self->{reason} = $reason }
    else                   { delete $self->{reason} }

    return;
};

# STATUS METHODS
sub is_info ($self) {
    return $self->status >= 100 && $self->status < 200;
}

sub is_success ($self) {
    return $self->status >= 200 && $self->status < 300;
}

sub is_redirect ($self) {
    return $self->status >= 300 && $self->status < 400;
}

sub is_error ($self) {
    return $self->status >= 400 && $self->status < 600;
}

sub is_client_error ($self) {
    return $self->status >= 400 && $self->status < 500;
}

sub is_server_error ($self) {
    return $self->status >= 500 && $self->status < 600;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 97                   │ ControlStructures::ProhibitCascadingIfElse - Cascading if-elsif chain                                          │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Status

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
