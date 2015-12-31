package Pcore::Util::Data1;

use Pcore -const, -export,
  { ALL   => [qw[encode_data decode_data]],
    PERL  => [qw[to_perl from_perl]],
    JSON  => [qw[to_json from_json]],
    CBOR  => [qw[to_cbor from_cbor]],
    YAML  => [qw[to_yaml from_yaml]],
    XML   => [qw[to_xml from_xml]],
    INI   => [qw[to_ini from_ini]],
    B64   => [qw[to_b64 to_b64_url from_b64 from_b64_url]],
    B85   => [qw[to_b85 from_b85]],
    URI   => [qw[to_uri from_uri from_uri_query]],
    CONST => [qw[$DATA_ENC_B64 $DATA_ENC_HEX $DATA_ENC_B85 $DATA_COMPRESS_ZLIB $DATA_CIPHER_DES]],
    TYPE  => [qw[$DATA_TYPE_PERL $DATA_TYPE_JSON $DATA_TYPE_CBOR $DATA_TYPE_YAML $DATA_TYPE_XML $DATA_TYPE_INI]],
  };
use Pcore::Util::Data::I18N;
use Pcore::Util::Text qw[decode_utf8 encode_utf8 escape_scalar];
use Pcore::Util::List qw[pairs];
use Sort::Naturally qw[nsort];
use Pcore::Util::Scalar qw[blessed];
use URI::Escape::XS qw[];    ## no critic qw[Modules::ProhibitEvilModules]
use WWW::Form::UrlEncoded::XS qw[];

const our $DATA_TYPE_PERL => 1;
const our $DATA_TYPE_JSON => 2;
const our $DATA_TYPE_CBOR => 3;
const our $DATA_TYPE_YAML => 4;
const our $DATA_TYPE_XML  => 5;
const our $DATA_TYPE_INI  => 6;

const our $DATA_ENC_B64 => 1;
const our $DATA_ENC_HEX => 2;
const our $DATA_ENC_B85 => 3;

const our $DATA_COMPRESS_ZLIB => 1;

const our $DATA_CIPHER_DES => 1;

const our $CIPHER_NAME => {    #
    $DATA_CIPHER_DES => 'DES',
};

our $JSON_CACHE;

# JSON is used by default
# JSON can't serialize ScalarRefs
# objects should have TO_JSON method, otherwise object will be serialized as null
# base64 encoder is used by default, it generates more compressed data
sub encode_data ( $type, $data, @ ) {
    my %args = (
        readable           => undef,               # make serialized data readable for humans
        compress           => undef,               # use compression
        secret             => undef,               # crypt data if defined, can be ArrayRef
        secret_index       => 0,                   # index of secret to use in secret array, if secret is ArrayRef
        encoding           => undef,               # 0 - disable
        token              => undef,               # attach informational token
        compress_threshold => 100,                 # min data length in bytes to perform compression, only if compress = 1
        cipher             => $DATA_CIPHER_DES,    # cipher to use
        json               => undef,               # HashRef with additional params for JSON::XS
        splice @_, 2,
    );

    if ( $args{readable} && $type != $DATA_TYPE_CBOR ) {
        $args{compress} = undef;
        $args{secret}   = undef;
        $args{encoding} = undef;
        $args{token}    = undef;
    }

    my $res;

    # encode
    if ( $type == $DATA_TYPE_PERL ) {
        state $init = !!require Data::Dumper;

        state $sort_keys = sub {
            return [ nsort keys $_[0]->%* ];
        };

        local $Data::Dumper::Indent     = 0;
        local $Data::Dumper::Purity     = 1;
        local $Data::Dumper::Pad        = q[];
        local $Data::Dumper::Terse      = 1;
        local $Data::Dumper::Deepcopy   = 0;
        local $Data::Dumper::Quotekeys  = 0;
        local $Data::Dumper::Pair       = '=>';
        local $Data::Dumper::Maxdepth   = 0;
        local $Data::Dumper::Deparse    = 0;
        local $Data::Dumper::Sparseseen = 1;
        local $Data::Dumper::Useperl    = 1;
        local $Data::Dumper::Useqq      = 1;
        local $Data::Dumper::Sortkeys   = $args{readable} ? $sort_keys : 0;

        if ( !defined $data ) {
            $res = \'undef';
        }
        else {
            no warnings qw[redefine];

            local *Data::Dumper::qquote = sub {
                return q["] . encode_utf8( escape_scalar $_[0] ) . q["];
            };

            $res = \Data::Dumper->Dump( [$data] );
        }

        if ( $args{readable} ) {
            state $init1 = !!require Pcore::Src::File;

            $res = Pcore::Src::File->new(
                {   action      => 'decompress',
                    path        => 'config.perl',    # mark file as perl config
                    is_realpath => 0,
                    in_buffer   => $res,
                    filter_args => {
                        perl_tidy   => '--comma-arrow-breakpoints=0',
                        perl_critic => 0,
                    },
                }
            )->run->out_buffer;
        }
    }
    elsif ( $type == $DATA_TYPE_JSON ) {
        if ( $args{json} ) {
            my $json = _get_json_obj( $args{json}->%* );

            $res = \$json->encode($data);
        }
        elsif ( $args{readable} ) {
            state $json = _get_json_obj( ascii => 0, latin1 => 0, utf8 => 1, pretty => 1 );

            $res = \$json->encode($data);
        }
        else {
            state $json = _get_json_obj( ascii => 1, latin1 => 0, utf8 => 1, pretty => 0 );

            $res = \$json->encode($data);
        }
    }
    elsif ( $type == $DATA_TYPE_CBOR ) {
        state $cbor = _get_cbor_obj();

        $res = \$cbor->encode($data);
    }
    elsif ( $type == $DATA_TYPE_YAML ) {
        state $init = !!require YAML::XS;

        local $YAML::XS::UseCode  = 0;
        local $YAML::XS::DumpCode = 0;
        local $YAML::XS::LoadCode = 0;

        $res = \YAML::XS::Dump($data);
    }
    elsif ( $type == $DATA_TYPE_XML ) {
        state $init = !!require XML::Hash::XS;

        state $xml_args = {
            root      => 'root',
            version   => '1.0',
            encoding  => 'UTF-8',
            output    => undef,
            canonical => 0,            # sort hash keys
            use_attr  => 1,
            content   => 'content',    # if defined that the key name for the text content(used only if use_attr=1)
            xml_decl  => 1,
            trim      => 1,
            utf8      => 0,
            buf_size  => 4096,
            method    => 'NATIVE',
        };

        state $xml_obj = XML::Hash::XS->new( $xml_args->%* );

        my $root = [ keys $data->%* ]->[0];

        $res = \$xml_obj->hash2xml( $data->{$root}, root => $root, indent => $args{readable} ? 4 : 0 );
    }
    elsif ( $type == $DATA_TYPE_INI ) {
        state $init = !!require Config::INI::Writer;

        $res = \Config::INI::Writer->write_string($data);
    }
    else {
        die qq[Unknown serializer "$type"];
    }

    # compress
    if ( $args{compress} ) {
        if ( bytes::length $res->$* >= $args{compress_threshold} ) {
            if ( $args{compress} == $DATA_COMPRESS_ZLIB ) {
                state $init = !!require Compress::Zlib;

                $res = \Compress::Zlib::compress( $res->$* );
            }
            else {
                die qq[Unknown compressor type "$args{compress}"];
            }
        }
        else {
            $args{compress} = 0;
        }
    }

    # encrypt
    if ( defined $args{secret} ) {
        my $secret;

        if ( ref $args{secret} eq 'ARRAY' ) {
            $secret = $args{secret}->[ $args{secret_index} ];
        }
        else {
            $secret = $args{secret};
        }

        if ( defined $secret ) {
            state $init = !!require Crypt::CBC;

            $res = \Crypt::CBC->new(
                -key    => $secret,
                -cipher => $CIPHER_NAME->{ $args{cipher} },
            )->encrypt( $res->$* );
        }
        else {
            $args{secret} = undef;
        }
    }

    # encode
    if ( $args{encoding} ) {
        if ( $args{encoding} == $DATA_ENC_B64 ) {
            $res = \to_b64_url( $res->$* );
        }
        elsif ( $args{encoding} == $DATA_ENC_HEX ) {
            $res = \unpack 'H*', $res->$*;
        }
        elsif ( $args{encoding} == $DATA_ENC_B85 ) {
            $res = \to_b85( $res->$* );
        }
        else {
            die qq[Unknown encoder "$args{encoding}"];
        }
    }

    # add token
    if ( $args{token} ) {
        $res->$* .= sprintf( '#%x', ( $args{compress} // 0 ) . ( defined $args{secret} ? $args{cipher} : 0 ) . ( $args{secret_index} // 0 ) . ( $args{encoding} // 0 ) . $type ) . sprintf( '#%x', bytes::length $res->$* );
    }

    return $res;
}

# JSON data should be without UTF8 flag
# objects isn't deserialized automatically from JSON
sub decode_data ( $type, @ ) {
    my $data_ref = ref $_[1] ? $_[1] : \$_[1];

    my %args = (
        compress     => undef,
        secret       => undef,              # can be ArrayRef
        secret_index => 0,
        cipher       => $DATA_CIPHER_DES,
        encoding     => undef,              # 0, 1 = 'hex', 'hex', 'b64'
        perl_ns      => undef,              # for PERL only, namespace for data evaluation
        json         => undef,              # HashRef with additional params for JSON::XS
        return_token => 0,                  # return token
        splice( @_, 2 ),
        type => $type,
    );

    # parse token
    if ( $data_ref->$* =~ /#([[:xdigit:]]{1,8})#([[:xdigit:]]{1,16})\z/sm ) {
        my $token_len = 2 + length($1) + length $2;

        if ( bytes::length( $data_ref->$* ) - $token_len == hex $2 ) {
            $args{has_token} = 1;

            substr $data_ref->$*, -$token_len, $token_len, q[];

            ( $args{compress}, $args{cipher}, $args{secret_index}, $args{encoding}, $type ) = split //sm, sprintf '%05s', hex $1;

            $args{type} = $type;
        }
    }

    # decode
    if ( $args{encoding} ) {
        if ( $args{encoding} == $DATA_ENC_B64 ) {
            $data_ref = \from_b64_url( $data_ref->$* );
        }
        elsif ( $args{encoding} == $DATA_ENC_HEX ) {
            $data_ref = \pack 'H*', $data_ref->$*;
        }
        elsif ( $args{encoding} == $DATA_ENC_B85 ) {
            $data_ref = \from_b85( $data_ref->$* );
        }
        else {
            die qq[Unknown encoder "$args{encoding}"];
        }
    }

    # decrypt
    if ( $args{cipher} && defined $args{secret} ) {
        my $secret;

        if ( ref $args{secret} eq 'ARRAY' ) {
            $secret = $args{secret}->[ $args{secret_index} ];
        }
        else {
            $secret = $args{secret};
        }

        if ( defined $secret ) {
            state $init = !!require Crypt::CBC;

            $data_ref = \Crypt::CBC->new(
                -key    => $secret,
                -cipher => $CIPHER_NAME->{ $args{cipher} },
            )->decrypt( $data_ref->$* );

        }
    }

    # decompress
    if ( $args{compress} ) {
        if ( $args{compress} == $DATA_COMPRESS_ZLIB ) {
            state $init = !!require Compress::Zlib;

            $data_ref = \Compress::Zlib::uncompress($data_ref);

            die if !defined $data_ref->$*;
        }
        else {
            die qq[Unknown compressor "$args{compressor}"];
        }
    }

    # decode
    my $res;

    if ( $type == $DATA_TYPE_PERL ) {
        my $ns = $args{perl_ns} || '_Pcore::CONFIG::SANDBOX';

        decode_utf8 $data_ref->$*;

        ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
        $res = eval <<"CODE";
package $ns;

use Pcore -config;
no warnings qw[redefine];

local *i18n = sub { return Pcore::Util::Data::I18N->new( { args => [ \@_ ] } ) };

$data_ref->$*
CODE
        die $@ if $@;

        die q[Config must return value] unless $res;
    }
    elsif ( $type == $DATA_TYPE_JSON ) {
        if ( $args{json} ) {
            my $json = _get_json_obj( $args{json}->%* );

            $res = $json->decode( $data_ref->$* );
        }
        else {
            state $json = _get_json_obj( utf8 => 1 );

            # $res = $json->decode_prefix( $data_ref->$* );

            $res = $json->decode( $data_ref->$* );
        }
    }
    elsif ( $type == $DATA_TYPE_CBOR ) {
        state $cbor = _get_cbor_obj();

        $res = $cbor->decode( $data_ref->$* );
    }
    elsif ( $type == $DATA_TYPE_YAML ) {
        state $init = !!require YAML::XS;

        local $YAML::XS::UseCode  = 0;
        local $YAML::XS::DumpCode = 0;
        local $YAML::XS::LoadCode = 0;

        $res = YAML::XS::Load( $data_ref->$* );
    }
    elsif ( $type == $DATA_TYPE_XML ) {
        state $init = !!require XML::Hash::XS;

        state $xml_args = {
            encoding      => 'UTF-8',
            utf8          => 1,
            max_depth     => 1024,
            buf_size      => 4096,
            force_array   => 1,
            force_content => 1,
            merge_text    => 1,
            keep_root     => 1,
        };

        state $xml_obj = XML::Hash::XS->new( $xml_args->%* );

        $res = $xml_obj->xml2hash($data_ref);
    }
    elsif ( $type == $DATA_TYPE_INI ) {
        state $init = !!require Config::INI::Reader;

        $res = Config::INI::Reader->read_string( $data_ref->$* );
    }
    else {
        die qq[Unknown serializer "$type"];
    }

    if ( wantarray && $args{return_token} ) {
        return $res, \%args;
    }
    else {
        return $res;
    }
}

# PERL
sub to_perl {
    return encode_data( $DATA_TYPE_PERL, @_ );
}

sub from_perl {
    return decode_data( $DATA_TYPE_PERL, @_ );
}

# JSON
sub _get_json_obj {
    my %args = (

        # COMMON
        utf8         => 1,
        allow_nonref => 1,    # allow scalars
        allow_tags   => 0,    # use FREEZE / THAW, we don't use this, because non-standard JSON will be generated, use CBOR instead to serialize objects

        # shrink                        => 0,
        # max_depth                     => 512,

        # DECODE
        relaxed => 1,    # allows commas and # - style comments

        # filter_json_object            => undef,
        # filter_json_single_key_object => undef,
        # max_size                      => 0,

        # ENCODE
        ascii  => 1,
        latin1 => 0,
        pretty => 0,    # set indent, space_before, space_after

        # indent       => 0,
        # space_before => 0,    # put a space before the ":" separating key from values
        # space_after  => 0,    # put a space after the ":" separating key from values, and after "," separating key-value pairs

        canonical       => 0,    # sort hash keys, slow
        allow_unknown   => 0,    # throw exception if can't encode item
        allow_blessed   => 1,    # allow blessed objects
        convert_blessed => 1,    # use TO_JSON method of blessed objects

        @_,
    );

    state $init = !!require JSON::XS;

    my $json = JSON::XS->new;

    for ( keys %args ) {
        $json->$_( $args{$_} );
    }

    return $json;
}

sub to_json ( $data, @ ) {
    return encode_data( $DATA_TYPE_JSON, @_ );
}

sub from_json ( $data, @ ) {
    return decode_data( $DATA_TYPE_JSON, @_ );
}

# CBOR
sub _get_cbor_obj {
    state $init = !!require CBOR::XS;

    my $cbor = CBOR::XS->new;

    $cbor->max_depth(512);
    $cbor->max_size(0);    # max. string size is unlimited
    $cbor->allow_unknown(0);
    $cbor->allow_sharing(1);
    $cbor->allow_cycles(1);
    $cbor->pack_strings(1);
    $cbor->validate_utf8(0);
    $cbor->filter(undef);

    return $cbor;
}

sub to_cbor {
    return encode_data( $DATA_TYPE_CBOR, @_ );
}

sub from_cbor {
    return decode_data( $DATA_TYPE_CBOR, @_ );
}

# YAML
sub to_yaml {
    return encode_data( $DATA_TYPE_YAML, @_ );
}

sub from_yaml {
    return decode_data( $DATA_TYPE_YAML, @_ );
}

# XML
sub to_xml {
    return encode_data( $DATA_TYPE_XML, @_ );
}

sub from_xml {
    return decode_data( $DATA_TYPE_XML, @_ );
}

# INI
sub to_ini {
    return encode_data( $DATA_TYPE_INI, @_ );
}

sub from_ini {
    return decode_data( $DATA_TYPE_INI, @_ );
}

# BASE64
sub to_b64 {
    state $init = !!require MIME::Base64;

    return &MIME::Base64::encode_base64;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

sub to_b64_url {
    state $init = !!require MIME::Base64;

    return &MIME::Base64::encode_base64url;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

sub from_b64 {
    state $init = !!require MIME::Base64;

    return &MIME::Base64::decode_base64;       ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

sub from_b64_url {
    state $init = !!require MIME::Base64;

    return &MIME::Base64::decode_base64url;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

# BASE85
sub to_b85 {
    state $init = !!require Convert::Ascii85;

    state $args = { compress_zero => 1, compress_space => 1 };

    return Convert::Ascii85::ascii85_encode( $_[0], $args );
}

sub from_b85 {
    state $init = !!require Convert::Ascii85;

    return &Convert::Ascii85::ascii85_decode;    ## no critic qw[Subroutines::ProhibitAmpersandSigils]
}

# URI
sub to_uri {
    if ( ref $_[0] ) {
        return WWW::Form::UrlEncoded::XS::build_urlencoded( blessed $_[0] && $_[0]->isa('Pcore::Util::Hash::Multivalue') ? $_[0]->get_hash : $_[0] );
    }
    else {
        return URI::Escape::XS::encodeURIComponent( $_[0] );
    }
}

# always return scalar string
sub from_uri {
    my %args = (
        encoding => 'UTF-8',
        splice @_, 1,
    );

    state $encodings;

    if ( defined wantarray ) {
        if ( $args{encoding} ) {
            $encodings->{ $args{encoding} } //= Encode::find_encoding( $args{encoding} );

            my $u = URI::Escape::XS::decodeURIComponent( $_[0] );

            eval {    #
                $u = $encodings->{ $args{encoding} }->decode( $u, Encode::FB_CROAK | Encode::LEAVE_SRC );
            };

            utf8::upgrade($u) if $@;

            return $u;
        }
        else {
            return URI::Escape::XS::decodeURIComponent( $_[0] );
        }
    }
    else {
        if ( $args{encoding} ) {
            $encodings->{ $args{encoding} } //= Encode::find_encoding( $args{encoding} );

            my $u = URI::Escape::XS::decodeURIComponent( $_[0] );

            eval {    #
                $u = $encodings->{ $args{encoding} }->decode( $u, Encode::FB_CROAK | Encode::LEAVE_SRC );
            };

            utf8::upgrade($u) if $@;

            $_[0] = $u;
        }
        else {
            $_[0] = URI::Escape::XS::decodeURIComponent( $_[0] );
        }
    }

    return;
}

# always return HashMultivalue
sub from_uri_query {
    my %args = (
        encoding => 'UTF-8',
        splice @_, 1,
    );

    state $encoding = {};

    $encoding->{ $args{encoding} } //= Encode::find_encoding( $args{encoding} ) if $args{encoding};

    my $array = WWW::Form::UrlEncoded::XS::parse_urlencoded_arrayref( $_[0] );

    my $res = P->hash->multivalue;

    my $hash = $res->get_hash;

    for my $pair ( pairs( $array->@* ) ) {
        $pair->[1] = undef if defined $pair->[1] && $pair->[1] eq q[];

        if ( $args{encoding} ) {

            # decode key
            if ( defined $pair->[0] ) {
                eval {    #
                    $pair->[0] = $encoding->{ $args{encoding} }->decode( $pair->[0], Encode::FB_CROAK | Encode::LEAVE_SRC );
                };

                utf8::upgrade( $pair->[0] ) if $@;
            }

            # decode value
            if ( defined $pair->[1] ) {
                eval {    #
                    $pair->[1] = $encoding->{ $args{encoding} }->decode( $pair->[1], Encode::FB_CROAK | Encode::LEAVE_SRC );
                };

                utf8::upgrade( $pair->[1] ) if $@;
            }
        }

        push $hash->{ $pair->[0] }->@*, $pair->[1];
    }

    if ( defined wantarray ) {
        return $res;
    }
    else {
        $_[0] = $res;

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
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 50                   │ * Subroutine "encode_data" with high complexity score (35)                                                     │
## │      │ 255                  │ * Subroutine "decode_data" with high complexity score (33)                                                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 78, 126, 173, 175,   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 363, 403             │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 606, 624, 664, 673   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 247                  │ CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 717                  │ Documentation::RequirePackageMatchesPodName - Pod NAME on line 721 does not match the package declaration      │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Data

=head1 SYNOPSIS

=head1 DESCRIPTION

JSON SERIALIZE

    ascii(1):
    - qq[\xA3] -> \u00A3, upgrded and encoded to UTF-8 character;
    - qq[£]    -> \u00A3, UTF-8 character;
    - qq[ᾥ]    -> \u1FA5, UTF-8 character;

    latin1(1):
    - qq[\xA3] -> qq[\xA3], encoded as bytes;
    - qq[£]    -> qq[\xA3], downgraded and encoded as bytes;
    - qq[ᾥ]    -> \u1FA5, downgrade impossible, encoded as UTF-8 character;

    utf8 - used only when ascii(0) and latin1(0);
    utf8(0) - upgrade scalar, UTF8 on, DO NOT USE, SERIALIZED DATA SHOULD ALWAYS BY WITHOUT UTF8 FLAG!!!!!!!!!!!!!!!!!!;
    - qq[\xA3] -> "£" (UTF8, multi-byte, len = 1, bytes::len = 2);
    - qq[£]    -> "£" (UTF8, multi-byte, len = 1, bytes::len = 2);
    - qq[ᾥ]    -> "ᾥ" (UTF8, multi-byte, len = 1, bytes::len = 3);

    utf8(1) - upgrade, encode scalar, UTF8 off;
    - qq[\xA3] -> "\xC2\xA3" (latin1, bytes::len = 2);
    - qq[£]    -> "\xC2\xA3" (latin1, bytes::len = 2);
    - qq[ᾥ]    -> "\xE1\xBE\xA5" (latin1, bytes::len = 3);

    So,
    - don't use latin1(1);
    - don't use utf8(0);

JSON DESERIALIZE

    utf8(0):
    - qq[\xA3]     -> "£", upgrade;
    - qq[£]        -> "£", as is;
    - qq[\xC2\xA3] -> "Â£", upgrade each byte, invalid;
    - qq[ᾥ]        -> error;

    utf8(1):
    - qq[\xA3]     -> "£", error, can't decode utf8;
    - qq[£]        -> "£", error, can't decode utf8;
    - qq[\xC2\xA3] -> "£", decode utf8;
    - qq[ᾥ]        -> error, can't decode utf8;

    So,
    - if data was encoded with utf8(0) - use utf8(0) to decode;
    - if data was encoded with utf8(1) - use utf8(1) to decode;

=cut
