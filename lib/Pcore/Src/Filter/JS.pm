package Pcore::Src::Filter::JS;

use Pcore qw[-class];

with qw[Pcore::Src::Filter];

sub decompress ( $self, % ) {
    my %args = (
        js_hint => 1,
        @_[ 1 .. $#_ ],
    );

    return 0 if !length $self->buffer->$*;

    return 0 if $self->has_kolon;

    my $js_beautify_args = $self->dist_cfg->{JS_BEAUTIFY} || $self->src_cfg->{JS_BEAUTIFY};

    if ($MSWIN) {
        my $temp = P->file->tempfile;

        syswrite $temp, $self->buffer->$* or die;

        require Win32::Process;

        Win32::Process::Create( my $process_obj, $ENV{COMSPEC}, qq[/C js-beautify $js_beautify_args --replace "$temp"], 0, Win32::Process::CREATE_NO_WINDOW(), q[.] ) || die;

        $process_obj->Wait( Win32::Process::INFINITE() );

        $self->buffer->$* = P->file->read_bin( $temp->path )->$*;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
    }

    my $log;

    my $jshint_output;

    if ( $args{js_hint} && length $self->buffer->$* ) {
        $jshint_output = $self->run_js_hint;

        if ( $jshint_output->{data}->@* ) {
            for my $rec ( $jshint_output->{data}->@* ) {
                $log .= qq[ * $rec->{code}, line: $rec->{line}, col: $rec->{col}, $rec->{msg}\n];
            }
        }
    }

    $self->_append_log($log);

    if ( $args{js_hint} ) {
        if ( $jshint_output->{has_errors} ) {
            return 5;
        }
        elsif ( $jshint_output->{has_warns} ) {
            return 1;
        }
    }

    return 0;
}

sub compress ($self) {
    try {
        require JavaScript::Packer;

        $self->buffer->$* = JavaScript::Packer->init->minify( $self->buffer, { compress => 'clean' } );    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
    };

    return 0;
}

sub obfuscate ($self) {
    try {
        require JavaScript::Packer;

        $self->buffer->$* = JavaScript::Packer->init->minify( $self->buffer, { compress => 'obfuscate' } );    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
    };

    return 0;
}

sub cut_log ($self) {
    $self->buffer->$* =~ s[/[*] -----SOURCE FILTER LOG BEGIN-----.*-----SOURCE FILTER LOG END----- [*]/\n*][]sm;

    P->text->rcut_all( $self->buffer->$* );

    return;
}

sub _append_log ( $self, $log ) {
    $self->cut_log;

    if ($log) {
        P->text->encode_utf8($log);

        $self->buffer->$* .= qq[\n/* -----SOURCE FILTER LOG BEGIN-----\n *\n];

        $self->buffer->$* .= $log;

        $self->buffer->$* .= qq[ *\n * -----SOURCE FILTER LOG END----- */];
    }

    return;
}

sub run_js_hint ($self) {
    my $jshint_output = [];

    my $js_hint_args = $self->dist_cfg->{JS_HINT} || $self->src_cfg->{JS_HINT};

    if ($MSWIN) {
        my $in_temp = P->file->tempfile;

        syswrite $in_temp, $self->buffer->$* or die;

        my $out_temp = $PROC->{TEMP_DIR} . 'tmp-jshint-' . int rand 99_999;

        require Win32::Process;

        Win32::Process::Create( my $process_obj, $ENV{COMSPEC}, qq[/C jshint $js_hint_args "$in_temp"> "$out_temp"], 0, Win32::Process::CREATE_NO_WINDOW(), q[.] ) || die;

        $process_obj->Wait( Win32::Process::INFINITE() );

        $jshint_output = P->file->read_lines($out_temp);

        unlink $out_temp;    ## no critic qw[InputOutput::RequireCheckedSyscalls]
    }

    my $res = {
        has_errors => 0,
        has_warns  => 0,
        data       => [],
    };

    for my $line ( $jshint_output->@* ) {
        next unless $line =~ s/^.+?: line/line/smg;

        my $descriptor = { raw => $line };

        ( $descriptor->{line}, $descriptor->{col}, $descriptor->{msg}, $descriptor->{code} ) = $line =~ /line (\d+), col (\d+|undefined), (.+)? [(]([WE]\d+)[)]/sm;

        if ( index( $descriptor->{code}, 'E', 0 ) == 0 ) {
            $descriptor->{is_error} = 1;

            $res->{has_errors}++;
        }
        else {
            $descriptor->{is_warn} = 1;

            $res->{has_warns}++;
        }

        push $res->{data}->@*, $descriptor;
    }

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 82                   │ RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Filter::JS

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
