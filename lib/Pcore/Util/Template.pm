package Pcore::Util::Template;

use Pcore qw[-class];
use Text::Xslate qw[];

has _renderer => ( is => 'ro', isa => InstanceOf ['Text::Xslate'], required => 1 );
has _string_tmpl => ( is => 'ro', isa => HashRef, required => 1 );

# cache => 0 - don't use cache at all
#
# cache => 1:
# - file tmpl rebuilded and cached every time if original tmpl timestamp was changed, timestamp will checked on every render call;
# - string tmpl rebuilded and cached at first render call if not cached yet or cached tmpl has different check sum;
#
# cache => 2:
# - file tmpl builded and cached at first use only if not cached previously;
# - string tmpl same as cache => 1;
sub NEW ( $self, %args ) {
    my $string_tmpl_cache = {};

    my $path = [$string_tmpl_cache];    # virtual path

    my %path_index;

    if ( $PROC->{TMPL_DIR} ) {
        push $path->@*, $PROC->{TMPL_DIR};    # proc tmpl dir

        $path_index{ $PROC->{TMPL_DIR} } = 1;
    }

    if ( $DIST->{TMPL_DIR} && !exists $path_index{ $DIST->{TMPL_DIR} } ) {
        push $path->@*, $DIST->{TMPL_DIR};    # dist tmpl dir

        $path_index{ $DIST->{TMPL_DIR} } = 1;
    }

    if ( $P->{TMPL_DIR} && !exists $path_index{ $P->{TMPL_DIR} } ) {
        push $path->@*, $P->{TMPL_DIR};       # pcore tmpl dir
    }

    my $args_def = {
        path        => $path,
        cache       => 1,
        cache_dir   => $PROC->{TEMP_DIR} . '.xslate',
        input_layer => q[:encoding(UTF-8)],
        type        => 'html',                              # html, text}
        syntax      => 'Kolon',                             # Kolon, TTerse
        module      => ['Text::Xslate::Bridge::TT2Like'],
        function    => {
            i18n => sub {
                return i18n( \@_ );
            },
        },
    };

    return __PACKAGE__->new( { _renderer => Text::Xslate->new( P->hash->merge( $args_def, \%args )->%* ), _string_tmpl => $string_tmpl_cache } );
}

sub cache_string_tmpl ( $self, %args ) {
    for my $name ( keys %args ) {
        $self->_string_tmpl->{$name} = $args{$name}->$*;

        $self->reload_tmpl($name);
    }

    return;
}

sub reload_tmpl ( $self, @args ) {
    for (@args) {
        $self->_renderer->load_file($_);
    }

    return;
}

sub render ( $self, $tmpl, $params = undef ) {
    if ( ref $tmpl eq 'SCALAR' ) {
        return \$self->_renderer->render_string( $tmpl->$*, $params );
    }
    else {
        return \$self->_renderer->render( $tmpl, $params );
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 56                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
OLD VARS AND FILTERS, maybe needed to be reimplemented:

VARIABLES    => {
    ENV     => \%ENV,
    UUID    => sub { return P->uuid->str },
    TO_JSON => sub { return P->data->encode(@_) },
    TO_XML  => sub {
        my $data = shift;
        my $args = shift;

        return P->data->to_xml($data, $args>%*);
    },
},
FILTERS => {
    b64                     => sub { return P->data->to_b64(@_) },
    b64_url                 => sub { return P->data->to_b64_url(@_) },
    hex                        => sub { return P->text->encode_hex(@_) },
    html                       => sub { return P->text->encode_html(@_) },
    html_attr                  => sub { return P->text->encode_html_attr(@_) },
    js_string                  => sub { return P->text->encode_js_string(@_) },
    uri                        => sub { return P->data->to_uri(@_) },                    # same as javascript encodeURIComponent function, used to encode dataurl or any other binary data as javascript string
    strftime_to_jquery_pattern => sub { return P->text->encode_strftime_jquery(@_) },
},
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Template - Text::Xslate wrapper

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
