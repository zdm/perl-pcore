package Pcore::API::Map::Method;

use Pcore -class;
use Pcore::Util::Text qw[to_camel_case];

has name => ( is => 'ro', isa => StrMatch [qr/\A[[:lower:][:digit:]_]+\z/sm], required => 1 );
has api_map => ( is => 'ro', isa => InstanceOf ['Pcore::API::Map'], required => 1, weak_ref => 1 );

has params => ( is => 'lazy', isa => HashRef [ InstanceOf ['Pcore::API::Map::Param'] ], default => sub { {} }, init_arg => undef );
has params_strict => ( is => 'ro', isa => Bool, default => 1 );    # used only with params, check params on client, dies on unknown params

has use_fields => ( is => 'ro', isa => Enum [ 'id', 'all' ], init_arg => 'fields' );    # method use fields
has fields_strict          => ( is => 'ro', isa => Bool, default => 1 );                       # used only with fields, dies on unknown fields
has write_client_id        => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # require clientd_id in output records
has read_client_id         => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );    # require clientd_id in input records
has check_critical_fields  => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );
has read_persist_rc_fields => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

has public => ( is => 'ro', isa => Bool, default => 0 );
has desc   => ( is => 'ro', isa => Str,  default => q[] );

has readable_fields            => ( is => 'lazy', isa => HashRef, init_arg => undef );
has has_readable_upload_fields => ( is => 'lazy', isa => Bool,    init_arg => undef );

has _can_hook_method => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

sub BUILDARGS {
    my $self = shift;
    my $args = shift;

    if ( exists $args->{fields} ) {
        if ( !$args->{fields} ) {
            delete $args->{fields};
        }
        elsif ( $args->{fields} eq '1' ) {
            $args->{fields} = 'all';
        }
    }

    return $args;
}

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->add_params( $args->{params} ) if $args->{params};

    return;
}

sub add_params {
    my $self   = shift;
    my $params = shift;

    for my $param_cfg ( $params->@* ) {
        my $args->%* = $param_cfg->%*;

        $args->{method} = $self;

        my $class;

        if ( my $type = delete $args->{type} ) {
            $class = to_camel_case( $type, ucfirst => 1 );
        }
        else {
            $class = '+Pcore::API::Map::Param';
        }

        my $param = P->class->load( $class, ns => 'Pcore::API::Map::Param' )->new($args);

        my $param_name = $args->{name} // $param->name;

        die qq[Param name "$param_name" can't be redefined] if $param->name ne $param_name;

        $self->params->{$param_name} = $param;
    }

    return;
}

sub use_params {
    my $self = shift;

    return scalar keys $self->params->%*;
}

sub _build_readable_fields {
    my $self = shift;

    my $fields = {};

    if ( !$self->use_fields ) {
        die q[Method don't use fields];
    }
    else {
        die q[Field "id" must be declared] unless exists $self->api_map->fields->{id};

        $fields->{id} = 1;

        if ( $self->use_fields eq 'all' ) {
            for my $field ( values $self->api_map->fields->%* ) {
                if ( $field->persist_rw || $field->upload ) {
                    $fields->{ $field->name } = 1;
                }
                elsif ( $field->persist_rc && $self->read_persist_rc_fields ) {
                    $fields->{ $field->name } = 1;
                }
            }
        }

        if ( $self->read_client_id ) {
            die q[Field "client_id" must be declared] unless exists $self->api_map->fields->{client_id};

            delete $fields->{id};

            $fields->{client_id} = 1;
        }
    }

    return $fields;
}

sub _build_has_readable_upload_fields {
    my $self = shift;

    return $self->use_fields && $self->use_fields eq 'all' && $self->api_map->has_upload_fields ? 1 : 0;
}

# API MAP GENERATOR
sub generate_api_map {
    my $self = shift;

    die q[Use of "fields" and "params" together is forbidden] if $self->use_params && $self->use_fields;

    die q[Field "client_id" must be declared] if $self->write_client_id && !exists $self->api_map->fields->{client_id};

    my $api_map = { name => $self->name, };

    if ( $self->use_params ) {    # only params used
        $api_map->{params} = [];
        $api_map->{strict} = $self->params_strict ? $TRUE : $FALSE;

        for my $name ( keys $self->params->%* ) {
            my $param_name = $self->params->{$name}->generate_api_map;

            next unless defined $param_name;

            push $api_map->{params}, $param_name;
        }
    }
    elsif ( $self->use_fields ) {
        if ( $self->has_readable_upload_fields ) {    # use fields as params if method has uploads
            $api_map->{formHandler} = $TRUE;
            $api_map->{params}      = [];
            $api_map->{strict}      = $self->fields_strict ? $TRUE : $FALSE;

            for my $field_name ( keys $self->readable_fields->%* ) {
                push $api_map->{params}, $field_name;
            }
        }
        else {
            $api_map->{len} = 1;
        }
    }
    else {
        $api_map->{len} = 0;
    }

    return $api_map;
}

# HOOKS
sub call_hook {
    my $self        = shift;
    my $method_name = shift;

    my $api_class        = $self->api_map->api_class;
    my $real_method_name = 'on_api_' . $self->name . q[_] . $method_name;

    if ( !exists $self->_can_hook_method->{$real_method_name} ) {
        $self->_can_hook_method->{$real_method_name} = $api_class->can($real_method_name) ? 1 : 0;
    }

    if ( $self->_can_hook_method->{$real_method_name} ) {
        return $api_class->$real_method_name(@_);    # method was called
    }
    else {
        return;                                      # method wasn't called
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 59, 87, 104, 146,    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 160                  │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
