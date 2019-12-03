package Pcore::Util::Src::Filter::js;

use Pcore -class, -res;
use Pcore::Util::Text qw[rcut_all encode_utf8];

with qw[Pcore::Util::Src::Filter];

has lint => 1;

sub decompress ( $self ) {
    my $res = $self->filter_prettier('--parser=babel');

    return $res if !$res;

    $res = $self->filter_eslint if $self->{lint};

    return $res;
}

sub compress ($self) {
    my $options = $self->dist_cfg->{terser_compress} || $self->src_cfg->{terser_compress};

    return $self->filter_terser( $options->@* );
}

sub obfuscate ($self) {
    my $options = $self->dist_cfg->{terser_obfuscate} || $self->src_cfg->{terser_obfuscate};

    return $self->filter_terser( $options->@* );
}

sub update_log ( $self, $log = undef ) {

    # clear log
    $self->{data} =~ s[// -----SOURCE FILTER LOG BEGIN-----.*-----SOURCE FILTER LOG END-----][]sm;

    rcut_all $self->{data};

    # insert log
    if ($log) {
        encode_utf8 $log;

        $self->{data} .= qq[\n// -----SOURCE FILTER LOG BEGIN-----\n//\n];

        $self->{data} .= $log =~ s[^][// ]smgr;

        $self->{data} .= qq[\n//\n// -----SOURCE FILTER LOG END-----];
    }

    return;
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

# TODO
sub filter_terser ( $self, @options ) {
    my $temp = P->file1->tempfile( suffix => 'js' );

    P->file->write_bin( $temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'terser', $temp, @options ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    $self->{data} = $proc->{stdout}->$*;

    return res 200;
}

sub filer_packer ( $self, $obfuscate = undef ) {
    require JavaScript::Packer;

    state $packer = JavaScript::Packer->init;

    $packer->minify( \$self->{data}, { compress => $obfuscate ? 'obfuscate' : 'clean' } );

    return res 200;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 35                   | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter::js

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
