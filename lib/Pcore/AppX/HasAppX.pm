package Pcore::AppX::HasAppX;

use Pcore qw[-types];

sub import ($self) {
    my $caller = caller;

    Moo::_install_tracked $caller => has_appx => sub ( $name, @ ) {
        my %args = (
            is        => 'ro',
            isa       => undef,
            does      => 'Pcore::AppX',
            lazy      => 1,
            predicate => 1,
            clearer   => 1,
            init_arg  => undef,
            @_[ 1 .. $#_ ]
        );

        my $caller_class = caller;
        my $does         = delete $args{does};
        my $isa          = delete $args{isa};
        my $ns           = delete $args{ns};

        if ($isa) {
            $isa = P->class->resolve_class_name( $isa, 'Pcore::AppX' );

            $args{isa} = InstanceOf [$isa];
        }

        $args{is_appx} = 1;

        $args{default} = sub ($self) {
            return _default_appx_builder(
                $self,
                $name,
                isa  => $isa,
                does => $does,
                ns   => $ns,
            );
        };

        # create attribute
        Moo->_constructor_maker_for($caller_class)->register_attribute_specs( $name, \%args );
        Moo->_accessor_maker_for($caller_class)->generate_method( $caller_class, $name, \%args );
        Moo->_maybe_reset_handlemoose($caller_class);

        return;
    };

    return;
}

sub _default_appx_builder ( $self, $name, @ ) {
    my %args = (
        isa  => undef,
        does => undef,
        ns   => undef,
        @_[ 2 .. $#_ ]
    );

    my $key  = uc $name;                                               # config hash key
    my $app  = $self->does('Pcore::App::Role') ? $self : $self->app;
    my $appx = $self->does('Pcore::AppX') ? $self : undef;

    my $class;
    if ( !$args{isa} ) {
        $class = $self->cfg->{$key}->{CLASS} or die qq[isa attribute option or ${key}_CLASS config key must be defined for AppX attribute "$name"];
        $class = P->class->resolve_class_name( $class, $args{ns} // 'Pcore::AppX' );
    }
    else {
        $class = $args{isa};
    }

    return P->class->load( $class, does => $args{does} )->new( { app => $app, appx => $appx, _appx_key => $key } );
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 8, 44, 45, 46        │ Subroutines::ProtectPrivateSubs - Private subroutine/method used                                               │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 9, 55                │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AppX::HasAppX

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
