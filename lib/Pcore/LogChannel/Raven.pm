package Pcore::LogChannel::Raven;

use Pcore -class;

with qw[Pcore::Core::Log::Channel];

has '+stream'   => ( required => 1 );                                                                  # <SCHEME>://<PUBLIC_KEY>:<PRIVATE_KEY><HOST[:<PORT>]>/<PROJECT_ID>
has '+header'   => ( default  => q[] );
has '+priority' => ( default  => 4 );
has timeout     => ( is       => 'rw', isa => Int, default => 1 );
has _ua         => ( is       => 'lazy', isa => InstanceOf ['Pcore::Util::UA'], init_arg => undef );
has _sentry_url         => ( is => 'rwp', isa => Str, init_arg => undef );
has _sentry_public_key  => ( is => 'rwp', isa => Str, init_arg => undef );
has _sentry_private_key => ( is => 'rwp', isa => Str, init_arg => undef );

our $SENTRY_VERSION = 4;

sub _build__ua {
    my $self = shift;

    my $ua = P->ua->new( { timeout => $self->timeout } );

    my $u = P->uri( $self->stream );

    $self->_set__sentry_url( $u->scheme . '://' . $u->host_port . '/api' . $u->path . '/store/' );

    my ( $pub, $priv ) = split /:/sm, $u->userinfo;

    $self->_set__sentry_public_key($pub);

    $self->_set__sentry_private_key($priv);

    return $ua;
}

sub send_log {
    my $self = shift;
    my %args = @_;

    for my $i ( 0 .. $#{ $args{data} } ) {
        my $res = $self->_ua->post(
            $self->_sentry_url,
            $self->_build_message(
                {   message => $args{data}->[$i],
                    level   => lc $args{level},
                    tags    => {
                        namespace    => $args{ns},
                        script_name  => $ENV->{SCRIPT_NAME},
                        script_dir   => $ENV->{SCRIPT_DIR},
                        script_path  => $ENV->{SCRIPT_PATH},
                        process_name => $ENV->{SERVICE_NAME} || q[],
                        %{ $args{tags} }
                    },
                }
            ),
            'X-Sentry-Auth' => "Sentry sentry_version=$SENTRY_VERSION, sentry_client=perl_client/0.01, sentry_timestamp=" . time() . ', sentry_key=' . $self->_sentry_public_key . ', sentry_secret=' . $self->_sentry_private_key,
        );

        return 0 unless $res->is_success;
    }

    return 1;
}

sub _build_message {
    my ( $self, $params ) = @_;

    my $data = {
        'event_id'    => P->uuid->str,
        'message'     => $params->{'message'},
        'timestamp'   => time(),
        'level'       => $params->{'level'} || 'error',
        'logger'      => $params->{'logger'} || 'root',
        'platform'    => $params->{'platform'} || 'perl',
        'culprit'     => $params->{'culprit'} || q[],
        'tags'        => $params->{'tags'} || [],
        'server_name' => $params->{server_name} || P->sys->hostname,
        'modules'     => $params->{'modules'},
        'extra'       => $params->{'extra'} || {}
    };

    return P->data->encode( $data, compress => 1, portable => 1 );
}

1;
__END__
=pod

=encoding utf8

=cut
