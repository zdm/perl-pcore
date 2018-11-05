package Pcore::Src1::html;

use Pcore -class, -res;
use Pcore::Util::Text qw[trim];
use Pcore::Src1::js;
use Pcore::Src1::css;

with qw[Pcore::Src1::Filter];

sub decompress ($self) {
    return res 200 if !length $self->{data}->$*;

    return res 200 if $self->has_kolon;

    my $temp = P->file1->tempfile;

    P->file->write_bin( $temp, $self->{data} );

    my $proc = P->sys->run_proc( qq[html-beautify --indent-scripts separate --replace "$temp"], stdout => 1, stderr => 1, win32_create_no_window => 1 )->wait;

    $self->{data}->$* = P->file->read_bin($temp)->$*;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return res 200;
}

sub compress ($self) {
    return res 200 if !length $self->{data}->$*;

    return res 200 if $self->has_kolon;

    # compress js
    my @script = split m[(<script[^>]*>)(.*?)(</script[^>]*>)]smi, $self->{data}->$*;

    for my $i ( 0 .. $#script ) {
        if ( $script[$i] =~ m[\A</script]sm && $script[ $i - 1 ] ) {
            Pcore::Src1::js->new( { file => $self->{file}, data => \$script[ $i - 1 ] } )->compress;

            trim $script[ $i - 1 ];
        }
    }

    $self->{data}->$* = join '', @script;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    # compress css
    my @css = split m[(<style[^>]*>)(.*?)(</style[^>]*>)]smi, $self->{data}->$*;

    for my $i ( 0 .. $#css ) {
        if ( $css[$i] =~ m[\A</style]sm && $css[ $i - 1 ] ) {
            Pcore::Src1::css->new( { file => $self->{file}, data => \$css[ $i - 1 ] } )->compress;
        }
    }

    $self->{data}->$* = join '', @css;       ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    require HTML::Packer;

    eval { $self->{data}->$* = HTML::Packer->init->minify( $self->{data}, { remove_comments => 0, remove_newlines => 1, html5 => 1 } ) };    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return res 200;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 57                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 42, 53               | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src1::html

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
