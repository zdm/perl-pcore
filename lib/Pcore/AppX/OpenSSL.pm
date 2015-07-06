package Pcore::AppX::OpenSSL;

use Pcore qw[-class];

# openssl help - http://pro-ldap.ru/tr/zytrax/tech/ssl.html

with qw[Pcore::AppX];

has _ca_path => ( is => 'lazy', isa => Str, init_arg => undef );

my $CFG = {
    pkey_alg    => 'rsa',
    pkey_bits   => 2048,
    ca_days     => 1095,
    dh_key_bits => 4096
};

# APPX
sub _build_cfg {
    my $self = shift;

    return $CFG;
}

sub _create_local_cfg {
    my $self = shift;

    return;
}

sub app_deploy {
    my $self = shift;

    return;
}

# OPENSSL
sub _build__ca_path {
    my $self = shift;

    my $path = $self->app->app_dir . 'ca';

    # create CA infrastructure
    P->file->mkpath(qq[$path/private]);
    P->file->mkpath(qq[$path/certs]);
    P->file->mkpath(qq[$path/newcerts]);
    P->file->touch(qq[$path/index.txt]);

    return $path;
}

sub _generate_openssl_conf {
    my $self = shift;
    my $conf = shift;
    my $_res = shift;

    for my $key ( sort { ref $conf->{$a} cmp ref $conf->{$b} } keys %{$conf} ) {
        if ( ref $conf->{$key} eq 'HASH' ) {
            push @{$_res}, qq[[ $key ]\n];
            __SUB__->( $self, $conf->{$key}, $_res );
        }
        else {
            push @{$_res}, qq[$key = $conf->{$key}\n];
        }
    }

    my $temp = P->file->tempfile;
    P->file->write_text( $temp, $_res );

    return $temp;
}

sub is_enabled {
    my $self = shift;

    return 1;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 25                   │ * Private subroutine/method '_create_local_cfg' declared but not used                                          │
## │      │ 52                   │ * Private subroutine/method '_generate_openssl_conf' declared but not used                                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
