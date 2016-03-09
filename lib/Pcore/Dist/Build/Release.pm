package Pcore::Dist::Build::Release;

use Pcore -class;
use Pcore::Util::Text qw[encode_utf8];
use Pod::Markdown;
use CPAN::Meta;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has major  => ( is => 'ro', isa => Bool, default => 0 );
has minor  => ( is => 'ro', isa => Bool, default => 0 );
has bugfix => ( is => 'ro', isa => Bool, default => 0 );

sub run ($self) {
    if ( $self->dist->cfg->{dist}->{cpan} && !$self->dist->build->user_cfg || ( !$self->dist->build->user_cfg->{PAUSE}->{username} || !$self->dist->build->user_cfg->{PAUSE}->{password} ) ) {
        say qq[You need to specify PAUSE credentials$LF];

        return;
    }

    if ( !$self->dist->scm ) {
        say qq[SCM is required$LF];

        return;
    }

    my $scm = $self->dist->scm->server;

    # check for uncommited changes
    if ( $scm->cmd(qw[status -mardu --subrepos])->%* ) {
        say qq[Working copy or subrepos has uncommited changes or unknown files. Release is impossible.$LF];

        return;
    }

    # release is impossible, if we are not on the "default" branch
    if ( $scm->cmd('branch')->{o}->[0] ne 'default' ) {
        say qq[SCM should be on the "default" branch. Release is impossible.$LF];

        return;
    }

    # check for resolved issues without milestone
    if ( my $resolved_issues = $self->dist->build->issues->get( resolved => 1 ) ) {
        say qq[Following issues are resolved and not closed:$LF];

        $self->dist->build->issues->print_issues($resolved_issues);

        say qq[${LF}Close or re-open this issues. Release is impossible.$LF];

        return;
    }

    # show current and new versions, take confirmation
    my $cur_ver = $self->dist->version;

    # check if v0.1.0 is already released
    if ( $cur_ver eq 'v0.1.0' ) {
        my $tags = { map { $_ => 1 } grep {$_} $scm->cmd(qw[tags -q])->{o}->@* };

        # v0.1.0 is not released yet
        $cur_ver = version->parse('v0.0.0') if !exists $tags->{'v0.1.0'};
    }

    # increment version
    my @parts = $cur_ver->{version}->@*;

    if ( $self->major ) {
        $parts[0]++;
        $parts[1] = 0;
        $parts[2] = 0;
    }
    elsif ( $self->minor ) {
        $parts[1]++;
        $parts[2] = 0;
    }
    elsif ( $self->bugfix ) {

        # bugfix is impossible for v0.0.0
        $parts[2]++ if $cur_ver ne 'v0.0.0';
    }

    my $new_ver = version->parse( 'v' . join q[.], @parts );

    if ( $cur_ver eq $new_ver ) {
        say qq[You forgot to specify release version. Release is impossible.$LF];

        return;
    }

    # working with issues tracker
    my $closed_issues = $self->dist->build->issues->get( closed => 1 );

    if ($closed_issues) {
        say qq[\nFollowing issues will be added to the release CHANGES file\n];

        $self->dist->build->issues->print_issues($closed_issues);
    }
    else {
        say qq[\nNo issues were closed since the last release];
    }

    say qq[${LF}Current version is: $cur_ver];
    say qq[New version will be: $new_ver$LF];

    return if P->term->prompt( qq[Continue release process?], [qw[yes no]], enter => 1 ) ne 'yes';

    say q[];

    # run tests
    return if !$self->dist->build->test( author => 1, release => 1 );

    say q[];

    # !!!WARNING!!! start release, next changes will be hard to revert

    # update release version in the main module
    unless ( $self->dist->module->content->$* =~ s[^(\s*package\s+\w[\w\:\']*\s+)v?[\d._]+(\s*;)][$1$new_ver$2]sm ) {
        say q[Error updating version];

        return;
    }

    P->file->write_bin( $self->dist->module->path, $self->dist->module->content );

    {
        my $cv = AE::cv;

        # create new version on issues tracker
        print q[Creating new version and milestone on issues tracker ... ];

        $cv->begin;

        $self->dist->build->issues->create_version(
            $new_ver,
            sub ($id) {
                die q[Error creating new version on issues tracker] if !$id;

                $cv->end;

                return;
            }
        );

        # create new milestone on issues tracker
        $cv->begin;

        $self->dist->build->issues->create_milestone(
            $new_ver,
            sub ($id) {
                die q[Error creating new milestone on issues tracker] if !$id;

                $cv->end;

                return;
            }
        );

        $cv->recv;

        say 'done';

        # get closed issues, set milestone for closed issues
        if ($closed_issues) {
            $cv = AE::cv;

            print q[Updating milestone for closed issues ... ];

            for my $issue ( $closed_issues->@* ) {
                $cv->begin;

                $issue->set_milestone(
                    $new_ver,
                    sub ($success) {
                        $cv->end;

                        return;
                    }
                );
            }

            $cv->recv;

            say 'done';
        }
    }

    # update working copy
    $self->dist->build->update;

    # update CHANGES file
    $self->_create_changes( $new_ver, $closed_issues );

    # generate wiki
    $self->dist->build->wiki->run if $self->dist->build->wiki;

    # add / remove files, possible generated by wiki command
    $scm->cmd( 'addremove', '--subrepos' );

    # commit
    $scm->cmd( 'commit', qq[-m"stable $new_ver"], '--subrepos' );

    $scm->cmd( 'tag', '-f', 'stable', $new_ver );

    print 'Pushing to the upstream repository ... ';
    $scm->cmd('push');
    say 'done';

    # upload to the CPAN if this is the CPAN distribution, prompt before upload
    $self->_upload_to_cpan if $self->dist->cfg->{dist}->{cpan};

    return 1;
}

sub _upload_to_cpan ($self) {
    print 'Creating .tgz ... ';

    my $tgz = $self->dist->build->tgz;

    say 'done';

  REDO:
    print 'Uploading to CPAN ... ';

    my ( $status, $reason ) = $self->_upload( $self->dist->build->user_cfg->{PAUSE}->{username}, $self->dist->build->user_cfg->{PAUSE}->{password}, $tgz );

    if ( $status == 200 ) {
        say $reason;

        unlink $tgz or 1;
    }
    else {
        say qq[$status $reason];

        goto REDO if P->term->prompt( 'Retry?', [qw[yes no]], enter => 1 );

        say qq[Upload to CPAN failed. You should upload manually: "$tgz"];
    }

    return;
}

sub _upload ( $self, $username, $password, $path ) {
    my $body;

    encode_utf8 $username;

    encode_utf8 $password;

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

    P->http->post(
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

sub _create_changes ( $self, $ver, $issues ) {
    state $init = !!require CPAN::Changes;

    my $changes_path = $self->dist->root . 'CHANGES';

    my $changes = -f $changes_path ? CPAN::Changes->load($changes_path) : CPAN::Changes->new;

    my $rel = CPAN::Changes::Release->new(
        version => $ver,
        date    => P->date->now_utc->to_w3cdtf,
    );

    if ($issues) {
        my $group = {};

        for my $issue ( sort { $b->priority_id <=> $a->priority_id } $issues->@* ) {
            push $group->{ $issue->{metadata}->{kind} }->@*, qq[[$issue->{priority}] $issue->{title} (@{[$issue->url]})];
        }

        for my $group_name ( keys $group->%* ) {
            $rel->add_changes( { group => uc $group_name }, $group->{$group_name}->@* );
        }
    }
    else {
        $rel->add_changes('No issues were closed since the last release');
    }

    $changes->add_release($rel);

    P->file->write_text( $changes_path, $changes->serialize );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 14                   │ Subroutines::ProhibitExcessComplexity - Subroutine "run" with high complexity score (27)                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 30, 331              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 106                  │ ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 15, 44, 47, 92, 97,  │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## │      │ 118, 134, 148, 225   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 327                  │ BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                │
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
