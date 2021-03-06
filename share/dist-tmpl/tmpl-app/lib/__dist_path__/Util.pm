package <: $module_name ~ "::Util" :>;

use Pcore -class, -res;
use Pcore::API::SMTP;
use <: $module_name ~ "::Const qw[]" :>;

has settings => ( required => 1 );    # HashRef

has _smtp => ( is => 'lazy', init_arg => undef );    # Maybe [ InstanceOf ['Pcore::API::SMTP'] ]

sub BUILD ( $self, $args ) {

    # set settings listener
    P->on(
        'app.api.settings.updated',
        sub ($ev) {
            $self->on_settings_update( $ev->{data} );

            return;
        }
    );

    $self->on_settings_update( $self->{settings} );

    return;
}

sub on_settings_update ( $self, $data ) {
    $self->{settings} = $data;

    delete $self->{_smtp};

    return;
}

# SMTP
sub _build__smtp ($self) {
    my $cfg = $self->{settings};

    return if !$cfg->{smtp_host} || !$cfg->{smtp_port} || !$cfg->{smtp_username} || !$cfg->{smtp_password};

    return Pcore::API::SMTP->new( {
        host     => $cfg->{smtp_host},
        port     => $cfg->{smtp_port},
        username => $cfg->{smtp_username},
        password => $cfg->{smtp_password},
        tls      => $cfg->{smtp_tls},
    } );
}

sub sendmail ( $self, $to, $subject, $body, %args ) {
    my $smtp = $self->_smtp;

    my $res;

    if ( !$smtp ) {
        $res = res [ 500, 'SMTP is not configured' ];
    }
    else {
        $res = $smtp->sendmail(
            from     => $args{from}     || $smtp->{username},
            reply_to => $args{reply_to} || $args{from} || $smtp->{username},
            to      => $to,
            bcc     => $args{bcc},
            subject => $subject,
            body    => $body
        );
    }

    P->sendlog( '<: $dist_name :>.FATAL', 'SMTP error', "$res" ) if !$res;

    return $res;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 1, 5                 | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 70                   | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 77                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 81 does not match the package declaration       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

<: $module_name ~ "::Util" :>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
