package Pcore::API::S3;

use Pcore -class, -res, -const;
use Pcore::Util::Digest qw[sha256_hex hmac_sha256 hmac_sha256_hex];
use Pcore::Util::Scalar qw[is_ref is_plain_coderef];
use Pcore::Util::Data qw[to_uri_query from_xml];
use Pcore::Util::Scalar qw[weaken];

has key      => ();
has secret   => ();
has bucket   => ();
has region   => ();
has service  => 's3';
has endpoint => 'digitaloceanspaces.com';

has max_threads => 50;
has _queue      => ();
has _threads    => 0;
has _signal     => sub { Coro::Signal->new };

const our $S3_ACL_READ_ONLY    => 0;
const our $S3_ACL_FULL_CONTROL => 1;

sub DESTROY ($self) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) {

        # finish threads
        $self->{_signal}->broadcast;

        # finish tasks
        while ( my $task = shift $self->{_queue}->@* ) {
            $task->{cb}->( res 500 ) if $task->{cb};
        }
    }

    return;
}

sub _req ( $self, $args ) {
    my $cv;

    if ( defined wantarray ) {
        $cv = P->cv;

        my $cb = delete $args->{cb};

        $args->{cb} = sub ($res) { $cv->( $cb ? $cb->($res) : $res ) };
    }

    push $self->{_queue}->@*, $args;

    if ( $self->{_signal}->awaited ) {
        $self->{_signal}->send;
    }
    elsif ( $self->{_threads} < $self->{max_threads} ) {
        $self->_run_thread;
    }

    return $cv ? $cv->recv : ();
}

sub _run_thread ($self) {
    weaken $self;

    $self->{_threads}++;

    my $coro = Coro::async_pool {
        while () {
          REDO:
            last if !defined $self;

            if ( my $task = shift $self->{_queue}->@* ) {
                my $res = $self->_req1($task);

                $task->{cb}->($res) if $task->{cb};

                goto REDO;
            }

            $self->{_signal}->wait;
        }

        $self->{_threads}--;

        return;
    };

    $coro->cede_to;

    return;
}

sub _req1 ( $self, $args ) {
    no warnings qw[uninitialized];

    $args->{path} = "/$args->{path}" if substr( $args->{path}, 0, 1 ) ne '/';

    my $uri = P->uri( sprintf "https://%s%s.$self->{endpoint}%s?%s", $args->{bucket} ? "$args->{bucket}." : '', $args->{region} || $self->{region}, $args->{path}, defined $args->{query} ? to_uri_query $args->{query} : '' );

    my $date          = P->date->now_utc;
    my $date_ymd      = $date->strftime('%Y%m%d');
    my $date_iso08601 = $date->strftime('%Y%m%dT%H%M%SZ');
    my $data_hash     = sha256_hex( $args->{data} ? $args->{data}->$* : q[] );

    $args->{headers}->{'Host'}                 = $uri->{host};
    $args->{headers}->{'X-Amz-Date'}           = $date_iso08601;
    $args->{headers}->{'X-Amz-Content-Sha256'} = $data_hash if $data_hash;

    my $canon_req = "$args->{method}\n$uri->{path}\n$uri->{query}\n";

    my @signed_headers;

    for my $header ( sort keys $args->{headers}->%* ) {
        push @signed_headers, lc $header;

        $canon_req .= lc($header) . ":$args->{headers}->{$header}\n";
    }

    my $signed_headers = join ';', @signed_headers;

    $canon_req .= "\n$signed_headers\n$data_hash";

    my $credential_scope = "$date_ymd/$args->{region}/$self->{service}/aws4_request";
    my $string_to_sign   = "AWS4-HMAC-SHA256\n$date_iso08601\n$credential_scope\n" . sha256_hex $canon_req;

    my $k_date = hmac_sha256 $date_ymd, "AWS4$self->{secret}";
    my $k_region  = hmac_sha256 $args->{region},  $k_date;
    my $k_service = hmac_sha256 $self->{service}, $k_region;
    my $sign_key = hmac_sha256 'aws4_request', $k_service;
    my $signature = hmac_sha256_hex $string_to_sign, $sign_key;

    return P->http->request(
        method  => $args->{method},
        url     => $uri,
        headers => [
            $args->{headers}->%*,
            Referer       => undef,
            Authorization => qq[AWS4-HMAC-SHA256 Credential=$self->{key}/$credential_scope,SignedHeaders=$signed_headers,Signature=$signature],
        ],
        data => $args->{data},
    );
}

sub get_buckets ( $self, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        @args,
        method => 'GET',
        cb     => sub ($res) {
            if ($res) {
                $res->{data} = from_xml $res->{data};

                my ( $data, $meta );

                for my $key ( keys $res->{data}->{ListAllMyBucketsResult}->%* ) {
                    if ( $key eq 'Buckets' ) {
                        for my $item ( $res->{data}->{ListAllMyBucketsResult}->{$key}->[0]->{Bucket}->@* ) {
                            $data->{ $item->{Name}->[0]->{content} } = {
                                name          => $item->{Name}->[0]->{content},
                                creation_date => $item->{CreationDate}->[0]->{content},
                            };
                        }
                    }
                    else {
                        $meta->{$key} = $res->{data}->{ListBucketResult}->{$key}->[0]->{content};
                    }
                }

                $res = res 200, $data, meta => $meta;
            }

            return $cb ? $cb->($res) : $res;
        }
    };

    return $self->_req($args);
}

sub get_bucket_location ( $self, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        bucket => $self->{bucket},
        @args,
        method => 'GET',
        query  => 'location=',
        cb     => sub ($res) {
            if ($res) {
                $res->{data} = from_xml $res->{data};

                $res = res 200, $res->{data}->{LocationConstraint}->{content};
            }

            return $cb ? $cb->($res) : $res;
        }
    };

    return $self->_req($args);
}

# - max: default 1000, 1000 is maximum allowed value;
# - prefix: NOTE: must be relative. A string used to group keys. When specified, the response will only contain objects with keys beginning with the string;
# - delim: A single character used to group keys. When specified, the response will only contain keys up to its first occurrence. (E.g. Using a slash as the delimiter can allow you to list keys as if they were folders, especially in combination with a prefix.);
sub get_bucket_content ( $self, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my %args = @args;

    my $args = {
        bucket => $args{bucket} || $self->{bucket},
        region => $args{region} || $self->{region},
        method => 'GET',
        path   => '/',
        query  => [
            delimiter  => $args{delim} // '',
            marker     => $args{marker} // '',
            'max-keys' => $args{max} // '',
            prefix     => $args{prefix} // '',
        ],
        cb => sub ($res) {
            if ( $res && $res->{data} ) {
                $res->{data} = from_xml $res->{data};

                my ( $data, $meta );

                for my $key ( keys $res->{data}->{ListBucketResult}->%* ) {
                    if ( $key eq 'Contents' ) {
                        for my $item ( $res->{data}->{ListBucketResult}->{$key}->@* ) {
                            $data->{ $item->{Key}->[0]->{content} } = {
                                path          => '/' . $item->{Key}->[0]->{content},
                                etag          => $item->{ETag}->[0]->{content} =~ s/"//smgr,
                                last_modified => $item->{LastModified}->[0]->{content},
                                size          => $item->{Size}->[0]->{content},
                            };
                        }
                    }
                    else {
                        $meta->{$key} = $res->{data}->{ListBucketResult}->{$key}->[0]->{content};
                    }
                }

                $res = res 200, $data, meta => $meta;
            }

            return $cb ? $cb->($res) : $res;
        }
    };

    return $self->_req($args);
}

sub get_all_bucket_content ( $self, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my %args = @args;

    $args{max} = 1000;

    my $result = res 200;

    my $cv = defined wantarray ? P->cv : ();

    my $req = sub {
        my $sub = __SUB__;

        $self->get_bucket_content(
            %args,
            sub ($res) {
                if ( !$res ) {
                    $result = $res;
                }
                else {
                    $result->{data}->@{ keys $res->{data}->%* } = values $res->{data}->%*;

                    if ( $res->{meta}->{IsTruncated} eq 'true' ) {
                        $args{marker} = $res->{meta}->{NextMarker};

                        $sub->();

                        return;
                    }
                }

                if ($cv) {
                    $cv->( $cb ? $cb->($result) : $result );
                }
                else {
                    $cb->($result) if $cb;
                }

                return;
            }
        );

        return;
    };

    $req->();

    return $cv ? $cv->recv : ();
}

sub upload ( $self, $path, $data, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        bucket  => $self->{bucket},
        private => 0,
        mime    => undef,
        cache   => undef,
        @args,
        method => 'PUT',
        path   => $path,
        cb     => $cb,
    };

    my $buf = is_ref $data ? $data : \$data;

    $args->{data} = $buf;

    $args->{headers} = {
        'Content-Length' => length $buf->$*,
        $args->{mime}  ? ( 'Content-Type'  => $args->{mime} )  : (),
        $args->{cache} ? ( 'Cache-Control' => $args->{cache} ) : (),
        'X-Amz-Acl' => $args->{private} ? 'private' : 'public-read',
    };

    return $self->_req($args);
}

sub get_object ( $self, $path, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        bucket => $self->{bucket},
        @args,
        method => 'GET',
        path   => $path,
        cb     => $cb
    };

    return $self->_req($args);
}

sub get_metadata ( $self, $path, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        bucket => $self->{bucket},
        @args,
        method => 'HEAD',
        path   => $path,
        cb     => sub ($res) {
            if ($res) {
                $res->{headers}->{ETAG} =~ s/"//smg;

                $res = res 200, $res->{headers};
            }

            return $cb ? $cb->($res) : $res;
        },
    };

    return $self->_req($args);
}

sub remove ( $self, $path, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        bucket => $self->{bucket},
        @args,
        method => 'DELETE',
        path   => $path,
        cb     => $cb
    };

    return $self->_req($args);
}

sub get_acl ( $self, $path, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $args = {
        bucket => $self->{bucket},
        @args,
        method => 'GET',
        query  => 'acl=',
        path   => $path,
        cb     => sub ($res) {
            if ($res) {
                $res->{data} = from_xml $res->{data};

                my $data;

                for my $grant ( $res->{data}->{AccessControlPolicy}->{AccessControlList}->[0]->{Grant}->@* ) {
                    if ( $grant->{Grantee}->[0]->{URI} ) {
                        $data->{'*'} = $grant->{Permission}->[0]->{content} eq 'READ' ? $S3_ACL_READ_ONLY : $S3_ACL_FULL_CONTROL;
                    }
                    else {
                        $data->{ $grant->{Grantee}->[0]->{ID}->[0]->{content} } = $grant->{Permission}->[0]->{content} eq 'READ' ? $S3_ACL_READ_ONLY : $S3_ACL_FULL_CONTROL;
                    }
                }

                $res = res 200, $data;
            }

            return $cb ? $cb->($res) : $res;
        }
    };

    return $self->_req($args);
}

# TODO fucking stupid API, created by stupid idiots
sub set_public_access ( $self, $path, $enabled, @args ) {
    my $cb = is_plain_coderef $_[-1] ? pop @args : ();

    my $data = <<"XML";
<AccessControlPolicy xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <AccessControlList>
        <Grant>
            <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Group">
                <URI>http://acs.amazonaws.com/groups/global/AllUsers</URI>
            </Grantee>
            <Permission>READ</Permission>
        </Grant>
    </AccessControlList>
</AccessControlPolicy>
XML

    my $args = {
        bucket => $self->{bucket},
        @args,
        method  => 'PUT',
        query   => 'acl=',
        path    => $path,
        headers => { 'Content-Length' => length $data },
        data    => \$data,
        cb      => $cb
    };

    return $self->_req($args);
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 98, 216, 217, 218,   | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |      | 219                  |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::S3

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
