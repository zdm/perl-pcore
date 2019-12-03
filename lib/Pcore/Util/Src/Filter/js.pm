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

sub filer_js_packer ( $self, $obfuscate = undef ) {
    state $packer = {
        require JavaScript::Packer;

        JavaScript::Packer->init;
    };

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
