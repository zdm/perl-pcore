package Pcore::Util::Text;

use Pcore -export, [
    qw[
      cut
      cut_all
      decode_eol
      decode_html_entities
      decode_utf8
      encode_hex
      encode_html
      encode_html_attr
      encode_js_string
      encode_utf8
      escape_scalar
      expand_num
      format_num
      fullchomp
      lcut
      lcut_all
      ltrim
      ltrim_multi
      mark_raw
      rcut
      rcut_all
      remove_ansi
      remove_bom
      rtrim
      rtrim_multi
      table
      to_camel_case
      to_snake_case
      trim
      trim_multi
      unmark_raw
      ]
];
use Encode qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Term::ANSIColor qw[];
use Text::Xslate qw[mark_raw unmark_raw];

our $ENC_CACHE = {};

our %ESC_ANSI_CTRL = (
    qq[\a] => q[\a],
    qq[\b] => q[\b],
    qq[\t] => q[\t],
    qq[\n] => q[\n],
    qq[\f] => q[\f],
    qq[\r] => q[\r],
    qq[\e] => q[\e],
);

# TODO
# - crunch - ?;
# - P->text - clear trim functions names, eg, P->text->rcut_all -> P->text->trim_trailing_hs
# - autogenerated functions should always return ScalarRef if wantarray;

our $CODE = {
    decode_eol => <<'PERL',    # convert EOL to internal \n representation
        s/\x0D?\x0A/\n/smg;
PERL
    remove_bom => <<'PERL',    # remove BOM
        s/\A(?:\x00\x00\xFE\xFF|\xFF\xFE\x00\x00|\xFE\xFF|\xFF\xFE|\xEF\xBB\xBF)//sm;
PERL
    fullchomp => <<'PERL',
        s/(?:\x0D|\x0A)+\z//sm;
PERL

    # "trim" functions removes spaces and tabs
    trim => <<'PERL',
        s/\A\h+//sm;        # ltrim
        s/\h+\z//sm;        # rtrim
PERL
    ltrim => <<'PERL',         # treats string as single-line, remove all \h (space, tab) before first \n, non-space or non-tab character)
        s/\A\h+//sm;
PERL
    rtrim => <<'PERL',         # treats string as single-line, remove all \h (space, tab) after last \n, non-space or non-tab character
        s/\h+\z//sm;
PERL

    trim_multi => <<'PERL',
        s/^\h+//smg;    # ltrim_multi
        s/\h+$//smg;    # rtrim_multi
PERL
    ltrim_multi => <<'PERL',    # treats string as multi-line, remove \h just after each \n or string begin
        s/^\h+//smg;
PERL
    rtrim_multi => <<'PERL',    # treats string as multi-line, remove \h before each \n
        s/\h+$//smg;
PERL

    # "cut" functions compress several \n to one \n
    cut => <<'PERL',            # replace all \n series with single \n
        s/\A\v+//sm; # lcut
        s/\v+\z//sm; # rcut
        s/\v+/\n/smg;
PERL
    lcut => <<'PERL',           # treats string as single-line, cut all \n before first character
        s/\A\v+//sm;
PERL
    rcut => <<'PERL',           # treats string as single-line, remove all \n after last character, including last \n
        s/\v+\z//sm;
PERL

    # "cut_all" functions combines trim and cut functionality together
    cut_all => <<'PERL',        # trim_multi + cut

        # trim_multi
        s/^\h+//smg;    # ltrim_multi
        s/\h+$//smg;    # rtrim_multi

        # cut
        s/\A\v+//sm; # lcut
        s/\v+\z//sm; # rcut
        s/\v+/\n/smg;
PERL
    lcut_all => <<'PERL',       # remove empty lines and lines, consisting only of spaces and tabs, from string start
        s/\A\s+//sm;
PERL
    rcut_all => <<'PERL',       # remove empty lines and lines, consisting only of spaces and tabs, from string end, including last \n
        s/\s+\z//sm;
PERL

    # encode
    # Used to convert HTML tags to plain text:
    # <textarea>[% data | html %]</textarea>, <p>[% data | html %]</p>
    encode_html => <<'PERL',
        s/([&<>"'])/q[&#] . ord $1/smge;
PERL

    # Used to quote HTML tag attribute, example:
    # <input type="text" value="[% data | html_attr %]">
    encode_html_attr => <<'PERL',
        s/(\W)/q[&#] . ord $1/smge;
PERL

    # Used to encode javascript string, such as:
    # var a = "[% data | js_string %]";
    # onclick="alert('[% data | js_string %]')"
    # onclick="alert(&#34;[% data | js_string %]&#34;)" - hint: &#34; = "
    encode_js_string => <<'PERL',
        s/(\W)/sprintf q[\x%02lx], ord $1/smge;
PERL

    encode_hex => <<'PERL',
        $_ = unpack 'H*', $_;
PERL

    # DECODE, ENCODE
    decode_utf8 => <<'PERL',
        my %args = (
            encoding   => 'UTF-8',
            decode_eol => 1,
            splice @_, 1,
        );

        if ( defined && !utf8::is_utf8 $_ ) {
            my $enc = $ENC_CACHE->{ $args{encoding} } // do {
                $ENC_CACHE->{ $args{encoding} } = Encode::find_encoding( $args{encoding} );
            };

            $_ = $enc->decode( $_, Encode::FB_CROAK | Encode::LEAVE_SRC );

            s/\x0D?\x0A/\n/smg if $args{decode_eol};
        }
PERL

    encode_utf8 => <<'PERL',
        # Encode::_utf8_off $_ if utf8::is_utf8 $_;    ## no critic qw[Subroutines::ProtectPrivateSubs]

        utf8::encode $_ if utf8::is_utf8 $_;
PERL

};

# create accessors
for my $name ( keys $CODE->%* ) {
    my $sub = <<'PERL';
sub <: $name :> {
    my $_;

    if ( defined wantarray ) {
        $_ = $_[0];

        <: $code :>

        return $_;
    }
    else {
        \$_ = \$_[0];

        <: $code :>

        return;
    }
}
PERL

    $sub =~ s/<: \$name :>/$name/smg;

    $sub =~ s/<: \$code :>/$CODE->{$name}/smg;

    eval $sub;    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
}

# UTIL
sub table {
    state $init = !!require Pcore::Util::Text::Table;

    return Pcore::Util::Text::Table->new(@_);
}

sub remove_ansi {
    if ( defined wantarray ) {
        return join q[], map {s/\e.+?m//smgr} @_;
    }
    else {
        for (@_) {    # convert in-place
            s/\e.+?m//smg;
        }

        return;
    }
}

sub escape_scalar {
    my $_;

    if ( defined wantarray ) {
        $_ = $_[0];
    }
    else {
        \$_ = \$_[0];
    }

    my %args = (
        bin         => undef,     # if TRUE - always treats scalar as binary data
        utf8_encode => 1,         # if FALSE - in bin mode escape utf8 multi-byte chars as \x{...}
        esc_color   => undef,
        reset_color => 'reset',
        splice @_, 1,
    );

    # automatically detect scalar type
    if ( !defined $args{bin} ) {
        if ( utf8::is_utf8 $_ ) {    # UTF-8 scalar
            $args{bin} = 0;
        }
        elsif (/[[:^ascii:]]/sm) {    # latin1 octets
            $args{bin} = 1;
        }
        else {                        # ASCII bytes
            $args{bin} = 0;
        }
    }

    # escape scalar
    if ( $args{bin} ) {
        if ( utf8::is_utf8 $_ ) {
            if ( $args{utf8_encode} ) {
                encode_utf8($_);

                s/(.)/sprintf '\x%02X', ord $1/smge;
            }
            else {
                s/([[:ascii:]])/sprintf '\x%02X', ord $1/smge;

                s/([[:^ascii:]])/sprintf '\x{%X}', ord $1/smge;
            }
        }
        else {
            s/(.)/sprintf '\x%02X', ord $1/smge;
        }
    }
    else {
        my $esc_color = $args{esc_color} ? Term::ANSIColor::color( $args{esc_color} ) : q[];

        my $reset_color = $args{esc_color} ? Term::ANSIColor::color( $args{reset_color} ) : q[];

        s/([\a\b\t\n\f\r\e])/${esc_color}$ESC_ANSI_CTRL{$1}${reset_color}/smg;    # escape ANSI

        s/([\x00-\x1A\x1C-\x1F\x7F])/$esc_color . sprintf( '\x%02X', ord $1 ) . $reset_color/smge;    # hex ANSI non-printable chars
    }

    if ( defined wantarray ) {
        return $_;
    }
    else {
        return;
    }
}

# HTML ENTITIES
sub decode_html_entities {
    my $_;

    if ( defined wantarray ) {
        $_ = $_[0];
    }
    else {
        \$_ = \$_[0];
    }

    my %args = (
        trim => undef,
        splice @_, 1,
    );

    state $init = !!require HTML::Entities;

    decode $_;

    HTML::Entities::decode_entities $_;

    trim $_ if $args{trim};

    if ( defined wantarray ) {
        return $_;
    }
    else {
        return;
    }
}

# expand number from scientific format to ordinary
sub expand_num ($num) {
    return $num unless $num =~ /\A(.*)e([-+]?)(.*)\z/sm;

    my ( $abs, $sign, $exp ) = ( $1, $2, $3 );

    my $sig = $sign eq q[-] ? q[.] . ( $exp - 1 + length $abs ) : q[];

    return sprintf "%${sig}f", $num;
}

# pretty print number 1234567 -> 1_234_567
sub format_num ($num) {
    my $sign = $num =~ s/\A([^\d])//sm ? $1 : q[];

    my $fraction = $num =~ s/[.](\d+)\z//sm ? $1 : undef;

    $num = scalar reverse join q[_], ( reverse $num ) =~ /(.{1,3})/smg;

    $num .= q[.] . scalar reverse join q[_], ( reverse $fraction ) =~ /(.{1,3})/smg if $fraction;

    return $sign . $num;
}

sub to_snake_case {
    my $str;

    if ( defined wantarray ) {
        $str = $_[0];
    }
    else {
        \$str = \$_[0];
    }

    my %args = (
        split => undef,
        join  => undef,
        splice @_, 1,
    );

    if ( $args{split} ) {
        my @parts = split /\Q$args{split}\E/sm, $str;

        for (@parts) {
            $_ = lcfirst;

            s/([[:upper:]])/q[_] . lc $1/smge;
        }

        if ( $args{join} ) {
            $str = join $args{join}, @parts;
        }
        else {
            $str = join $args{split}, @parts;
        }
    }
    else {

        # convert camelCase to snake_case notation
        $str = lcfirst $str;

        $str =~ s/([[:upper:]])/q[_] . lc $1/smge;
    }

    if ( defined wantarray ) {
        return $str;
    }
    else {
        return;
    }
}

sub to_camel_case {
    my $str;

    if ( defined wantarray ) {
        $str = $_[0];
    }
    else {
        \$str = \$_[0];
    }

    my %args = (
        ucfirst => undef,
        split   => undef,
        join    => undef,
        splice @_, 1,
    );

    if ( $args{split} ) {
        my @parts = split /\Q$args{split}\E/sm, $str;

        for (@parts) {
            $_ = lc;

            s/_(.)/uc $1/smge;    # convert snake_case to camelCase notation

            $_ = ucfirst if $args{ucfirst};
        }

        if ( $args{join} ) {
            $str = join $args{join}, @parts;
        }
        else {
            $str = join $args{split}, @parts;
        }
    }
    else {
        $str = lc $str;

        $str =~ s/_(.)/uc $1/smge;    # convert snake_case to camelCase notation

        $str = ucfirst $str if $args{ucfirst};
    }

    if ( defined wantarray ) {
        return $str;
    }
    else {
        return;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 178                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 204                  │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 45, 46, 47, 48, 49,  │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## │      │ 50, 51               │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Text

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
