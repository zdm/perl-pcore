package Pcore::App::API::Map;

use Pcore -class;
use Pcore::Util::Scalar qw[is_plain_arrayref];
use Package::Stash::XS qw[];

has app    => ();    # ( isa => ConsumerOf ['Pcore::App'], required => 1 );
has method => ();    # ( isa => HashRef, init_arg => undef );
has obj    => ();    # ( isa => HashRef, init_arg => undef );

# TODO https://github.com/OAI/OpenAPI-Specification/blob/master/versions/2.0.md

sub init ($self) {
    my $method = {};

    # read api roles
    my $roles = {
        do {
            no strict qw[refs];

            map { $_ => 1 } ${ ref( $self->{app} ) . '::APP_API_ROLES' }->@*;
          }
    };

    my $ns_path = ( ref( $self->{app} ) =~ s[::][/]smgr ) . '/API';

    my $class;

    # scan %INC
    for my $class_path ( keys %INC ) {

        # API class must be located in V\d+ directory
        next if $class_path !~ m[\A$ns_path/V\d+/]sm;

        # remove .pm suffix
        my $class_name = $class_path =~ s/[.]pm\z//smr;

        $class_name =~ s[/][::]smg;

        $class->{$class_path} = $class_name;
    }

    # scan filesystem namespace, find and preload controllers
    for my $inc ( grep { !ref } @INC ) {
        if ( -d "$inc/$ns_path" ) {
            my $guard = P->file->chdir("$inc/$ns_path");

            P->file->find(
                "$inc/$ns_path",
                abs => 0,
                dir => 0,
                sub ($path) {

                    # .pm file
                    if ( $path->suffix eq 'pm' ) {

                        # API class must be located in V\d+ directory
                        return if $path !~ m[\Av\d+/]sm;

                        my $route = $path->dirname . $path->filename_base;

                        $class->{$route} = "$ns_path/$route" =~ s[/][::]smgr;
                    }

                    return;
                }
            );
        }
    }

    my $MODIFY_CODE_ATTRIBUTES = sub ( $pkg, $ref, @attrs ) {
        my @bad;

        for my $attr (@attrs) {
            if ( $attr =~ /(Perms) [(] ([^)]*) [)]/smxx ) {
                my ( $attr, $val ) = ( $1, $2 );

                if ( $attr eq 'Perms' ) {

                    # parse args
                    my @val = split /\s*,\s*/sm, $val;

                    # dequote
                    for (@val) {s/['"]//smg}

                    $val = \@val;
                }

                no strict qw[refs];

                ${"$pkg\::_API_MAP"}->{$ref}->{ lc $attr } = $val;
            }
            else {
                push @bad, $attr;
            }
        }

        return @bad;
    };

    for my $class_path ( sort keys $class->%* ) {
        my $class_name = $class->{$class_path};

        my $attrs = do {
            no strict qw[refs];

            local *{"$class_name\::MODIFY_CODE_ATTRIBUTES"} = $MODIFY_CODE_ATTRIBUTES;

            P->class->load($class_name);

            ${"$class_name\::_API_MAP"};
        };

        die qq["$class_name" must be an instance of "Pcore::App::API::Base"] if !$class_name->isa('Pcore::App::API::Base');

        # prepare API object route
        $class_path =~ s/\AV/v/sm;

        # create API object and store in cache
        my $obj = $self->{obj}->{$class_name} = $class_name->new( { app => $self->{app} } );

        # parse API version
        my ($version) = $class_path =~ /\Av(\d+)/sm;

        # scan api methods
        for my $method_name ( grep {/\AAPI_/sm} Package::Stash::XS->new($class_name)->list_all_symbols('CODE') ) {

            # get method permissions
            my $perms = do {
                no strict qw[refs];

                my $ref = *{"$class_name\::$method_name"}{CODE};

                $attrs->{$ref}->{perms};
            };

            my $local_method_name = $method_name;

            $method_name =~ s/\AAPI_//sm;

            my $method_id = qq[/$class_path/$method_name];

            $method->{$method_id} = {
                id                => $method_id,
                version           => "v$version",
                class_name        => $class_name,
                class_path        => "/$class_path",
                method_name       => $method_name,
                local_method_name => $local_method_name,
                permissions       => $perms,
            };

            # check method permissions
            if ( $method->{$method_id}->{permissions} ) {

                # methods permissions are empty
                if ( !$method->{$method_id}->{permissions}->@* ) {
                    $method->{$method_id}->{permissions} = undef;
                }

                # check permissions
                else {
                    for my $role ( $method->{$method_id}->{permissions}->@* ) {

                        # expand "*"
                        if ( $role eq q[*] ) {
                            $method->{$method_id}->{permissions} = [ keys $roles->%* ];

                            last;
                        }

                        if ( !exists $roles->{$role} ) {
                            die qq[Invalid API method permission "$role" for method "$method_id"];
                        }
                    }
                }
            }
        }
    }

    $self->{method} = $method;

    return;
}

sub get_method ( $self, $method_id ) {
    return $self->{method}->{$method_id};
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 13                   | Subroutines::ProhibitExcessComplexity - Subroutine "init" with high complexity score (21)                      |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 166, 172             | ControlStructures::ProhibitDeepNests - Code structure is deeply nested                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Map

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
