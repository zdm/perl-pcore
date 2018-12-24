package Pcore::Util::Text;

use Pcore -ansi, -export;
use Encode qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Text::Xslate qw[mark_raw unmark_raw];

our $ENC_CACHE = {};

our $EXPORT = [ qw[
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
      add_num_sep
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
      wrap
      ] ];

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
    local $_;

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
    require Pcore::Util::Text::Table;

    return Pcore::Util::Text::Table->new( {@_} );
}

sub remove_ansi {
    if ( defined wantarray ) {
        return join $EMPTY, map {s/\e.+?m//smgr} @_;
    }
    else {
        for (@_) {    # convert in-place
            s/\e.+?m//smg;
        }

        return;
    }
}

sub escape_scalar ( $str, @args ) {
    state %CTRL = (
        "\a" => '\a',
        "\b" => '\b',
        "\e" => '\e',
        "\f" => '\f',
        "\n" => '\n',
        "\r" => '\r',
        "\t" => '\t',
    );

    my %args = (
        quote       => 1,              # 1 - always quote, 2 - quote for fat-comma ("=>")
        readable    => 0,
        color       => 0,
        color_ctrl  => $BOLD . $RED,
        color_reset => $RESET,
        @args,
    );

    if ( $str eq $EMPTY ) {
        if ( defined wantarray ) {
            return $args{quote} ? q[''] : $EMPTY;
        }
        else {
            $_[0] = $args{quote} ? q[''] : $EMPTY;

            return;
        }
    }

    my $color_ctrl  = $args{color} && $args{color_ctrl}  ? $args{color_ctrl}  : $EMPTY;
    my $color_reset = $color_ctrl  && $args{color_reset} ? $args{color_reset} : $EMPTY;

    my $interpolation;

    # downgrade, if possible
    Encode::_utf8_off $str if utf8::is_utf8 $str && length $str == bytes::length $str;

    # escape '/'
    $str =~ s[/][\/]smg if $args{quote};

    # escape control characters
    $interpolation = 1 if $str =~ s/([\a\b\e\f\n\r\t])/$color_ctrl . $CTRL{$1} . $color_reset/smge;
    $interpolation = 1 if $str =~ s/([\x00-\x06\x0B\x0E-\x1A\x1C-\x1F\x7F-\x9F])/$color_ctrl . sprintf('\x%02X', ord $1) . $color_reset/smge;

    if ( utf8::is_utf8 $str) {
        if ( $args{readable} ) {
            $interpolation = 1 if $str =~ s/([\x80-\xFF])/sprintf '\x%02X', ord $1/smge;
        }
        else {
            $interpolation = 1 if $str =~ s/([[:^ascii:]])/sprintf((ord $1 > 255 ? '\x{%X}' : '\x%02X'), ord $1)/smge;

            Encode::_utf8_off $str;
        }
    }
    else {
        $interpolation = 1 if $str =~ s/([[:^ascii:]])/sprintf '\x%02X', ord $1/smge;
    }

    if ( $args{quote} ) {
        if ($interpolation) {
            $str =~ s/"/\\"/smg;
            $str = qq["$str"];
        }
        elsif ( $args{quote} != 2 || $str =~ /[^A-Za-z0-9_]/sm ) {
            $str =~ s/'/\\'/smg;
            $str = qq['$str'];
        }
    }

    if ( defined wantarray ) {
        return $str;
    }
    else {
        $_[0] = $str;

        return;
    }
}

sub wrap ( $text, $width, % ) {
    my %args = (
        ansi  => 1,
        align => undef,
        splice @_, 2,
    );

    # remove ANSI
    $text =~ s/\e.+?m//smg if !$args{ansi};

    # expand tabs
    $text =~ s/\t/    /smg;

    state $wrap = sub ( $width, $ansi ) {
        my @lines;

        my $wrap_re = do {
            if   ($ansi) {qr/(\e.+?m|\s)/sm}
            else         {qr/(\s)/sm}
        };

        my $buf = $EMPTY;

        my $buf_len = 0;

        for my $word ( grep { $_ ne $EMPTY } split $wrap_re ) {
            if ( $ansi && $word =~ /\e.+?m/sm ) {
                $buf .= $word;
            }
            elsif ( $buf_len + length $word > $width ) {

                # wrap by any character
                # $buf .= substr $word, 0, $width - $buf_len, $EMPTY;

                # drop current buf to @lines
                push @lines, $buf if $buf ne $EMPTY;

                while ( length $word > $width ) {
                    push @lines, substr $word, 0, $width, $EMPTY;
                }

                # init next buf
                $buf     = $word;
                $buf_len = length $word;
            }
            else {
                $buf .= $word;
                $buf_len += length $word;
            }
        }

        push @lines, $buf if $buf ne $EMPTY;

        return @lines;
    };

    my @lines;

    # wrap lines
    for ( split /\n/sm, $text ) {
        push @lines, $wrap->( $width, $args{ansi} );
    }

    # process ansi seq.
    if ( $args{ansi} ) {
        my $ansi_prefix = $EMPTY;

        for my $line (@lines) {
            my $cur_ansi_prefix = $ansi_prefix;

            if ( my @ansi = $line =~ /(\e.+?m)/smg ) {
                if ( $ansi[-1] ne "\e[0m" ) {
                    $line .= "\e[0m";

                    $ansi_prefix .= join $EMPTY, @ansi;
                }
                else {
                    $ansi_prefix = $EMPTY;
                }
            }
            elsif ($cur_ansi_prefix) { $line .= "\e[0m" }

            $line = $cur_ansi_prefix . $line if $cur_ansi_prefix;
        }
    }

    # align
    if ( defined $args{align} != -1 ) {
        for my $line (@lines) {
            my $len = length( $args{ansi} ? $line =~ s/\e.+?m//smgr : $line );

            next if $len == $width;

            if ( $args{align} == -1 ) {

                # right
                $line .= ( $SPACE x ( $width - $len ) );
            }
            elsif ( $args{align} == 1 ) {

                # left
                $line = $SPACE x ( $width - $len ) . $line;
            }
            elsif ( $args{align} == 0 ) {

                # center
                my $left  = int( ( $width - $len ) / 2 );
                my $right = $width - $len - $left;

                $line = ( $SPACE x $left ) . $line . ( $SPACE x $right );
            }
            else {
                die q[Invalid align value];
            }
        }
    }

    return \@lines;
}

# HTML ENTITIES
sub decode_html_entities {
    local $_;

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

    require HTML::Entities;

    Pcore::Util::Text::decode_utf8 $_;

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

    my $sig = $sign eq q[-] ? q[.] . ( $exp - 1 + length $abs ) : $EMPTY;

    return sprintf "%${sig}f", $num;
}

# pretty print number 1234567 -> 1_234_567
sub add_num_sep ( $num, $sep = q[_] ) {
    my $sign = $num =~ s/\A([^\d])//sm ? $1 : $EMPTY;

    my $fraction = $num =~ s/[.](\d+)\z//sm ? $1 : undef;

    $num = scalar reverse join $sep, ( reverse $num ) =~ /(.{1,3})/smg;

    $num .= q[.] . scalar reverse join $sep, ( reverse $fraction ) =~ /(.{1,3})/smg if $fraction;

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
        delim => q[_],
        split => undef,
        join  => undef,
        splice @_, 1,
    );

    if ( $args{split} ) {
        my @parts = split /\Q$args{split}\E/sm, $str;

        for (@parts) {
            $_ = lcfirst;

            s/([[:upper:]])/$args{delim} . lc $1/smge;
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

        $str =~ s/([[:upper:]])/$args{delim} . lc $1/smge;
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
        delim   => q[_],
        ucfirst => undef,
        split   => undef,
        join    => undef,
        splice @_, 1,
    );

    if ( $args{split} ) {
        my @parts = split /\Q$args{split}\E/sm, $str;

        for (@parts) {
            $_ = lc;

            s/$args{delim}(.)/uc $1/smge;    # convert snake_case to camelCase notation

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

        $str =~ s/$args{delim}(.)/uc $1/smge;    # convert snake_case to camelCase notation

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
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 193                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitExcessComplexity                                                                          |
## |      | 216                  | * Subroutine "escape_scalar" with high complexity score (28)                                                   |
## |      | 297                  | * Subroutine "wrap" with high complexity score (28)                                                            |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 253, 269             | Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | NamingConventions::ProhibitAmbiguousNames                                                                      |
## |      | 403, 404             | * Ambiguously named variable "left"                                                                            |
## |      | 404                  | * Ambiguously named variable "right"                                                                           |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 419                  | Variables::RequireInitializationForLocalVars - "local" variable not initialized                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 218, 219, 220, 221,  | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## |      | 222, 223, 224        |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 281                  | RegularExpressions::ProhibitEnumeratedClasses - Use named character classes ([^A-Za-z0-9_] vs. \W)             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
