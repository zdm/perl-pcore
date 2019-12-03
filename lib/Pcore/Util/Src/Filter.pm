package Pcore::Util::Src::Filter;

use Pcore -role, -res, -const;

has data      => ( required => 1 );
has has_kolon => ( is       => 'lazy', init_arg => undef );

sub src_cfg ($self) { return Pcore::Util::Src::cfg() }

sub dist_cfg ($self) { return {} }

sub decompress ($self) { return res 200 }

sub compress ($self) { return res 200 }

sub obfuscate ($self) { return res 200 }

sub _build_has_kolon ($self) {
    return 1 if $self->{data} =~ /<: /sm;

    return 1 if $self->{data} =~ /^: /sm;

    return 0;
}

sub update_log ( $self, $log ) {return}

# TODO remove temporary filename from log
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

        # parse stderr
        if ( $proc->{stderr}->$* ) {
            for my $line ( split /\n/sm, $proc->{stderr}->$* ) {
                if ( $line =~ s/\A\[(.+?)\]\s//sm ) {
                    if    ( $1 eq 'error' ) { $has_errors++ }
                    elsif ( $1 eq 'warn' )  { $has_warnings++ }
                }

                push @log, $line;
            }

        }

        # unable to run prettier
        return res [ 500, $log[0] || $proc->{reason} ] if $proc->{exit_code} == 1;

        # prettier found erros in content
        $self->update_log( join "\n", @log );

        return res $has_errors ? 400 : 201;
    }
}

# TODO defined severity correctly
# TODO --fix option ???
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
    return res [ 500, $proc->{stderr}->$* || $proc->{reason} ] if !$proc;

    my $eslint_log = P->data->from_json( $proc->{stdout} );

    # eslint reported no violations
    return res 200 if !$eslint_log->[0] || !$eslint_log->[0]->{messages} || !$eslint_log->[0]->{messages}->@*;

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

        # TODO
        if ( $msg->{severity} >= 2 ) {
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
