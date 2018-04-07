package <: $module_name ~ "::Util" :>;

use Pcore -class, -result;
use Pcore::SMTP;
use <: $module_name ~ "::Const qw[:CONST]" :>;

has tmpl => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Template'], init_arg => undef );
has dbh  => ( is => 'ro', isa => ConsumerOf ['Pcore::Handle::DBI'],    init_arg => undef );
has settings => ( is => 'ro', isa => HashRef, init_arg => undef );

has _smtp => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::SMTP'] ], init_arg => undef );

sub BUILD ( $self, $args ) {

    # init tmpl
    $self->{tmpl} = P->tmpl;

    # set settings listener
    P->listen_events(
        'APP.SETTINGS_UPDATED',
        sub ($ev) {
            $self->{settings} = $ev->{data};

            delete $self->{_smtp};

            return;
        }
    );

    return;
}

# DBH
sub build_dbh ( $self, $db ) {
    $self->{dbh} = P->handle($db) if !defined $self->{dbh};

    return $self->{dbh};
}

# TODO
sub update_schema ( $self, $db, $cb ) {
    my $dbh = $self->build_dbh($db);

    $dbh->add_schema_patch(
        1 => <<'SQL'
            CREATE EXTENSION IF NOT EXISTS "pgcrypto";

            CREATE TABLE IF NOT EXISTS "settings" (
                "id" INT2 PRIMARY KEY NOT NULL,

                -- reCaptcha
                "recaptcha_secret_key" VARCHAR,
                "recaptcha_site_key" VARCHAR,
                "recaptcha_enabled" BOOL NOT NULL DEFAULT FALSE,

                -- SMTP
                "smtp_host" VARCHAR,
                "smtp_port" INT2,
                "smtp_username" VARCHAR,
                "smtp_password" VARCHAR,
                "smtp_ssl" BOOL NOT NULL DEFAULT FALSE
            );

            INSERT INTO "settings" ("id", "smtp_host", "smtp_port", "smtp_ssl") VALUES (1, 'smtp.gmail.com', 465, TRUE);

            CREATE TABLE IF NOT EXISTS "user" (
                "id" UUID PRIMARY KEY NOT NULL,
                "name" VARCHAR NOT NULL UNIQUE,
                "enabled" BOOL NOT NULL DEFAULT TRUE,
                "created" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                "email" VARCHAR NOT NULL UNIQUE,
                "email_confirmed" BOOL NOT NULL DEFAULT FALSE
            );

            CREATE TABLE "user_action_token" (
                "token" VARCHAR(64) PRIMARY KEY,
                "user_id" UUID NOT NULL,
                "token_type" INT2 NOT NULL,
                "created" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                "email" VARCHAR NOT NULL
            );

            CREATE TABLE "log" (
                "id" UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
                "created" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                "channel" TEXT,
                "level" TEXT,
                "title" TEXT,
                "data" TEXT
            );
SQL
    );

    $dbh->upgrade_schema($cb);

    return;
}

# SETTINGS
sub load_settings ( $self, $cb ) {
    $self->{dbh}->selectrow(
        q[SELECT * FROM "settings" WHERE "id" = 1],
        sub ( $dbh, $res, $data ) {
            P->fire_event( 'APP.SETTINGS_UPDATED', $data ) if $res;

            $cb->($res);

            return;
        }
    );

    return;
}

sub update_settings ( $self, $settings, $cb ) {

    # check SMTP port
    if ( exists $settings->{smtp_port} && $settings->{smtp_port} !~ /\A\d+\z/sm ) {
        $cb->( result 400, error => { smtp_port => 'Port is invalid' } );

        return;
    }

    $self->{dbh}->do(
        [ q[UPDATE "settings"], SET($settings), 'WHERE "id" = 1' ],
        sub ( $dbh, $status, $data ) {
            if ( !$status ) {
                $cb->( result 500 );
            }
            else {
                $self->load_settings( sub ($res) {
                    $cb->($res);

                    return;
                } );
            }

            return;
        }
    );

    return;
}

# SMTP
sub _build__smtp ($self) {
    my $cfg = $self->{settings};

    return if !$cfg->{smtp_host} || !$cfg->{smtp_port} || !$cfg->{smtp_username} || !$cfg->{smtp_password};

    return Pcore::SMTP->new( {
        host     => $cfg->{smtp_host},
        port     => $cfg->{smtp_port},
        username => $cfg->{smtp_username},
        password => $cfg->{smtp_password},
        tls      => $cfg->{smtp_ssl},
    } );
}

sub sendmail ( $self, $to, $bcc, $subject, $body, $cb = undef ) {
    my $smtp = $self->_smtp;

    if ( !$smtp ) {
        my $res = result [ 500, 'SMTP is not configured' ];

        P->sendlog( '<: $dist_name :>.FATAL', 'SMTP error', "$res" );

        $cb->($res) if $cb;
    }
    else {
        $smtp->sendmail(
            from     => $smtp->{username},
            reply_to => $smtp->{username},
            to       => $to,
            bcc      => $bcc,
            subject  => $subject,
            body     => $body,
            sub ($res) {
                P->sendlog( '<: $dist_name :>.FATAL', 'SMTP error', "$res" ) if !$res;

                $cb->($res) if $cb;

                return;
            }
        );
    }

    return;
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
## |    3 | 160                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 166, 179             | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 209                  | Documentation::RequirePackageMatchesPodName - Pod NAME on line 213 does not match the package declaration      |
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
