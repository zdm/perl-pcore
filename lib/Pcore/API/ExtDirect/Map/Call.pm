package Pcore::API::Map::Call;

use Pcore qw[-class];
use Pcore::API::Map::Records;

has action => ( is => 'ro', isa => InstanceOf ['Pcore::API::Call::Action::Request'], required => 1, weak_ref => 1 );
has api_class => ( is => 'ro', isa => ConsumerOf ['Pcore::API::Class'], required => 1, weak_ref => 1 );

has api_map => ( is => 'lazy', isa => InstanceOf ['Pcore::API::Map'],         init_arg => undef, weak_ref => 1 );
has method  => ( is => 'lazy', isa => InstanceOf ['Pcore::API::Map::Method'], init_arg => undef, weak_ref => 1 );

has params => ( is => 'lazy', isa => HashRef [ InstanceOf ['Pcore::API::Map::Param'] ], init_arg => undef );
has records => ( is => 'lazy', isa => InstanceOf ['Pcore::API::Map::Records'], init_arg => undef );

has env_is_devel => ( is => 'lazy', isa => Bool, init_arg => undef );
has _exception_data => ( is => 'rwp', isa => HashRef, predicate => 1, init_arg => undef );

has cache => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );    # cache for various internal usage

has writable_fields => ( is => 'lazy', isa => ArrayRef, init_arg => undef );                # fieds, that can be writed in current API call
has persist_fields  => ( is => 'lazy', isa => ArrayRef, init_arg => undef );                # persist fields, used to retrive only needed fields from DB

our $INPUT_FIELDS_TYPE = ArrayRef [HashRef];

no Pcore;

sub BUILD {
    my $self = shift;

    $self->api_class->_set__call($self);

    return;
}

# ACCESSORS
sub _build_api_map {
    my $self = shift;

    return $self->api_class->_api_map;
}

sub _build_method {
    my $self = shift;

    return $self->api_map->methods->{ $self->action->method };
}

sub _build_env_is_devel {
    my $self = shift;

    return $self->api_class->backend->app->env_is_devel;
}

# PARAMS
sub _build_params {
    my $self = shift;

    die q[Method don't use params] if !$self->method->use_params;

    my $raw_params         = $self->_get_raw_params;
    my $method_params      = $self->method->params;
    my $params             = {};
    my $params_strict_keys = $self->method->params_strict ? { map { $_ => 1 } keys $raw_params->%* } : {};

    for my $param_name ( keys $method_params->%* ) {
        my $param = $method_params->{$param_name};

        # mark param as allowed
        delete $params_strict_keys->@{ $param_name, $param->alias_name };    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

        my $val;

        # try to find param value in raw_params by name or alias_name
        if ( exists $raw_params->{$param_name} ) {
            $val = \$raw_params->{$param_name};
        }
        elsif ( exists $raw_params->{ $param->alias_name } ) {
            $val = \$raw_params->{ $param->alias_name };
        }

        # throw exception if critical param wasn't found
        return $self->exception(qq[Param "$param_name" is required]) if !$val && $param->critical;

        try {
            my $param_obj = $param->read_param( $val, $self );

            $params->{$param_name} = $param_obj if defined $param_obj;
        }
        catch {
            my $e = shift;

            if ( !$e->propagated ) {
                $e->propagate;
            }
            elsif ( $e->is_propagated('API::EXCEPTION') ) {
                $self->_exception_data->{message} = qq[Param "$param_name" read error. ] . $self->_exception_data->{message};
            }
        };
    }

    # validate params_strict condition
    $self->call->exception( q[Call has unrecognized params: ] . join q[, ], map {qq["$_"]} keys $params_strict_keys->%* ) if keys $params_strict_keys->%*;

    return $params;
}

sub _get_raw_params {
    my $self = shift;

    $self->_validate_action_data;

    my $data = $self->action->has_data ? $self->action->data : {};

    $self->exception(q[Method require hash of params]) if ref $data ne 'HASH';

    return $data;
}

# RECORDS
sub _build_records {
    my $self = shift;

    my $records = Pcore::API::Map::Records->new( { call => $self } );

    $records->add_in_records( $self->_get_raw_records, $self->action->uploads ) if $self->method->use_fields;

    return $records;
}

sub _get_raw_records {
    my $self = shift;

    $self->_validate_action_data;

    my $action = $self->action;
    my $method = $self->method;

    $self->exception(q[Method require data]) if !$action->has_data;

    my $data;

    if ( ref $action->data eq 'HASH' ) {
        $data = [ $action->data ];    # single row can be passed as hash
    }
    elsif ( ref $action->data eq 'ARRAY' ) {
        $data = ref $action->data->[0] eq 'ARRAY' ? $action->data->[0] : $action->data;    # unpack extjs data [ [ data ], ..]

        if ( $method->use_fields eq 'id' && ref $data->[0] ne 'HASH' ) {                   # allow to pass id's as ArrayRef if method use id field only
            for ( $data->@* ) {
                $_ = { id => $_ };
            }
        }
    }
    else {
        $self->exception(q[Unsupported data format]);
    }

    $self->exception(q[Data should not be empty]) if !$data->@*;

    $self->exception(q[Can't use upload fields with batch operation]) if $data->@* > 1 && $action->has_uploads;

    $self->exception(q[Data should be an array of hashes]) if !$INPUT_FIELDS_TYPE->check($data);

    return $data;
}

# fields, that can be writed back to client in current API call
sub _build_writable_fields {
    my $self = shift;

    my $writable_fields;

    if ( $self->method->use_params ) {
        if ( exists $self->params->{id} ) {
            $writable_fields = $self->api_map->writable_fields;    # all API map writable fields
        }
        elsif ( exists $self->params->{fields} ) {
            $writable_fields->%* = $self->params->{fields}->value->%*;    # fields, defined if "fields" param

            # add always writable fields, if not already added
            my $api_map_fields = $self->api_map->fields;

            for my $field_name ( grep { $api_map_fields->{$_}->is_always_writable } keys $api_map_fields->%* ) {
                $writable_fields->{$field_name} = 1;
            }
        }
        else {
            $writable_fields = $self->api_map->writable_fields;           # all API map writable fields
        }
    }
    else {
        $writable_fields = $self->api_map->writable_fields;               # all API map writable fields
    }

    $writable_fields = { $writable_fields->%*, client_id => 1 } if $self->method->write_client_id;

    return [ keys $writable_fields->%* ];
}

# persist fields, used to retrive only needed fields from DB
sub _build_persist_fields {
    my $self = shift;

    my $api_map_fields = $self->api_map->fields;

    my $persist_fields = {};

    for my $field_name ( $self->writable_fields->@* ) {

        # add this field, if this field is persist
        $persist_fields->{$field_name} = 1 if $api_map_fields->{$field_name}->persist;

        # add persist fields, from this field depends
        for my $depend_field_name ( $api_map_fields->{$field_name}->persist_depends->@* ) {
            $persist_fields->{$depend_field_name} = 1;
        }
    }

    return [ keys $persist_fields->%* ];
}

# RUN
sub run {
    my $self = shift;

    my $action = $self->action;

    my $api_method = 'api_' . $action->method;

    my $response = try {
        $self->exception(q[Method isn't implemented]) unless $self->api_class->can($api_method);

        # call api method
        my ( $recs, %args ) = $self->api_class->$api_method( $self->method->use_fields ? $self->records : $self->params, $self );

        $recs //= [];

        # write recoeds
        $recs = $self->records->write_records($recs);

        return $action->response( data => $recs, %args );
    }
    catch {
        my $e = shift;

        if ( !$e->propagated ) {    # unexpected run-time error
            $e->send_log;

            my %args;

            $args{where} = $e->msg if $self->env_is_devel;

            return $action->exception( 'Internal server error', %args );
        }
        elsif ( $e->is_propagated('API::EXCEPTION') ) {    # expected exception
            $e->stop_propagate;

            my $message = delete $self->_exception_data->{message} // q[Unknown exception occured];

            if ( $self->env_is_devel ) {
                warn $message;
            }

            return $action->exception( $message, $self->_exception_data->%* );
        }
    };

    return $response;
}

sub exception {
    my $self    = shift;
    my $message = shift;
    my %args    = @_;

    $args{message} = $message if defined $message;

    $self->_set__exception_data( \%args );

    return Pcore::Core::Exception::propagate('API::EXCEPTION');
}

# UTIL
sub _validate_action_data {
    my $self = shift;

    # uploads are disabled if method has no upload fields
    $self->exception(q[Method don't accept uploads]) if $self->action->has_uploads && !$self->method->has_readable_upload_fields;

    $self->exception(q[Method don't accept any data]) if $self->action->has_data && !$self->method->use_params && !$self->method->use_fields;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 30, 39               │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 63, 65, 102, 178,    │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 183, 195, 197, 219,  │                                                                                                                │
## │      │ 264                  │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
