package Pcore::Util::Text;

use Pcore -export, [qw[decode trim encode_hex mark_raw unmark_raw]];
use Encode qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use Term::ANSIColor qw[];
use Text::Xslate qw[mark_raw unmark_raw];

our %ESC_ANSI_CTRL = (
    qq[\a] => q[\a],
    qq[\b] => q[\b],
    qq[\t] => q[\t],
    qq[\n] => q[\n],
    qq[\f] => q[\f],
    qq[\r] => q[\r],
    qq[\e] => q[\e],
);

# http://docs.jquery.com/UI/Datepicker/formatDate
our %STRFTIME_JQUERY = (
    q[%e] => q[d],     # day of month (no leading zero)
    q[%d] => q[dd],    # day of month (2 digits)
    q[%j] => q[oo],    # day of year (3 digits)
    q[%a] => q[D],     # day name long
    q[%A] => q[DD],    # day name short
    q[%m] => q[mm],    # month of year (two digits)
    q[%b] => q[M],     # Month name short
    q[%B] => q[MM],    # Month name long
    q[%y] => q[y],     # year (2 digits)
    q[%Y] => q[yy],    # year (4 digits)
    q[%s] => q[@],     # epoch
);

# TODO
# - crunch - ?;
# - fullchomp - ?;
# - P->text - disallow to accept references, only plain scalars, test, how it will work with objects;
# - P->text - clear trim functions names, eg, P->text->rcut_all -> P->text->trim_trailing_hs

our $SUB = {
    decode_eol => sub {    # convert EOL to internal \n representation
        $_[0] =~ s/\x0D?\x0A/\n/smg;

        return;
    },
    remove_bom => sub {    # remove BOM
        $_[0] =~ s/\A(?:\x00\x00\xFE\xFF|\xFF\xFE\x00\x00|\xFE\xFF|\xFF\xFE|\xEF\xBB\xBF)//sm;

        return;
    },

    # "trim" functions removes spaces and tabs
    trim => sub {          # see below
        &ltrim;            ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        &rtrim;            ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        return;
    },
    ltrim => sub {         # treats string as single-line, remove all \h (space, tab) before first \n, non-space or non-tab character)
        $_[0] =~ s/\A\h+//sm;

        return;
    },
    rtrim => sub {         # treats string as single-line, remove all \h (space, tab) after last \n, non-space or non-tab character
        $_[0] =~ s/\h+\z//sm;

        return;
    },
    trim_multi => sub {    # see below
        &ltrim_multi;      ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        &rtrim_multi;      ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        return;
    },
    ltrim_multi => sub {    # treats string as multi-line, remove \h just after each \n or string begin
        $_[0] =~ s/^\h+//smg;

        return;
    },
    rtrim_multi => sub {    # treats string as multi-line, remove \h before each \n
        $_[0] =~ s/\h+$//smg;

        return;
    },

    # "cut" functions compress several \n to one \n
    cut => sub {            # replace all \n series with single \n
        &lcut;              ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        &rcut;              ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        $_[0] =~ s/\v+/\n/smg;

        return;
    },
    lcut => sub {           # treats string as single-line, cut all \n before first character
        $_[0] =~ s/\A\v+//sm;

        return;
    },
    rcut => sub {           # treats string as single-line, remove all \n after last character, including last \n
        $_[0] =~ s/\v+\z//sm;

        return;
    },

    # "cut_all" functions combines trim and cut functionality together
    cut_all => sub {        # trim_multi + cut
        &trim_multi;        ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        &cut;               ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        return;
    },
    lcut_all => sub {       # remove empty lines and lines, consisting only of spaces and tabs, from string start
        $_[0] =~ s/\A\s+//sm;

        return;
    },
    rcut_all => sub {       # remove empty lines and lines, consisting only of spaces and tabs, from string end, including last \n
        $_[0] =~ s/\s+\z//sm;

        return;
    },

    # encode
    # Used to convert HTML tags to plain text:
    # <textarea>[% data | html %]</textarea>, <p>[% data | html %]</p>
    encode_html => sub {
        $_[0] =~ s/([&<>"'])/q[&#] . ord $1/smge;

        return;
    },

    # Used to quote HTML tag attribute, example:
    # <input type="text" value="[% data | html_attr %]">
    encode_html_attr => sub {
        $_[0] =~ s/(\W)/q[&#] . ord $1/smge;

        return;
    },

    # Used to encode javascript string, such as:
    # var a = "[% data | js_string %]";
    # onclick="alert('[% data | js_string %]')"
    # onclick="alert(&#34;[% data | js_string %]&#34;)" - hint: &#34; = "
    encode_js_string => sub {
        $_[0] =~ s/(\W)/sprintf q[\x%02lx], ord $1/smge;

        return;
    },

    # used to convert strftime patterns to jquery formatDate patterns
    encode_strftime_jquery => sub {
        for ( keys %STRFTIME_JQUERY ) {
            $_[0] =~ s/($_)/$STRFTIME_JQUERY{$1}/smg;
        }

        $_[0] =~ s/%.|://smg;

        &trim;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]

        return;
    },

    encode_hex => sub {
        $_[0] = unpack 'H*', $_[0];

        return;
    },
};

# create sccessors
#  TODO
#  inline args wrapper + sub body
for my $sub ( keys $SUB->%* ) {
    no strict qw[refs];

    *{$sub} = sub {
        my $scalar_ref = do {    # want a copy
            if ( defined wantarray ) {

                # make a copy and stringify
                if ( ref $_[0] ) {
                    if ( ref $_[0] eq 'SCALAR' ) {
                        \( q[] . $_[0]->$* );
                    }
                    else {
                        \( q[] . $_[0] );
                    }
                }
                else {
                    \( q[] . $_[0] );
                }
            }
            else {    # modify string in-place
                if ( ref $_[0] ) {
                    if ( ref $_[0] eq 'SCALAR' ) {
                        $_[0];
                    }
                    else {

                        # make a copy and stringify, this behaviour is unclear
                        $_[0] = q[] . $_[0];

                        \$_[0];
                    }
                }
                else {
                    \$_[0];
                }
            }
        };

        $SUB->{$sub}->( $scalar_ref->$* );

        if ( defined wantarray ) {
            return $scalar_ref->$*;
        }
        else {
            return;
        }
    };
}

# UTIL
sub table {
    return P->class->load('Pcore::Util::Text::Table')->new(@_);
}

sub remove_ansi_color {
    if ( defined wantarray ) {
        my $res;

        for (@_) {
            $res .= s/\e.+?m//smgr;
        }

        return \$res;
    }
    else {
        for (@_) {    # convert in-place
            s/\e.+?m//smg;
        }

        return;
    }
}

sub escape_scalar {
    my $scalar_ref = defined wantarray ? ref $_[0] ? \( q[] . shift->$* ) : \( q[] . shift ) : ref $_[0] ? ref $_[0] eq 'SCALAR' ? shift : \( q[] . shift ) : \shift;
    my %args = (
        bin         => undef,     # if TRUE - always treats scalar as binary data
        utf8_encode => 1,         # if FALSE - in bin mode escape utf8 multi-byte chars as \x{...}
        esc_color   => undef,
        reset_color => 'reset',
        @_,
    );

    # automatically detect scalar type
    if ( !defined $args{bin} ) {
        if ( utf8::is_utf8( $scalar_ref->$* ) ) {    # UTF-8 scalar
            $args{bin} = 0;
        }
        elsif ( $scalar_ref->$* =~ /[[:^ascii:]]/sm ) {    # latin1 octets
            $args{bin} = 1;
        }
        else {                                             # ASCII bytes
            $args{bin} = 0;
        }
    }

    # escape scalar
    if ( $args{bin} ) {
        if ( utf8::is_utf8( $scalar_ref->$* ) ) {
            if ( $args{utf8_encode} ) {
                encode_utf8($scalar_ref);

                $scalar_ref->$* =~ s/(.)/sprintf q[\x%X], ord $1/smge;
            }
            else {
                $scalar_ref->$* =~ s/([[:ascii:]])/sprintf q[\x%X], ord $1/smge;
                $scalar_ref->$* =~ s/([[:^ascii:]])/sprintf q[\x{%X}], ord $1/smge;
            }
        }
        else {
            $scalar_ref->$* =~ s/(.)/sprintf q[\x%X], ord $1/smge;
        }
    }
    else {
        my $esc_color   = $args{esc_color} ? Term::ANSIColor::color( $args{esc_color} )   : q[];
        my $reset_color = $args{esc_color} ? Term::ANSIColor::color( $args{reset_color} ) : q[];

        $scalar_ref->$* =~ s/([\a\b\t\n\f\r\e])/${esc_color}$ESC_ANSI_CTRL{$1}${reset_color}/smg;                       # escape ANSI
        $scalar_ref->$* =~ s/([\x00-\x1A\x1C-\x1F\x7F])/$esc_color . sprintf( q[\x%X], ord $1 ) . $reset_color/smge;    # hex ANSI non-printable chars
    }

    if ( defined wantarray ) {
        return $scalar_ref;
    }
    else {
        return;
    }
}

# HTML ENTITIES
sub decode_html_entities {
    my $scalar_ref = defined wantarray ? ref $_[0] ? \( q[] . shift->$* ) : \( q[] . shift ) : ref $_[0] ? ref $_[0] eq 'SCALAR' ? shift : \( q[] . shift ) : \shift;
    my %args = (
        trim => undef,
        @_,
    );

    require HTML::Entities;

    decode($scalar_ref);

    HTML::Entities::decode_entities( $scalar_ref->$* );

    trim($scalar_ref) if $args{trim};

    if ( defined wantarray ) {
        return $scalar_ref;
    }
    else {
        return;
    }
}

# DECODE, ENCODE
sub decode {
    my $scalar_ref = defined wantarray ? ref $_[0] ? \( q[] . shift->$* ) : \( q[] . shift ) : ref $_[0] ? ref $_[0] eq 'SCALAR' ? shift : \( q[] . shift ) : \shift;
    my %args = (
        encoding   => 'UTF-8',
        decode_eol => 1,
        @_,
    );

    state $encoding = {};

    if ( defined $scalar_ref->$* && !utf8::is_utf8( $scalar_ref->$* ) ) {
        $encoding->{ $args{encoding} } //= Encode::find_encoding( $args{encoding} );

        $scalar_ref->$* = $encoding->{ $args{encoding} }->decode( $scalar_ref->$*, Encode::FB_CROAK | Encode::LEAVE_SRC );    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

        $scalar_ref->$* =~ s/\x0D?\x0A/\n/smg if $args{decode_eol};
    }

    if ( defined wantarray ) {
        return $scalar_ref;
    }
    else {
        return;
    }
}

sub encode_utf8 {
    my $scalar_ref = defined wantarray ? ref $_[0] ? \( q[] . shift->$* ) : \( q[] . shift ) : ref $_[0] ? ref $_[0] eq 'SCALAR' ? shift : \( q[] . shift ) : \shift;

    # Encode::_utf8_off( ${$scalar} ) if utf8::is_utf8( ${$scalar} );    ## no critic qw[Subroutines::ProtectPrivateSubs]

    utf8::encode( $scalar_ref->$* ) if utf8::is_utf8( $scalar_ref->$* );

    if ( defined wantarray ) {
        return $scalar_ref;
    }
    else {
        return;
    }
}

# expand number from scientific format to ordinary
sub expand ($n) {
    return $n unless $n =~ /\A(.*)e([-+]?)(.*)\z/sm;

    my ( $num, $sign, $exp ) = ( $1, $2, $3 );

    my $sig = $sign eq q[-] ? q[.] . ( $exp - 1 + length $num ) : q[];

    return sprintf "%${sig}f", $n;
}

sub to_snake_case {
    my $str = defined wantarray ? \( q[] . shift ) : \$_[0];

    my %args = (
        split => undef,
        join  => undef,
        ( defined wantarray ? @_ : splice @_, 1 ),
    );

    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    if ( $args{split} ) {
        my @parts = split /\Q$args{split}\E/sm, $str->$*;

        for (@parts) {
            $_ = lcfirst;
            s/([[:upper:]])/q[_] . lc $1/smge;
        }

        if ( $args{join} ) {
            $str->$* = join $args{join}, @parts;
        }
        else {
            $str->$* = join $args{split}, @parts;
        }
    }
    else {

        # convert camelCase to snake_case notation
        $str->$* = lcfirst $str->$*;

        $str->$* =~ s/([[:upper:]])/q[_] . lc $1/smge;
    }

    if ( defined wantarray ) {
        return $str->$*;
    }
    else {
        return;
    }
}

sub to_camel_case {
    my $str = defined wantarray ? \( q[] . shift ) : \$_[0];

    my %args = (
        ucfirst => undef,
        split   => undef,
        join    => undef,
        ( defined wantarray ? @_ : splice @_, 1 ),
    );

    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    if ( $args{split} ) {
        my @parts = split /\Q$args{split}\E/sm, $str->$*;

        for (@parts) {
            $_ = lc;

            s/_(.)/uc $1/smge;    # convert snake_case to camelCase notation

            $_ = ucfirst if $args{ucfirst};
        }

        if ( $args{join} ) {
            $str->$* = join $args{join}, @parts;
        }
        else {
            $str->$* = join $args{split}, @parts;
        }
    }
    else {
        $str->$* = lc $str->$*;

        $str->$* =~ s/_(.)/uc $1/smge;    # convert snake_case to camelCase notation

        $str->$* = ucfirst $str->$* if $args{ucfirst};
    }

    if ( defined wantarray ) {
        return $str->$*;
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
## │    3 │ 46                   │ RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 177                  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 9, 10, 11, 12, 13,   │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## │      │ 14, 15               │                                                                                                                │
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
