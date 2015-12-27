package Pcore::Util::Data;

use Pcore -export, [qw[to_b64]];
use Sort::Naturally qw[nsort];
use Scalar::Util qw[blessed];    ## no critic qw[Modules::ProhibitEvilModules]
use URI::Escape::XS qw[];        ## no critic qw[Modules::ProhibitEvilModules]
use WWW::Form::UrlEncoded::XS qw[];
use Pcore::Util::Text qw[decode_utf8 encode_utf8 escape_scalar];

our $TOKEN = {
    serializer => {
        PERL => 1,
        JSON => 2,
        CBOR => 3,
        YAML => 4,
        XML  => 5,
        INI  => 5,
    },
    compressor => { 'Compress::Zlib' => 1, },
    cipher     => { DES              => 1, },
    portable   => {
        b64 => 1,
        hex => 2,
    },
};

our $JSON_CACHE;

# JSON is used by default
# JSON can't serialize ScalarRefs
# objects should have TO_JSON method, otherwise object will be serialized as null
# base64 encoder is used by default, it generates more compressed data
sub encode {
    my $data = shift;
    my %args = (
        to                 => 'JSON',              # PERL, JSON, CBOR, YAML, XML, INI
        readable           => undef,               # make serialized data readable for humans
        compresss          => undef,               # use compression
        secret             => undef,               # crypt data if defined, can be ArrayRef
        secret_index       => 0,                   # index of secret to use in secret array, if secret is ArrayRef
        portable           => undef,               # 0 - disable, 1 - 'b64', 'b64', 'hex', make data portable
        token              => undef,               # attach informational token
        compress_threshold => 100,                 # min data length in bytes to perform compression, only if compress = 1
        compressor         => 'Compress::Zlib',    # compressor to use
        cipher             => 'DES',               # cipher to use
        @_,
    );

    if ( $args{readable} && $args{to} ne 'CBOR' ) {
        $args{compress} = undef;
        $args{secret}   = undef;
        $args{portable} = undef;
        $args{token}    = undef;
    }

    my $res;

    # encode
    if ( $args{to} eq 'PERL' ) {
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
    elsif ( $args{to} eq 'JSON' ) {
        if ( $args{readable} ) {
            $res = \to_json( $data, cache => 'serializer_readable', ascii => 0, latin1 => 0, utf8 => 1, pretty => 1 );
        }
        else {
            $res = \to_json( $data, cache => 'serializer_portable', ascii => 1, latin1 => 0, utf8 => 1, pretty => 0 );
        }
    }
    elsif ( $args{to} eq 'CBOR' ) {
        $res = \_get_cbor_obj->encode($data);
    }
    elsif ( $args{to} eq 'YAML' ) {
        state $init = !!require YAML::XS;

        local $YAML::XS::UseCode = 0;

        local $YAML::XS::DumpCode = 0;

        local $YAML::XS::LoadCode = 0;

        $res = \YAML::XS::Dump($data);
    }
    elsif ( $args{to} eq 'XML' ) {
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
    elsif ( $args{to} eq 'INI' ) {
        state $init = !!require Config::INI::Writer;

        $res = \Config::INI::Writer->write_string($data);
    }
    else {
        die qq[Unknown serializer "$args{to}"];
    }

    # compress
    if ( $args{compress} ) {
        if ( length $res->$* >= $args{compress_threshold} ) {
            if ( $args{compressor} eq 'Compress::Zlib' ) {
                state $init = !!require Compress::Zlib;

                $res = \Compress::Zlib::compress( $res->$* );
            }
            else {
                die qq[Unknown compressor "$args{compressor}"];
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
                -cipher => $args{cipher},
            )->encrypt( $res->$* );
        }
    }

    # encode
    if ( $args{portable} ) {
        $args{portable} = 'b64' if $args{portable} eq '1';

        if ( $args{portable} eq 'b64' ) {
            $res = \P->data->to_b64_url( $res->$* );
        }
        elsif ( $args{portable} eq 'hex' ) {
            $res = \unpack 'H*', $res->$*;
        }
        else {
            die qq[Unknown encoder "$args{portable}"];
        }
    }

    # create token
    if ( $args{token} ) {
        my $token = unpack 'H*', pack 'Q>', bytes::length $res->$*;

        $token .= $TOKEN->{serializer}->{ $args{to} };

        $token .= $args{compress} ? $TOKEN->{compressor}->{ $args{compressor} } : 0;

        $token .= $args{secret} ? $TOKEN->{cipher}->{ $args{cipher} } : 0;

        $token .= $args{secret_index} // 0;

        $token .= $args{portable} ? $TOKEN->{portable}->{ $args{portable} } : 0;

        $res = \( $token . $res->$* );
    }

    return $res;
}

# JSON data should be without UTF8 flag
# objects isn't deserialized automatically from JSON
sub decode {
    my $data_ref = ref $_[0] ? shift : \shift;

    my %args = (
        token        => 0,                  # perform deserialization only if token was found, otherwise return undef
        from         => 'JSON',             # PERL, JSON, CBOR, YAML, XML, INI
        compresss    => undef,
        compressor   => 'Compress::Zlib',
        secret       => undef,              # can be ArrayRef
        secret_index => 0,
        cipher       => 'DES',
        portable     => undef,              # 0, 1 = 'hex', 'hex', 'b64'
        json_utf8    => 1,                  # only for JSON data
        ns           => undef,              # for PERL only, namespace for data evaluation
        @_,
    );

    # parse token
    if ( $args{token} ) {
        if ( my $token = _parse_token($data_ref) ) {
            P->hash->merge( \%args, $token );

            # cut token from data
            $data_ref = \substr $data_ref->$*, 21;
        }
        else {    # token wasn't found
            return;
        }
    }

    # decode
    if ( $args{portable} ) {
        $args{portable} = 'b64' if $args{portable} eq '1';

        if ( $args{portable} eq 'b64' ) {
            $data_ref = \from_b64_url( $data_ref->$* );
        }
        elsif ( $args{portable} eq 'hex' ) {
            $data_ref = \pack 'H*', $data_ref->$*;
        }
        else {
            die qq[Unknown encoder "$args{portable}"];
        }
    }

    # decrypt
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

            $data_ref = \Crypt::CBC->new(
                -key    => $secret,
                -cipher => $args{cipher},
            )->decrypt( $data_ref->$* );

        }
    }

    # decompress
    if ( $args{compress} ) {
        if ( $args{compressor} eq 'Compress::Zlib' ) {
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

    if ( $args{from} eq 'PERL' ) {
        my $ns = $args{ns} || '_Pcore::CONFIG::SANDBOX';

        decode_utf8 $data_ref->$*;

        ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
        $res = eval <<"CODE";
package $ns;
use Pcore -config;
no warnings qw[redefine];
local *i18n = sub { return Pcore::Util::Data::_I18N->new( { args => [ \@_ ] } ) };
$data_ref->$*
CODE
        die $@ if $@;

        die q[Config must return value] unless $res;
    }
    elsif ( $args{from} eq 'JSON' ) {
        $res = from_json( $data_ref->$*, cache => 'deserializer_utf8_' . $args{json_utf8}, utf8 => $args{json_utf8} );
    }
    elsif ( $args{from} eq 'CBOR' ) {
        $res = _get_cbor_obj->decode( $data_ref->$* );
    }
    elsif ( $args{from} eq 'YAML' ) {
        state $init = !!require YAML::XS;

        local $YAML::XS::UseCode = 0;

        local $YAML::XS::DumpCode = 0;

        local $YAML::XS::LoadCode = 0;

        $res = YAML::XS::Load( $data_ref->$* );
    }
    elsif ( $args{from} eq 'XML' ) {
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
    elsif ( $args{from} eq 'INI' ) {
        state $init = !!require Config::INI::Reader;

        $res = Config::INI::Reader->read_string( $data_ref->$* );
    }
    else {
        die qq[Unknown serializer "$args{from}"];
    }

    if ( wantarray && $args{token} ) {
        return $res, \%args;
    }
    else {
        return $res;
    }
}

sub _parse_token {
    my $data_ref = shift;

    state $reversed_token;

    if ( !$reversed_token ) {
        $reversed_token->{serializer} = { reverse $TOKEN->{serializer}->%* };

        $reversed_token->{compressor} = { reverse $TOKEN->{compressor}->%* };

        $reversed_token->{cipher} = { reverse $TOKEN->{cipher}->%* };

        $reversed_token->{portable} = { reverse $TOKEN->{portable}->%* };
    }

    my $args;

    my $data_len = bytes::length $data_ref->$*;

    return if $data_len <= 21;

    my $expected_data_len = unpack 'Q>', pack 'H*', substr $data_ref->$*, 0, 16;

    return if $expected_data_len != $data_len - 21;

    if ( ( $args->{from}, $args->{compress}, $args->{cipher}, $args->{secret_index}, $args->{portable} ) = split //sm, substr $data_ref->$*, 16, 5 ) {

        # serializer
        if ( exists $reversed_token->{serializer}->{ $args->{from} } ) {
            $args->{from} = $reversed_token->{serializer}->{ $args->{from} };
        }
        else {
            return;
        }

        # compressor
        if ( $args->{compress} ) {
            if ( exists $reversed_token->{compressor}->{ $args->{compress} } ) {
                $args->{compressor} = $reversed_token->{compressor}->{ $args->{compress} };
            }
            else {
                return;
            }
        }

        # cipher
        if ( $args->{cipher} ) {
            if ( exists $reversed_token->{cipher}->{ $args->{cipher} } ) {
                $args->{cipher} = $reversed_token->{cipher}->{ $args->{cipher} };
            }
            else {
                return;
            }
        }

        # portable
        if ( $args->{portable} ) {
            if ( exists $reversed_token->{portable}->{ $args->{portable} } ) {
                $args->{portable} = $reversed_token->{portable}->{ $args->{portable} };
            }
            else {
                return;
            }
        }

        return $args;
    }
    else {
        return;
    }
}

# PERL
sub to_perl {
    return encode( @_, to => 'PERL' );
}

sub from_perl {
    return decode( @_, from => 'PERL' );
}

# JSON
sub to_json {
    my $data = shift;
    my %args = (
        cache => undef,    # cache id, get JSON object from cache

        ascii  => 1,
        latin1 => 0,
        utf8   => 1,

        pretty => 0,       # set indent, space_before, space_after

        # indent       => 0,
        # space_before => 0,    # put a space before the ":" separating key from values
        # space_after  => 0,    # put a space after the ":" separating key from values, and after "," separating key-value pairs

        canonical       => 0,    # sort hash keys, slow
        allow_nonref    => 1,    # allow scalars
        allow_unknown   => 0,    # trow exception if can't encode item
        allow_blessed   => 1,    # allow blessed objects
        convert_blessed => 1,    # use TO_JSON method of blessed objects
        allow_tags      => 0,    # use FREEZE / THAW, we don't use this, because non-standard JSON will be generated, use CBOR instead to serialize objects

        # shrink          => 0,
        # max_depth       => 512,

        @_,
    );

    state $init = !!require JSON::XS;

    # create and configure JSON serializer object
    my $json;

    my $cache = delete $args{cache};

    if ( $cache && $JSON_CACHE->{$cache} ) {
        $json = $JSON_CACHE->{$cache};
    }
    else {
        $json = JSON::XS->new;

        for ( keys %args ) {
            $json->$_( $args{$_} );
        }

        $JSON_CACHE->{$cache} = $json if $cache;
    }

    my $res = $json->encode($data);

    return $res;
}

sub from_json {
    my $data = shift;
    my %args = (
        cache => undef,    # cache id, get object from cache

        utf8 => 1,

        relaxed      => 1,    # allows commas and # - style comments
        allow_nonref => 1,
        allow_tags   => 0,    # use FREEZE / THAW

        # filter_json_object            => undef,
        # filter_json_single_key_object => undef,
        # shrink                        => 0,
        # max_depth                     => 512,
        # max_size                      => 0,
        @_,
    );

    state $init = !!require JSON::XS;

    # create and configure JSON deserializer object
    my $json;
    my $cache = delete $args{cache};
    if ( $cache && $JSON_CACHE->{$cache} ) {
        $json = $JSON_CACHE->{$cache};
    }
    else {
        $json = JSON::XS->new;

        for ( keys %args ) {
            $json->$_( $args{$_} );
        }

        $JSON_CACHE->{$cache} = $json if $cache;
    }

    return wantarray ? $json->decode_prefix($data) : $json->decode($data);
}

# CBOR
sub _get_cbor_obj {
    state $cbor = do {    # create and cache CBOR object
        require CBOR::XS;

        my $cbor1 = CBOR::XS->new;

        $cbor1->max_depth(512);
        $cbor1->max_size(0);    # max. string size is unlimited
        $cbor1->allow_unknown(0);
        $cbor1->allow_sharing(1);
        $cbor1->allow_cycles(1);
        $cbor1->pack_strings(1);
        $cbor1->validate_utf8(0);
        $cbor1->filter(undef);

        $cbor1;
    };

    return $cbor;
}

sub to_cbor {
    return encode( @_, to => 'CBOR' );
}

sub from_cbor {
    return decode( @_, from => 'CBOR' );
}

# YAML
sub to_yaml {
    return encode( @_, to => 'YAML' );
}

sub from_yaml {
    return decode( @_, from => 'YAML' );
}

# XML
sub to_xml {
    return encode( @_, to => 'XML' );
}

sub from_xml {
    return decode( @_, from => 'XML' );
}

# INI
sub to_ini {
    return encode( @_, to => 'INI' );
}

sub from_ini {
    return decode( @_, from => 'INI' );
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
        splice( @_, 1 ),
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
        splice( @_, 1 ),
    );

    state $encoding = {};

    $encoding->{ $args{encoding} } //= Encode::find_encoding( $args{encoding} ) if $args{encoding};

    my $array = WWW::Form::UrlEncoded::XS::parse_urlencoded_arrayref( $_[0] );

    my $res = P->hash->multivalue;

    my $hash = $res->get_hash;

    for my $pair ( P->list->pairs( $array->@* ) ) {
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

package Pcore::Util::Data::_I18N;

use Pcore -class;

use overload    #
  q[""] => sub {
    return i18n( $_[0]->args->@* );
  },
  fallback => undef;

has args => ( is => 'ro', isa => ArrayRef, required => 1 );

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitExcessComplexity                                                                          │
## │      │ 33                   │ * Subroutine "encode" with high complexity score (35)                                                          │
## │      │ 239                  │ * Subroutine "decode" with high complexity score (31)                                                          │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 63, 149, 151, 371,   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 398, 400, 402, 404   │                                                                                                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 568                  │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_get_cbor_obj' declared but not     │
## │      │                      │ used                                                                                                           │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 674, 692, 732, 741   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
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
