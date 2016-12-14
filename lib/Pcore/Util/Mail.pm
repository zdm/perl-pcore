package Pcore::Util::Mail;

use Pcore;
use Pcore::Util::Text qw[decode_utf8 encode_utf8];
use Net::SMTP;
use Mail::IMAPClient qw[];

sub send_mail (@) {
    my %args = (
        host         => undef,
        port         => undef,
        username     => undef,
        password     => undef,
        ssl          => undef,                           # undef, ssl, starttls
        debug        => 0,
        content_type => 'text/plain; charset="UTF-8"',
        from         => q[],
        reply_to     => q[],
        @_,
    );

    my $h = Net::SMTP->new(
        Host  => $args{host},
        Port  => $args{port},
        SSL   => $args{ssl},
        Debug => $args{debug},
    ) or die 'Could not connect to mail server ' . $args{host};

    $h->auth( $args{username}, $args{password} ) or die 'SMTP authentication failed for username ' . $args{username};

    encode_utf8 $args{subject};

    encode_utf8 $args{body};

    # create arbitrary boundary text used to seperate different parts of the message\n
    my ( $bi, @bchrs );
    my $boundary = q[];
    for my $bn ( 48 .. 57, 65 .. 90, 97 .. 122 ) {
        $bchrs[ $bi++ ] = chr $bn;
    }
    for my $bn ( 0 .. 20 ) {
        $boundary .= $bchrs[ rand $bi ];
    }

    $h->mail("$args{from}$CRLF");

    if ( $args{to} ) {
        $args{to} = [ $args{to} ] if ref $args{to} ne 'ARRAY';

        $h->to( $args{to}->@* );
    }

    if ( $args{cc} ) {
        $args{cc} = [ $args{cc} ] if ref $args{cc} ne 'ARRAY';

        $h->cc( $args{cc}->@* );
    }

    if ( $args{bcc} ) {
        $args{bcc} = [ $args{bcc} ] if ref $args{bcc} ne 'ARRAY';

        $h->bcc( $args{bcc}->@* );
    }

    $h->data();
    $h->datasend("Reply-To: $args{reply_to}$CRLF") if $args{reply_to};
    $h->datasend("From: $args{from}$CRLF");
    $h->datasend("To: @{[ join q[, ], $args{to}->@* ]}$CRLF");
    $h->datasend("Subject: $args{subject}$CRLF");

    $h->datasend("MIME-Version: 1.0$CRLF");
    $h->datasend("Content-Type: multipart/mixed; BOUNDARY=\"$boundary\"$CRLF");

    $h->datasend("$CRLF--$boundary$CRLF");
    $h->datasend("Content-Type: $args{content_type}$CRLF");
    $h->datasend("$CRLF");
    $h->datasend("$args{body}$CRLF$CRLF");

    # send attachments
    if ( $args{attachments} ) {
        if ( ref $args{attachments} eq 'HASH' ) {
            my $path = $args{attachments}->{path};
            my $name = $args{attachments}->{name} || q[];
            _send_attachment( $h, $boundary, $path, $name );
        }
        elsif ( ref $args{attachments} eq 'ARRAY' ) {
            for my $item ( @{ $args{attachments} } ) {
                if ( ref $item eq 'HASH' ) {
                    my $path = $item->{path};
                    my $name = $item->{name} || q[];
                    _send_attachment( $h, $boundary, $path, $name );
                }
                else {
                    _send_attachment( $h, $boundary, $item );
                }
            }
        }
        else {
            _send_attachment( $h, $boundary, $args{attachments} );
        }
    }

    $h->datasend("$CRLF--$boundary--$CRLF");
    $h->datasend("$CRLF");

    $h->dataend;

    $h->quit;

    return;
}

sub _send_attachment {
    my $h        = shift;
    my $boundary = shift;
    my $file     = shift;
    my $filename = shift || q[];

    die qq[Unable to find attachment file $file] unless -f $file;

    my $path = P->path($file);

    my $data = P->file->read_bin($path);

    my $mimetype = $path->mime_type;
    $filename = $path->filename unless $filename;
    encode_utf8 $filename;

    if ($data) {
        $h->datasend("--$boundary$CRLF");
        $h->datasend("Content-Type: $mimetype; name=\"$filename\"$CRLF");
        $h->datasend("Content-Transfer-Encoding: base64$CRLF");
        $h->datasend("Content-Disposition: attachment; =filename=\"$filename\"$CRLF$CRLF");
        $h->datasend( P->data->to_b64( ${$data} ) );
        $h->datasend("--$boundary$CRLF");
    }

    return;
}

sub get_mail {
    my %args = (
        gmail           => 0,
        host            => undef,
        port            => undef,
        ssl             => 1,
        login           => undef,
        password        => undef,
        folders         => undef,
        search          => { unseen => \1 },    # unseen => \1, to => user@domain,
        found_action    => q[],                 # 'delete_message', what to do with founded messages, by default message mark as read and moved to "all mail" folder
        retries         => 1,
        retries_timeout => 3,
        @_,
    );

    if ( $args{gmail} ) {
        P->hash->merge(
            \%args,
            {   host => 'imap.gmail.com',
                port => 993,
                ssl  => 1
            }
        );
        $args{folders} = [ '[Gmail]/All Mail', '[Gmail]/Spam' ] unless $args{folders};
    }
    else {
        $args{folders} = ['INBOX'] unless $args{folders};
    }

    my $imap = Mail::IMAPClient->new(
        Server   => $args{host},
        Port     => $args{port},
        Ssl      => $args{ssl},
        User     => $args{login},
        Password => $args{password},
    ) or die 'IMAP connections error';
    die 'IMAP connection error' unless $imap->IsAuthenticated;

    my @search_string;

    for my $token ( keys $args{search}->%* ) {
        my $res;

        if ( ref $args{search}->{$token} ) {
            $res = $args{search}->{$token}->$* == 1 ? uc $token : undef;
        }
        elsif ( $args{search}->{$token} ) {
            $res = uc($token) . q[ ] . $imap->Quote( $args{search}->{$token} );
        }

        push @search_string, $res if $res;
    }
    my $search_string = join q[ ], @search_string;

  REDO_SEARCH:
    P->log->sendlog( 'IMAP', 'IMAP search: ' . $search_string );

    my $messages = [];

    for my $folder ( @{ $args{folders} } ) {
        P->log->sendlog( 'IMAP', 'IMAP search in folder: ' . $folder );

        $imap->select($folder);

        if ( my $res = $imap->search($search_string) ) {
            if ( @{$res} ) {
                P->log->sendlog( 'IMAP', 'IMAP found: ' . $res->@* );

                push $messages->@*, _get_messages( $imap, $folder, $res, $args{found_action} )->@*;
            }
        }
    }
    if ( @{$messages} ) {
        P->log->sendlog( 'IMAP', 'IMAP total found: ' . $messages->@* );

        $imap->disconnect;

        return $messages;
    }

    if ( $args{retries} && --$args{retries} ) {
        P->log->sendlog( 'IMAP', 'IMAP sleep: ' . $args{retries_timeout} );

        sleep $args{retries_timeout};

        $imap->disconnect;

        $imap->reconnect;

        P->log->sendlog( 'IMAP', 'IMAP run next search iteration: ' . $args{retries} );

        goto REDO_SEARCH;
    }

    P->log->sendlog( 'IMAP', 'IMAP nothing found' );

    $imap->disconnect;

    return;
}

sub _get_messages {
    my $imap         = shift;
    my $folder       = shift;
    my $messages     = shift;
    my $found_action = shift;

    my $bodies = [];
    for my $msg ( @{$messages} ) {
        my $body = $imap->body_string($msg);
        my $content_type = $imap->get_header( $msg, 'Content-Type' );
        if ( $content_type =~ /charset="(.+?)"/sm ) {
            decode_utf8( $body, encoding => $1 );
        }
        push $bodies->@*, $body;
    }
    if ($found_action) {
        P->log->sendlog( 'IMAP', 'IMAP apply found action: ' . $found_action );

        my $method = $found_action;

        my $res = $imap->$method($messages);

        P->log->sendlog( 'IMAP', 'IMAP messages, affected by action: ' . $res );

        $imap->expunge($folder);
    }
    return $bodies;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 8                    | Subroutines::ProhibitExcessComplexity - Subroutine "send_mail" with high complexity score (21)                 |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=head1

=over

=item * type, tls, ssl, ''

=item * host

=item * port

=item * user

=item * password

=item * from

=item * to, several emails allowed, splitted by , or ;

=item * reply_to

=item * subject

=item * body

=item * content_type, default: text/plain; charset="UTF-8"

=item * attachments, [], {}, string - path to file

=back

=head1

=over

=item * login

=item * password

=item * search

=item * found_action, IMAP method to perform on founded messages. Can be undef, "delete_message", "seen" or somethig else.

=item * retries

=item * retries_timeout, default 3 seconds

=back

=cut
