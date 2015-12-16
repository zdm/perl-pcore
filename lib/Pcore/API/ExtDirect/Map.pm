package Pcore::API::Map;

use Pcore -class;
use Pcore::API::Map::Call;

has api_class => ( is => 'ro', isa => ConsumerOf ['Pcore::API::Class'], required => 1, weak_ref => 1 );

has _reserved_fields_names => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

has fields => ( is => 'lazy', isa => HashRef [ InstanceOf ['Pcore::API::Map::Field'] ], default => sub { {} }, init_arg => undef );
has upload_fields => ( is => 'lazy', isa => ArrayRef, clearer => 1, init_arg => undef );

has methods => ( is => 'lazy', isa => HashRef [ InstanceOf ['Pcore::API::Map::Method'] ], default => sub { {} }, init_arg => undef );

has writable_fields => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

# FIELDS
sub add_reserved_fields_names {
    my $self         = shift;
    my $fields_names = shift;

    for my $field_name ( $fields_names->@* ) {
        $self->_reserved_fields_names->{$field_name} = 1;

        die qq[Field name "$field_name" is reserved] if exists $self->fields->{$field_name};
    }

    return;
}

sub add_fields {
    my $self   = shift;
    my $fields = shift;

    for my $field_name ( keys $fields->%* ) {
        die qq[Field name "$field_name" is reserved] if exists $self->_reserved_fields_names->{$field_name};

        my $args->%* = $fields->{$field_name}->%*;

        $args->{api_map} = $self;
        $args->{name}    = $field_name;

        my $class;

        if ( my $type = delete $args->{type} ) {
            $class = P->text->to_camel_case( $type, ucfirst => 1 );
        }
        else {
            $class = '+Pcore::API::Map::Field';
        }

        my $field = P->class->load( $class, ns => 'Pcore::API::Map::Field' )->new($args);

        die qq[Field name "$field_name" can't be redefined] if $field->name ne $field_name;

        $self->fields->{ $field->name } = $field;
    }

    $self->clear_upload_fields;

    return $self;
}

sub _build_upload_fields {
    my $self = shift;

    return [ grep { $self->fields->{$_}->upload } keys $self->fields->%* ];
}

sub has_fields {
    my $self = shift;

    return keys $self->fields->%* ? 1 : 0;
}

sub has_upload_fields {
    my $self = shift;

    return $self->upload_fields->@*;
}

# METHODS
sub add_methods {
    my $self    = shift;
    my $methods = shift;

    for my $method_name ( keys $methods->%* ) {
        my $args->%* = $methods->{$method_name}->%*;

        $args->{name}    = $method_name;
        $args->{api_map} = $self;

        my $class;

        if ( my $type = delete $args->{type} ) {
            $class = P->text->to_camel_case( $type, ucfirst => 1 );
        }
        else {
            $class = '+Pcore::API::Map::Method';
        }

        my $method = P->class->load( $class, ns => 'Pcore::API::Map::Method' )->new($args);

        die qq[Field name "$method_name" can't be redefined] if $method->name ne $method_name;

        $self->methods->{$method_name} = $method;
    }

    return;
}

# MAP GENERATOR
sub generate_api_map {
    my $self = shift;

    my $api_map;

    # validate fields config
    for my $field_name ( sort keys $self->fields->%* ) {
        $self->fields->{$field_name}->generate_api_map;
    }

    # generate api map for each method
    for my $method_name ( sort keys $self->methods->%* ) {
        $api_map->{$method_name} = $self->methods->{$method_name}->generate_api_map;
    }

    return $api_map;
}

sub call_method {
    my $self   = shift;
    my $action = shift;

    return Pcore::API::Map::Call->new( { action => $action, api_class => $self->api_class } )->run;
}

sub _build_writable_fields {
    my $self = shift;

    return { map { $_ => 1 } grep { $self->fields->{$_}->is_writable } keys $self->fields->%* };
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 37, 40, 69, 75, 89,  │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## │      │ 90, 121, 126, 143    │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
