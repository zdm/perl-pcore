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
sub _build_cfg ($self) {
    return $CFG;
}

sub _create_local_cfg ($self) {
    return;
}

sub app_deploy ($self) {
    return;
}

# OPENSSL
sub _build__ca_path ($self) {
    my $path = $self->app->app_dir . 'ca';

    # create CA infrastructure
    P->file->mkpath(qq[$path/private]);
    P->file->mkpath(qq[$path/certs]);
    P->file->mkpath(qq[$path/newcerts]);
    P->file->touch(qq[$path/index.txt]);

    return $path;
}

sub _generate_openssl_conf ( $self, $conf, $_res ) {
    for my $key ( sort { ref $conf->{$a} cmp ref $conf->{$b} } keys $conf->%* ) {
        if ( ref $conf->{$key} eq 'HASH' ) {
            push $_res->@*, qq[[ $key ]\n];

            __SUB__->( $self, $conf->{$key}, $_res );
        }
        else {
            push $_res->@*, qq[$key = $conf->{$key}\n];
        }
    }

    my $temp = P->file->tempfile;

    P->file->write_text( $temp, $_res );

    return $temp;
}

sub is_enabled ($self) {
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
## │      │ 23                   │ * Private subroutine/method '_create_local_cfg' declared but not used                                          │
## │      │ 44                   │ * Private subroutine/method '_generate_openssl_conf' declared but not used                                     │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 45                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX::OpenSSL

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
