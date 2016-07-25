package Pcore::API::Server;

use Pcore -class;
use Pcore::API::Response;
use Pcore::API::Server::Hash;
use Pcore::Util::Hash::RandKey;
use Pcore::API::Server::Auth;

has namespace       => ( is => 'ro', isa => Str,         required => 1 );
has default_version => ( is => 'ro', isa => PositiveInt, required => 1 );

has dbh => ( is => 'lazy', isa => ConsumerOf ['Pcore::DBH'], init_arg => undef );
has map => ( is => 'ro', isa => HashRef, init_arg => undef );
has _hash_rpc => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );

# TODO scan API classes
sub BUILD ( $self, $args ) {
    my $ns_path = $self->namespace =~ s[::][/]smgr;

    my $controllers = {};

    # scan namespace, find and preload controllers
    for my $path ( grep { !ref } @INC ) {
        if ( -d "$path/$ns_path" ) {
            my $guard = P->file->chdir("$path/$ns_path");

            P->file->find(
                "$path/$ns_path",
                abs => 0,
                dir => 0,
                sub ($path) {
                    if ( $path->suffix eq 'pm' ) {
                        my $route = $path->dirname . $path->filename_base;

                        my $class = "$ns_path/$route" =~ s[/][::]smgr;

                        $controllers->{$class} = '/' . P->text->to_snake_case( $route, delim => '-', split => '/', join => '/' ) . '/';
                    }

                    return;
                }
            );
        }
    }

    $self->{map} = {};

    for my $class ( sort keys $controllers->%* ) {
        P->class->load($class);

        my $path = $controllers->{$class};

        if ( !$class->does('Pcore::API::Server::Class') ) {
            delete $controllers->{$class};

            say qq["$class" is not a consumer of "Pcore::API::Server::Class"];

            next;
        }

        my $version;

        if ( $path =~ s[\A/v(\d+)][]sm ) {
            $version = $1;
        }
        else {
            say qq[Can not determine API version "$class"];

            next;
        }

        my $obj = bless { api => $self }, $class;

        my $map = $obj->map;

        $self->{map}->{$version}->{$path} = {
            class  => $class,
            method => $map,
        };
    }

    # TODO check default version

    say dump $self->{map};

    return;
}

sub _build_dbh ($self) {
    my $dbh = P->handle('sqlite:auth.sqlite');

    # create db
    my $ddl = $dbh->ddl;

    $ddl->add_changeset(
        id  => 1,
        sql => <<"SQL"
            CREATE TABLE IF NOT EXISTS `user` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `username` TEXT NOT NULL UNIQUE,
                `password` TEXT NOT NULL,
                `enabled` INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS `token` (
                `id` BLOB PRIMARY KEY NOT NULL,
                `token` TEXT NOT NULL,
                `uid` INTEGER NOT NULL,
                `enabled` INTEGER NOT NULL
            );
SQL
    );

    $ddl->upgrade;

    return $dbh;
}

sub _build__hash_rpc($self) {
    return P->pm->run_rpc(
        'Pcore::API::Server::Hash',
        workers   => 1,
        buildargs => {
            scrypt_N   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );
}

# TODO return authenticated api object on success
sub auth_password ( $self, $username, $password, $cb ) {
    state $q1 = $self->dbh->query('SELECT * FROM user WHERE username = ?');

    if ( my $user = $q1->selectrow( [$username] ) ) {
        $self->_verify_hash(
            $password,
            $user->{password},
            sub ($match) {
                if ($match) {
                    $cb->( Pcore::API::Server::Auth->new( { uid => $user->{id}, auth => 1 } ) );
                }
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }
    else {
        $cb->(undef);
    }

    return;
}

# TODO check b64 decode and length
# TODO return authenticated api object on success
sub auth_token ( $self, $token_b64, $cb ) {
    state $q1 = $self->dbh->query('SELECT * FROM token WHERE id = ?');

    # TODO check, that decoded
    my $token_raw = P->data->from_b64_url($token_b64);

    my $token_id = substr $token_raw, 0, 16, q[];

    if ( my $token = $q1->selectrow( [$token_id] ) ) {
        $self->_verify_hash(
            $token_raw,
            $token->{token},
            sub ($match) {
                if ($match) {
                    $cb->( Pcore::API::Server::Auth->new( { uid => $token->{uid}, auth => 1 } ) );
                }
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }
    else {
        $cb->(undef);
    }

    return;
}

# TODO implement cache size
sub _verify_hash ( $self, $str, $hash, $cb ) {
    $str = P->text->encode_utf8($str);

    my $id = $str . $hash;

    if ( exists $self->{_hash_cache}->{$id} ) {
        $cb->(1);
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_scrypt',
            [ $str, $hash ],
            sub ($match) {
                $self->{_hash_cache}->{$id} = undef;

                $cb->($match);

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
## |    3 | 49                   | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 38                   | ValuesAndExpressions::ProhibitNoisyQuotes - Quotes used with a noisy string                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
