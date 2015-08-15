package Pcore::Src::Filter::HTML;

use Pcore qw[-class];
use Pcore::Src::Filter::JS;
use Pcore::Src::Filter::CSS;

with qw[Pcore::Src::Filter];

sub decompress ($self) {
    return 0 if $self->has_kolon;

    my $html_beautify_args = $self->dist_cfg->{HTML_BEAUTIFY} || $self->src_cfg->{HTML_BEAUTIFY};

    if ($MSWIN) {
        my $temp = P->file->tempfile;

        syswrite $temp, $self->buffer->$* or die;

        require Win32::Process;

        Win32::Process::Create( my $process_obj, $ENV{COMSPEC}, qq[/C html-beautify $html_beautify_args --replace --file "$temp"], 0, Win32::Process::CREATE_NO_WINDOW(), q[.] ) || die;

        $process_obj->Wait( Win32::Process::INFINITE() );

        $self->buffer->$* = P->file->read_bin( $temp->filename )->$*;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
    }

    return 0;
}

sub compress ($self) {
    return 0 if $self->has_kolon;

    # compress js
    my @script = split m[(<script[^>]*>)(.*?)(</script[^>]*>)]smi, $self->buffer->$*;

    for my $i ( 0 .. $#script ) {
        if ( $script[$i] =~ m[\A</script]sm && $script[ $i - 1 ] ) {
            Pcore::Src::Filter::JS->new( { buffer => \$script[ $i - 1 ] } )->compress;

            P->text->trim( $script[ $i - 1 ] );
        }
    }

    $self->buffer->$* = join q[], @script;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    # compress css
    my @css = split m[(<style[^>]*>)(.*?)(</style[^>]*>)]smi, $self->buffer->$*;

    for my $i ( 0 .. $#css ) {
        if ( $css[$i] =~ m[\A</style]sm && $css[ $i - 1 ] ) {
            Pcore::Src::Filter::CSS->new( { buffer => \$css[ $i - 1 ] } )->compress;
        }
    }

    $self->buffer->$* = join q[], @css;       ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    my $html_packer_minify_args = $self->dist_cfg->{HTML_PACKER_MINIFY} || $self->src_cfg->{HTML_PACKER_MINIFY};

    try {
        require HTML::Packer;

        $self->buffer->$* = HTML::Packer->init->minify( $self->buffer, $html_packer_minify_args );    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
    };

    return 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Filter::HTML

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
