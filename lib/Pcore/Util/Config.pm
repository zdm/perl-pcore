package Pcore::Util::Config;

use Pcore;

sub load {
    my $config = shift;    # scalar || scalar ref
    my %args   = (
        ns   => undef,     # load cfg into specified namespace, only for perl configs
        from => undef,     # PERL, JSON, CBOR, YAML, XML, INI
        @_,
    );

    my $from = delete $args{from};

    if ( !ref $config ) {
        if ( !-f $config ) {
            die qq[Config file "$config" wasn't found.];
        }

        if ( !$from ) {
            if ( my ($ext) = $config =~ /[.](json|cbor|yaml|yml|xml|ini)\z/sm ) {
                $from = $ext;

                $from = 'yaml' if $from eq 'yml';
            }
        }

        $config = P->file->read_bin($config);
    }
    else {
        P->text->encode_utf8( $config->$* );
    }

    $from //= 'PERL';

    return P->data->decode( $config, %args, from => uc $from );
}

sub store {
    my $path = shift;
    my $cfg  = shift;
    my %args = (
        to => undef,    # PERL, JSON, CBOR, YAML, XML, INI
        @_,
    );

    my $to = delete $args{to};

    if ( !$to ) {
        if ( my ($ext) = $path =~ /[.](json|cbor|yaml|yml|xml|ini)\z/sm ) {
            $to = $ext;

            $to = 'yaml' if $to eq 'yml';
        }
    }

    $to //= 'PERL';

    P->file->write_bin( $path, P->data->encode( $cfg, %args, to => uc $to ) );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Config

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
