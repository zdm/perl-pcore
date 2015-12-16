package Pcore::AppX;

use Pcore -role;

with qw[Pcore::AppX::Role];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App::Role'], required => 1, weak_ref => 1 );
has appx => ( is => 'ro', isa => Maybe [Object], required => 1, weak_ref => 1 );    # parent appx object
has _appx_key => ( is => 'ro', isa => Str, required => 1 );
has appx_reset => ( is => 'lazy', isa => Enum [qw[CLEAR RESET]], init_arg => undef );
has appx_parent => ( is => 'lazy', isa => Object, weak_ref => 1, init_arg => undef );
has cfg => ( is => 'lazy', isa => HashRef, init_arg => undef );

sub _build_appx_parent ($self) {
    return $self->appx ? $self->appx : $self->app;
}

around _build_cfg => sub ( $orig, $self ) {
    my $base_cfg = $self->appx_parent->cfg;

    $base_cfg->{ $self->_appx_key } //= {};
    if ( my $default_cfg = $self->$orig ) {
        %{ $base_cfg->{ $self->_appx_key } } = %{ P->hash->merge( $default_cfg, $base_cfg->{ $self->_appx_key } ) };
    }

    return $base_cfg->{ $self->_appx_key };
};

# this method can be oveloaded
sub _build_cfg ($self) {
    return;
}

around _create_local_cfg => sub ( $orig, $self, $base_cfg ) {
    if ( my $local_cfg = $self->$orig ) {
        $base_cfg->{ $self->_appx_key } //= {};

        P->hash->merge( $base_cfg->{ $self->_appx_key }, $local_cfg );
    }

    # create AppX local configs
    for my $attr ( $self->_appx_enum->@* ) {
        my $attr_reader = $attr->{reader};

        $self->$attr_reader->_create_local_cfg( $base_cfg->{ $self->_appx_key } );
    }

    return;
};

sub _build_appx_reset ($self) {
    return 'RESET';
}

# this method can be oveloaded
sub _create_local_cfg ($self) {
    return;
}

sub app_build ($self) {
    return;
}

sub app_deploy ($self) {
    return;
}

sub app_reset ($self) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
