package Pcore::API::Class;

use Pcore -role;
use Pcore::API::Map;

with qw[Pcore::JS::ExtJS::Namespace];

has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::API::Backend::Local'], required => 1, weak_ref => 1 );    # local api backend
has h_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Core::H::Cache'],      required => 1, weak_ref => 1 );    # api handles cache

has _api_map => ( is => 'lazy', isa => InstanceOf ['Pcore::API::Map'],       init_arg => undef );
has _call    => ( is => 'rwp',  isa => InstanceOf ['Pcore::API::Map::Call'], init_arg => undef, weak_ref => 1 );  # run-time call object

has __app_builded => ( is => 'rwp', isa => Bool, default => 0, init_arg => undef );

has ext_model_base_class => ( is => 'lazy', isa => Str, init_arg => undef );

no Pcore;

sub BUILD {
    my $self = shift;

    return;
}

sub _build__api_map {
    my $self = shift;

    return Pcore::API::Map->new( { api_class => $self } );
}

# DDL
sub APP_BUILD {
    my $self = shift;

    $self->_set___app_builded(1);

    return;
}

# CONFIG METHODS
sub add_reserved_fields_names {
    my $self = shift;

    return $self->_api_map->add_reserved_fields_names(@_);
}

sub add_fields {
    my $self = shift;

    return $self->_api_map->add_fields(@_);
}

sub add_methods {
    my $self = shift;

    return $self->_api_map->add_methods(@_);
}

# THROW EXCEPTION
sub exception {
    my $self = shift;

    return $self->_call->exception(@_);
}

# API CALLS
sub get_api_obj {
    my $self = shift;

    return $self->backend->get_api_obj(@_);
}

sub call_cache {
    my $self = shift;

    $self->_call->cache->{ ref $self } //= {};

    return $self->_call->cache->{ ref $self };
}

# EXT MODEL
sub ext_class_model {
    my $self = shift;

    return unless $self->_api_map->has_fields;

    return $self->ext_define(
        $self->ext_model_base_class,
        {   validationSeparator => ', ',
            proxy               => {
                type => 'direct',
                api  => $self->_ext_get_api_methods,
            },
            fields => [ grep {defined} map { $_->ext_model_field } values $self->_api_map->fields->%* ],
        }
    );
}

sub _build_ext_model_base_class {
    my $self = shift;

    return 'Ext.data.Model';
}

sub _ext_get_api_methods {
    my $self = shift;

    my $api = {};

    for my $method_name ( keys $self->_api_map->methods->%* ) {
        $api->{$method_name} = $self->app_name . q[.] . $self->ext_class_ns . q[.] . $method_name;
    }

    return $api;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 95, 111              │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
