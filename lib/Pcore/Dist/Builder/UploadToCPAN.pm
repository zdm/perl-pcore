package Dist::Zilla::Plugin::Pcore::UploadToCPAN;

use Moose;
use Pcore;

with qw[Dist::Zilla::Role::ReleaseStatusProvider Dist::Zilla::Role::BeforeRelease Dist::Zilla::Role::Releaser];

no Pcore;
no Moose;

sub provide_release_status ( $self, @ ) {

    # stable = release
    # testing = beta
    # unstable = alpha

    return 'stable';
}

sub before_release ( $self, @ ) {
    my $stash = $self->zilla->stash_named('%PAUSE');

    if ( !$stash->username ) {
        croak q[You need to supply a PAUSE username. Run "pcore setup"];
    }

    if ( !$stash->password ) {
        croak q[You need to supply a PAUSE password. Run "pcore setup"];
    }

    return;
}

sub release ( $self, $archive ) {
    my $stash = $self->zilla->stash_named('%PAUSE');

    $self->log(q[Start upload to CPAN]);

    my ( $status, $reason ) = $self->_upload( $stash->username, $stash->password, qq[$archive] );

    if ( $status == 200 ) {
        $self->log(qq[Upload to CPAN status: $reason]);
    }
    else {
        croak qq[Upload to CPAN status: $status, Reason: $reason];
    }

    return;
}

sub _upload ( $self, $username, $password, $path ) {
    my $body;

    P->text->encode_utf8($username);

    P->text->encode_utf8($password);

    $path = P->path($path);

    my $boundary = P->random->bytes_hex(64);

    state $pack_multipart = sub ( $name, $body_ref, $filename = q[] ) {
        $body .= q[--] . $boundary . $CRLF;

        $body .= qq[Content-Disposition: form-data; name="$name"];

        $body .= qq[; filename="$filename"] if $filename;

        $body .= $CRLF;

        $body .= $CRLF;

        $body .= $body_ref->$*;

        $body .= $CRLF;

        return;
    };

    $pack_multipart->( 'HIDDENNAME', \$username );

    $pack_multipart->( 'pause99_add_uri_subdirtext', \q[] );

    $pack_multipart->( 'CAN_MULTIPART', \1 );

    $pack_multipart->( 'pause99_add_uri_upload', \$path->filename );

    $pack_multipart->( 'pause99_add_uri_httpupload', P->file->read_bin($path), $path->filename );

    $pack_multipart->( 'pause99_add_uri_uri', \q[] );

    $pack_multipart->( 'SUBMIT_pause99_add_uri_httpupload', \q[ Upload this file from my disk ] );

    $body .= q[--] . $boundary . q[--] . $CRLF . $CRLF;

    my $status;

    my $reason;

    P->ua->post(
        'https://pause.perl.org/pause/authenquery',
        headers => {
            AUTHORIZATION => 'Basic ' . P->data->to_b64_url( $username . q[:] . $password ) . q[==],
            CONTENT_TYPE  => qq[multipart/form-data; boundary=$boundary],
        },
        body      => \$body,
        blocking  => 1,
        on_finish => sub ($res) {
            $status = $res->status;

            $reason = $res->reason;

            return;
        }
    );

    return $status, $reason;
}

__PACKAGE__->meta->make_immutable;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::Plugin::Pcore::UploadToCPAN

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
