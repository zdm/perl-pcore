package Pcore::App::API::Upload;

use Pcore -role, -res;
use Pcore::Util::UUID qw[uuid_v4_str];

has upload_idle_timeout => 60;

has _uploads      => ( init_arg => undef );
has _upload_timer => ( init_arg => undef );

sub _upload ( $self, $req, $args, $on_start, $on_finish ) {

    # upload start
    if ( !$args->{id} ) {

        # generate upload id
        my $id = $args->{id} = uuid_v4_str;

        $args->{auth} = $req->{auth};

        my $res = $on_start->( $self, $args );

        # upload accepted
        if ($res) {

            # register upload
            $self->{_upload}->{$id} = $args;

            $args->{last_activity} = time;

            $self->_set_upload_timer($id);

            $req->( 200, $id );
        }

        # upload rejected
        else {
            $req->($res);
        }
    }

    # upload continue
    else {
        my $upload = $self->{_upload}->{ $args->{id} };

        # upload was not found
        return $req->( [ 400, q[Upload id is invalid or expired] ] ) if !$upload;

        my $chunk = P->data->from_b64( delete $args->{chunk} );

        $upload->{uploaded_size} += length $chunk;

        $upload->{tempfile} //= P->file1->tempfile;

        # calculate server hash
        if ( $upload->{hash} ) {
            $upload->{server_hash} //= P->digest->sha1_stream;

            $upload->{server_hash}->add($chunk);
        }

        P->file->append_bin( $upload->{tempfile}, \$chunk );

        # upload is not finished
        if ( $upload->{uploaded_size} < $upload->{size} ) {
            $args->{last_activity} = time;

            $req->(200);
        }

        # upload is finished
        elsif ( $upload->{uploaded_size} == $upload->{size} ) {
            $self->_remove_upload( $args->{id} );

            # compare hash
            if ( $upload->{hash} ) {
                $upload->{server_hash} = $upload->{server_hash}->hexdigest;

                # hash is invalid
                return $req->( [ 400, 'File hash is invalid' ] ) if $upload->{hash} ne $upload->{server_hash};
            }

            my $res = $on_finish->( $self, $upload );

            $req->($res);
        }

        # uploaded size is greater
        else {
            $self->_remove_upload( $args->{id} );

            $req->( [ 400, q[File size is invalid] ] );
        }
    }

    return;
}

sub _remove_upload ( $self, $upload_id ) {
    delete $self->{_uploads}->{$upload_id};

    delete $self->{_upload_timer}->{$upload_id};

    return;
}

sub _set_upload_timer ( $self, $upload_id ) {
    $self->{_upload_timer}->{$upload_id} = AE::timer $self->{upload_idle_timeout}, 0, sub {
        my $upload = $self->{_uploads}->{$upload_id};

        # upload is expired
        $self->_remove_upload($upload_id) if !$upload || $upload->{last_activity} + $self->{upload_idle_timeout} < time;

        return;
    };

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 11                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 11                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_upload' declared but not used      |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Upload

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
