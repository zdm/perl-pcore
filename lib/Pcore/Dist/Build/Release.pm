package Pcore::Dist::Build::Release;

use Pcore qw[-class];
use Pod::Markdown;
use CPAN::Meta;
use Module::Metadata;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has major  => ( is => 'ro', isa => Bool, default => 0 );
has minor  => ( is => 'ro', isa => Bool, default => 0 );
has bugfix => ( is => 'ro', isa => Bool, default => 0 );

no Pcore;

sub run ($self) {
    if ( $self->dist->cfg->{dist}->{cpan} && !$self->dist->global_cfg || ( !$self->dist->global_cfg->{PAUSE}->{username} || !$self->dist->global_cfg->{PAUSE}->{password} ) ) {
        say 'You need to specify PAUSE credentials';

        return;
    }

    if ( !$self->dist->scm ) {
        say 'SCM is required';

        return;
    }

    my $scm = $self->dist->scm->server;

    # check for uncommited changes
    if ( $scm->cmd(qw[status -mard])->%* ) {
        say 'Working copy has uncommited changes. Release is impossible.';

        return;
    }

    # run tests
    return if !$self->dist->build->test( author => 1, release => 1 );

    # show cur and new versions, take confirmation
    my $cur_ver = $self->dist->version;

    # increment version
    my @parts = $cur_ver->{version}->@*;

    $parts[0]++ if $self->major;
    $parts[1]++ if $self->minor;
    $parts[2]++ if $self->bugfix;

    my $new_ver = version->parse( 'v' . join q[.], @parts );

    if ( $cur_ver eq $new_ver ) {
        say 'Versions are equal. Release is impossible.';

        return;
    }

    say 'Curent version is: ' . $cur_ver;
    say 'New version will be: ' . $new_ver;

    return if P->term->prompt( 'Correct?', [qw[yes no]], enter => 1 ) ne 'yes';

    # update release version in the main_module
    my $main_module = P->file->read_bin( $self->dist->main_module_path );

    unless ( $main_module->$* =~ s[^(\s*package\s+\w[\w\:\']*\s+)v?[\d._]+(\s*;)][$1$new_ver$2]sm ) {
        say 'Error updating version';

        return;
    }

    P->file->write_bin( $self->dist->main_module_path, $main_module );

    # update working copy
    $self->dist->build->update;

    # commit
    $scm->cmd( 'commit', qq[-m"stable $new_ver"] );

    $scm->cmd( 'tag', '-f', 'stable', $new_ver );

    # upload to the CPAN if this is the CPAN distribution, prompt before upload
    $self->_upload_to_cpan if $self->dist->cfg->{dist}->{cpan};

    return 1;
}

sub _upload_to_cpan ($self) {
    my $tgz = $self->dist->build->tgz;

  REDO:
    my ( $status, $reason ) = $self->_upload( $self->dist->global_cfg->{PAUSE}->{username}, $self->dist->global_cfg->{PAUSE}->{password}, $tgz );

    if ( $status == 200 ) {
        say qq[Upload to CPAN status: $reason];

        unlink $tgz or 1;
    }
    else {
        say qq[Upload to CPAN status: $status, Reason: $reason];

        goto REDO if P->term->prompt( 'Retry?', [qw[yes no]], enter => 1 );

        say qq[Upload to CPAN failed. You should upload manually: "$tgz"];
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 32                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Release

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
