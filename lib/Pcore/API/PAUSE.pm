package Pcore::API::PAUSE;

use Pcore -class, -result;
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::Scalar qw[is_coderef];

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

has _auth_header => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build__auth_header ($self) {
    return 'Basic ' . P->data->to_b64_url( encode_utf8( $self->username ) . q[:] . encode_utf8( $self->password ) ) . q[==];
}

sub upload ( $self, $path, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $on_finish = sub ($res) {
        $cb->($res) if $cb;

        $blocking_cv->($res) if $blocking_cv;
    };

    my $body;

    $path = P->path($path);

    my $boundary = P->random->bytes_hex(64);

    $self->_pack_multipart( \$body, $boundary, 'HIDDENNAME', \encode_utf8( $self->username ) );

    $self->_pack_multipart( \$body, $boundary, 'pause99_add_uri_subdirtext', \q[] );

    $self->_pack_multipart( \$body, $boundary, 'CAN_MULTIPART', \1 );

    $self->_pack_multipart( \$body, $boundary, 'pause99_add_uri_upload', \$path->filename );

    $self->_pack_multipart( \$body, $boundary, 'pause99_add_uri_httpupload', P->file->read_bin($path), $path->filename );

    $self->_pack_multipart( \$body, $boundary, 'pause99_add_uri_uri', \q[] );

    $self->_pack_multipart( \$body, $boundary, 'SUBMIT_pause99_add_uri_httpupload', \q[ Upload this file from my disk ] );

    $body .= q[--] . $boundary . q[--] . $CRLF . $CRLF;

    P->http->post(
        'https://pause.perl.org/pause/authenquery',
        headers => {
            AUTHORIZATION => $self->_auth_header,
            CONTENT_TYPE  => qq[multipart/form-data; boundary=$boundary],
        },
        body => \$body,
        sub ($res) {
            $on_finish->( result [ $res->status, $res->reason ] );

            return;
        }
    );

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

sub clean ( $self, @args ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    my $cb = is_coderef $args[-1] ? pop @args : undef;

    my %args = (
        keep => 2,
        @args,
    );

    my $on_finish = sub ($status) {
        $cb->($status) if $cb;

        $blocking_cv->($status) if $blocking_cv;

        return;
    };

    if ( !$args{keep} ) {
        $on_finish->( result [ 400, q[Bad "keep" arument.] ] );
    }

    P->http->get(
        'https://pause.perl.org/pause/authenquery?ACTION=delete_files',
        headers => { AUTHORIZATION => $self->_auth_header, },
        sub ($res) {
            if ( !$res ) {
                $on_finish->( result [ $res->status, $res->reason ] );
            }
            else {
                my $releases;

                while ( $res->body->$* =~ /input type="checkbox" name="pause99_delete_files_FILE" value="([[:alnum:]-]+)?-v([[:alnum:].]+)?[.]tar[.]gz"(.+?)<\/span>/smg ) {
                    $releases->{$1}->{$2} = undef if $3 !~ m[Scheduled for deletion]smi;
                }

                my $params = [
                    HIDDENNAME                         => encode_utf8( $self->username ),
                    SUBMIT_pause99_delete_files_delete => 'Delete',
                ];

                my $do_request;

                for my $release ( keys $releases->%* ) {
                    my $versions = [ map {"$_"} reverse sort map { version->new($_) } keys $releases->{$release}->%* ];

                    splice $versions->@*, 0, $args{keep}, ();

                    if ( $versions->@* ) {
                        $do_request = 1;

                        for my $version ( $versions->@* ) {
                            push $params->@*, pause99_delete_files_FILE => "$release-v$version.tar.gz";
                            push $params->@*, pause99_delete_files_FILE => "$release-v$version.meta";
                            push $params->@*, pause99_delete_files_FILE => "$release-v$version.readme";
                        }
                    }
                }

                if ( !$do_request ) {
                    $on_finish->( result [ 200, 'Nothing to do' ] );
                }
                else {
                    P->http->post(
                        'https://pause.perl.org/pause/authenquery',
                        headers => {
                            AUTHORIZATION => $self->_auth_header,
                            CONTENT_TYPE  => 'application/x-www-form-urlencoded',
                        },
                        body => P->data->to_uri($params),
                        sub ($res) {
                            $on_finish->( result [ $res->status, $res->reason ] );

                            return;
                        }
                    );
                }
            }

            return;
        }
    );

    return defined $blocking_cv ? $blocking_cv->recv : ();
}

sub _pack_multipart ( $self, $body, $boundary, $name, $content, $filename = undef ) {
    $body->$* .= q[--] . $boundary . $CRLF;

    $body->$* .= qq[Content-Disposition: form-data; name="$name"];

    $body->$* .= qq[; filename="$filename"] if $filename;

    $body->$* .= $CRLF x 2;

    $body->$* .= $content->$*;

    $body->$* .= $CRLF;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 96                   | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 150                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::PAUSE - pause.perl.org API

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
