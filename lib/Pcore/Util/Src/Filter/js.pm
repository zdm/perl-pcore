package Pcore::Util::Src::Filter::js;

use Pcore -class, -res;
use Pcore::Util::Text qw[rcut_all encode_utf8];

with qw[Pcore::Util::Src::Filter];

has eslint => 1;

# my $JS_PACKER;

sub decompress ($self) {
    my $options = $self->dist_cfg->{prettier} || $self->src_cfg->{prettier};

    my $in_temp = P->file1->tempfile;
    P->file->write_bin( $in_temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'prettier', $in_temp, $options->@*, '--parser=babel' ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    $self->{data}->$* = $proc->{stdout}->$*;

    my $log;

    my $eslint;

    if ( $self->{eslint} && length $self->{data}->$* ) {

        $eslint = $self->_run_eslint;

        for my $msg ( sort { $a->{severity} <=> $b->{severity} } $eslint->{messages}->@* ) {
            $log .= sprintf " * %5d %8d %8d %20s %s\n", $msg->{severity}, $msg->{line}, $msg->{column}, $msg->{ruleId}, $msg->{message};
        }
    }

    $self->_append_log($log);

    if ($eslint) {
        if ( $eslint->{has_errors} ) {
            return res [ 500, 'Error, eslint' ];
        }
        elsif ( $eslint->{has_warns} ) {
            return res [ 201, 'Warning, eslint' ];
        }
    }

    return res 200;
}

sub compress ($self) {

    # require JavaScript::Packer;

    # $JS_PACKER //= JavaScript::Packer->init;

    # $JS_PACKER->minify( $self->{data}, { compress => 'clean' } );

    my $options = $self->dist_cfg->{terser_compress} || $self->src_cfg->{terser_compress};

    my $in_temp = P->file1->tempfile( suffix => 'js' );
    P->file->write_bin( $in_temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'terser', $in_temp, $options->@* ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    $self->{data}->$* = $proc->{stdout}->$*;

    return res 200;
}

sub obfuscate ($self) {

    # require JavaScript::Packer;

    # $JS_PACKER //= JavaScript::Packer->init;

    # $JS_PACKER->minify( $self->{data}, { compress => 'obfuscate' } );

    my $options = $self->dist_cfg->{terser_obfuscate} || $self->src_cfg->{terser_obfuscate};

    my $in_temp = P->file1->tempfile( suffix => 'js' );
    P->file->write_bin( $in_temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'terser', $in_temp, $options->@* ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    $self->{data}->$* = $proc->{stdout}->$*;

    return res 200;
}

sub _append_log ( $self, $log ) {
    $self->_cut_log;

    if ($log) {
        encode_utf8 $log;

        $self->{data}->$* .= qq[\n/* -----SOURCE FILTER LOG BEGIN-----\n *\n];

        $self->{data}->$* .= $log;

        $self->{data}->$* .= qq[ *\n * -----SOURCE FILTER LOG END----- */];
    }

    return;
}

sub _cut_log ($self) {
    $self->{data}->$* =~ s[/[*] -----SOURCE FILTER LOG BEGIN-----.*-----SOURCE FILTER LOG END----- [*]/\n*][]sm;

    rcut_all $self->{data}->$*;

    return;
}

sub _run_eslint ($self) {
    state $config = $ENV->{share}->get('/Pcore/data/eslintrc.yaml');

    my $in_temp = P->file1->tempfile;
    P->file->write_bin( $in_temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'eslint', $in_temp, '--format=json', "--config=$config", '--fix' ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    my $data = P->data->from_json( $proc->{stdout} );

    return $data->[0];
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 121                  | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
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
