package Pcore::Util::Src::Filter;

use Pcore -role, -res, -const;

has data      => ( required => 1 );
has has_kolon => ( is       => 'lazy', init_arg => undef );

around decompress => sub ( $orig, $self, $data, %args ) {
    $self = $self->new( %args, data => $data->$* );

    my $res = $self->$orig;

    $data->$* = $self->{data} if !$res->is_server_error;

    return $res;
};

around compress => sub ( $orig, $self, $data, %args ) {
    $self = $self->new( %args, data => $data->$* );

    my $res = $self->$orig;

    $data->$* = $self->{data} if !$res->is_server_error;

    return $res;
};

around obfuscate => sub ( $orig, $self, $data, %args ) {
    $self = $self->new( %args, data => $data->$* );

    my $res = $self->$orig;

    $data->$* = $self->{data} if !$res->is_server_error;

    return $res;
};

sub _build_has_kolon ($self) {
    return 1 if $self->{data} =~ /<: /sm;

    return 1 if $self->{data} =~ /^: /sm;

    return 0;
}

sub src_cfg ($self) { return Pcore::Util::Src::cfg() }

sub dist_cfg ($self) { return {} }

sub decompress ($self) { return res 200 }

sub compress ($self) { return res 200 }

sub obfuscate ($self) { return res 200 }

sub update_log ( $self, $log = undef ) {return}

sub filter_prettier ( $self, @options ) {
    my $dist_options = $self->dist_cfg->{prettier} || $self->src_cfg->{prettier};

    my $temp = P->file1->tempfile;
    P->file->write_bin( $temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'prettier', $temp, $dist_options->@*, @options, '--no-color', '--no-config', '--loglevel=error' ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    # ran without errors
    if ($proc) {
        $self->{data} = $proc->{stdout}->$*;

        $self->update_log;

        return res 200;
    }

    # run with errors
    else {

        my ( @log, $has_errors, $has_warnings );

        my $temp_filename = $temp->{filename};

        # parse stderr
        if ( $proc->{stderr}->$* ) {
            for my $line ( split /\n/sm, $proc->{stderr}->$* ) {
                if ( $line =~ s/\A\[(.+?)\]\s//sm ) {
                    if    ( $1 eq 'error' ) { $has_errors++ }
                    elsif ( $1 eq 'warn' )  { $has_warnings++ }
                }

                # remove temp filename from log
                $line =~ s[\A.+$temp_filename:\s][]sm;

                push @log, $line;
            }

        }

        # unable to run prettier
        return res [ 500, $log[0] || $proc->{reason} ] if $proc->{exit_code} == 1;

        # prettier found errors in content
        $self->update_log( join "\n", @log );

        return res $has_errors ? 400 : 201;
    }
}

sub filter_eslint ( $self, @options ) {
    state $config = $ENV->{share}->get('/Pcore/data/.eslintrc.yaml');

    my $temp = P->file1->tempfile;
    P->file->write_bin( $temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'eslint', $temp, "--config=$config", @options, '--format=json', '--fix' ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    # unable to run elsint
    if ( !$proc && !$proc->{stdout}->$* ) {
        my $reason;

        if ( $proc->{stderr}->$* ) {
            my @log = split /\n/sm, $proc->{stderr}->$*;

            $reason = $log[0];
        }

        return res [ 500, $reason || $proc->{reason} ];
    }

    my $eslint_log = P->data->from_json( $proc->{stdout} );

    $self->{data} = $eslint_log->[0]->{output} if $eslint_log->[0]->{output};

    # eslint reported no violations
    if ( !$eslint_log->[0]->{messages}->@* ) {
        $self->update_log;

        return res 200;
    }

    my ( $log, $has_warnings, $has_errors );

    # create table
    my $tbl = P->text->table(
        style => 'compact',
        color => 0,
        cols  => [
            severity => {
                title  => 'Sev.',
                width  => 6,
                align  => 1,
                valign => -1,
            },
            pos => {
                title       => 'Line:Col',
                width       => 15,
                title_align => -1,
                align       => -1,
                valign      => -1,
            },
            rule => {
                title       => 'Rule',
                width       => 20,
                title_align => -1,
                align       => -1,
                valign      => -1,
            },
            desc => {
                title       => 'Description',
                width       => 99,
                title_align => -1,
                align       => -1,
                valign      => -1,
            },
        ],
    );

    $log .= $tbl->render_header;

    my @items;

    for my $msg ( sort { $a->{severity} <=> $b->{severity} || $a->{line} <=> $b->{line} || $a->{column} <=> $b->{column} } $eslint_log->[0]->{messages}->@* ) {
        if ( $msg->{severity} == 1 ) {
            $has_warnings++;
        }
        else {
            $has_errors++;
        }

        push @items, [ $msg->{severity}, "$msg->{line}:$msg->{column}", $msg->{ruleId}, $msg->{message} ];
    }

    my $row_line = $tbl->render_row_line;

    $log .= join $row_line, map { $tbl->render_row($_) } @items;

    $log .= $tbl->finish;

    $self->update_log($log);

    my $status = do {
        if    ($has_errors)   {400}
        elsif ($has_warnings) {201}
        else                  {200}
    };

    return res $status;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
