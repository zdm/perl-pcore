package Pcore::Util::Mail;

use Pcore;
use Net::SMTPS;
use Mail::IMAPClient qw[];

sub send_mail {
    my $self = shift;
    my %args = (
        host         => undef,
        port         => undef,
        username     => undef,
        password     => undef,
        layer        => undef,                           # undef, ssl, starttls
        debug        => 0,
        content_type => 'text/plain; charset="UTF-8"',
        from         => q[],
        reply_to     => q[],
        @_,
    );

    my $h = Net::SMTPS->new(
        Host  => $args{host},
        Port  => $args{port},
        doSSL => $args{layer},
        Debug => $args{debug},
    ) or die 'Could not connect to mail server ' . $args{host};

    $h->auth( $args{username}, $args{password} ) or die 'SMTP authentication failed for username ' . $args{username};

    P->text->encode_utf8( $args{subject} );

    P->text->encode_utf8( $args{body} );

    # Create arbitrary boundary text used to seperate
    # different parts of the message\n
    my ( $bi, @bchrs );
    my $boundary = q[];
    for my $bn ( 48 .. 57, 65 .. 90, 97 .. 122 ) {
        $bchrs[ $bi++ ] = chr $bn;
    }
    for my $bn ( 0 .. 20 ) {
        $boundary .= $bchrs[ rand $bi ];
    }

    $h->mail("$args{from}$CRLF");

    my @recepients = split /[,;]/sm, $args{to};
    foreach my $recp (@recepients) {
        $h->to("$recp$CRLF");
    }

    $h->data();
    $h->datasend("Reply-To: $args{reply_to}$CRLF") if $args{reply_to};
    $h->datasend("From: $args{from}$CRLF");
    $h->datasend("To: $args{to}$CRLF");
    $h->datasend("Subject: $args{subject}$CRLF");

    $h->datasend("MIME-Version: 1.0$CRLF");
    $h->datasend("Content-Type: multipart/mixed; BOUNDARY=\"$boundary\"$CRLF");

    $h->datasend("$CRLF--$boundary$CRLF");
    $h->datasend("Content-Type: $args{content_type}$CRLF");
    $h->datasend("$CRLF");
    $h->datasend("$args{body}$CRLF$CRLF");

    # Send attachments
    if ( $args{attachments} ) {
        if ( ref $args{attachments} eq 'HASH' ) {
            my $path = $args{attachments}->{path};
            my $name = $args{attachments}->{name} || q[];
            $self->_send_attachment( $h, $boundary, $path, $name );
        }
        elsif ( ref $args{attachments} eq 'ARRAY' ) {
            for my $item ( @{ $args{attachments} } ) {
                if ( ref $item eq 'HASH' ) {
                    my $path = $item->{path};
                    my $name = $item->{name} || q[];
                    $self->_send_attachment( $h, $boundary, $path, $name );
                }
                else {
                    $self->_send_attachment( $h, $boundary, $item );
                }
            }
        }
        else {
            $self->_send_attachment( $h, $boundary, $args{attachments} );
        }
    }

    $h->datasend("$CRLF--$boundary--$CRLF");
    $h->datasend("$CRLF");

    $h->dataend;
    $h->quit;

    return;
}

sub _send_attachment {
    my $self     = shift;
    my $h        = shift;
    my $boundary = shift;
    my $file     = shift;
    my $filename = shift || q[];

    die qq[Unable to find attachment file $file] unless -f $file;

    my $path = P->file->path($file);

    my $data = P->file->read_bin($path);

    my $mimetype = $path->mime_type;
    $filename = $path->filename unless $filename;
    P->text->encode_utf8($filename);

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
    my $self = shift;
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

    for my $token ( keys $args{search} ) {
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
    debug( 'IMAP search: ' . $search_string );

    my $messages = [];

    for my $folder ( @{ $args{folders} } ) {
        debug( 'IMAP search in folder: ' . $folder );
        $imap->select($folder);
        if ( my $res = $imap->search($search_string) ) {
            if ( @{$res} ) {
                debug( 'IMAP found: ' . scalar @{$res} );
                push @{$messages}, @{ $self->_get_messages( $imap, $folder, $res, $args{found_action} ) };
            }
        }
    }
    if ( @{$messages} ) {
        debug( 'IMAP total found: ' . scalar @{$messages} );
        $imap->disconnect;
        return $messages;
    }

    if ( $args{retries} && --$args{retries} ) {
        debug( 'IMAP sleep: ' . $args{retries_timeout} );
        sleep $args{retries_timeout};
        $imap->disconnect;
        $imap->reconnect;
        debug( 'IMAP run next search iteration: ' . $args{retries} );
        goto REDO_SEARCH;
    }

    debug('IMAP nothing found');
    $imap->disconnect;
    return;
}

sub _get_messages {
    my $self         = shift;
    my $imap         = shift;
    my $folder       = shift;
    my $messages     = shift;
    my $found_action = shift;

    my $bodies = [];
    for my $msg ( @{$messages} ) {
        my $body = $imap->body_string($msg);
        my $content_type = $imap->get_header( $msg, 'Content-Type' );
        if ( $content_type =~ /charset="(.+?)"/sm ) {
            P->text->decode( $body, encoding => $1 );
        }
        push @{$bodies}, $body;
    }
    if ($found_action) {
        debug( 'IMAP apply found action: ' . $found_action );
        my $method = $found_action;
        my $res    = $imap->$method($messages);
        debug( 'IMAP messages, affected by action: ' . $res );
        $imap->expunge($folder);
    }
    return $bodies;
}

1;
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
