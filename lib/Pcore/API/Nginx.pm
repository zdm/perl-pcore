package Pcore::API::Nginx;

use Pcore -class;

has data_dir  => $ENV->{DATA_DIR};
has nginx_bin => 'nginx';

has user => ();    # nginx workers user

has load_balancer_path => '/var/local/nginx/data/nginx/vhost';

has conf_dir  => ( is => 'lazy', init_arg => undef );
has vhost_dir => ( is => 'lazy', init_arg => undef );
has proc => ( init_arg => undef );

eval {
    require Pcore::GeoIP;
    Pcore::GeoIP->import;
};

sub _build_conf_dir ($self) {
    my $conf_dir = "$self->{data_dir}/nginx";

    P->file->mkpath($conf_dir);

    return $conf_dir;
}

sub _build_vhost_dir ($self) {
    my $vhost_dir = $self->conf_dir . '/vhost';

    P->file->mkpath($vhost_dir);

    return $vhost_dir;
}

sub run ($self) {

    # generate mime types
    my $mime_types = $ENV->{share}->read_cfg('data/mime.yaml')->{suffix};

    my $nginx_mime_types;

    for my $suffix ( keys $mime_types->%* ) { $nginx_mime_types->{$suffix} = $mime_types->{$suffix}->[0] }

    my $geoip2_country_path = $ENV->{share}->get('data/geoip2_country.mmdb') || undef;
    my $geoip2_city_path    = $ENV->{share}->get('data/geoip2_city.mmdb')    || undef;

    my $params = {
        user                => $self->{user},
        pid                 => $self->conf_dir . '/nginx.pid',
        error_log           => "$self->{data_dir}/nginx-error.log",
        use_geoip2          => $geoip2_country_path || $geoip2_city_path,
        geoip2_country_path => $geoip2_country_path,
        geoip2_city_path    => $geoip2_city_path,
        vhost_dir           => $self->vhost_dir,
        ssl_dhparam         => $ENV->{share}->get('data/dhparam-4096.pem'),
        mime_types          => $nginx_mime_types,
    };

    # generate conf.nginx
    P->file->write_text( $self->conf_dir . '/conf.nginx', { mode => q[rw-r--r--] }, P->tmpl( type => 'text' )->render( 'nginx/conf.nginx', $params ) );

    # create and prepare unix socket dir
    P->file->mkdir('/var/run/nginx') if !-d '/var/run/nginx';

    # chown $uid, $uid, '/var/run/nginx' or die;

    $self->{proc} = P->sys->run_proc( [ $self->{nginx_bin}, '-c', $self->conf_dir . '/conf.nginx' ] );

    return;
}

sub add_vhost ( $self, $name, $cfg ) {
    P->file->write_bin( $self->vhost_dir . "/$name.nginx", $cfg );

    return;
}

sub is_vhost_exists ( $self, $name ) {
    return -f $self->vhost_dir . "/$name.nginx";
}

# TODO
sub generate_vhost_config ( $self, $name ) {
    my $params = {};

    my $cfg = P->tmpl( type => 'text' )->render( 'nginx/vhost-load-balancer.nginx', $params );

    P->file->write_text( "$self->{load_balancer_path}/$name.nginx", { mode => q[rw-r--r--] }, $cfg );

    return;
}

sub generate_vhost_load_balancer_config ( $self, $name ) {
    my $params = {};

    my $cfg = P->tmpl( type => 'text' )->render( 'nginx/vhost-load-balancer.nginx', $params );

    P->file->write_text( "$self->{load_balancer_path}/$name.nginx", { mode => q[rw-r--r--] }, $cfg );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 16                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Nginx - Pcore nginx application

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

=head1 AUTHOR

zdm <zdm@cpan.org>

=head1 CONTRIBUTORS

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by zdm.

=cut
