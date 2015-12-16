package Pcore::API::Class::Amcharts;

use Pcore -role;

with qw[Pcore::API::Class];

requires qw[_build_chart_config];

has chart_config => ( is => 'lazy', isa => HashRef, init_arg => undef );

no Pcore;

# EXT
sub ext_class_panel {
    my $self = shift;

    my $class = $self->ext_define(
        'Pcore.amcharts.Panel',
        {   model       => $self->ext_class('Model'),
            chartConfig => P->hash->merge(
                $self->chart_config,
                {   pathToImages => '/static/amcharts/images/',
                    theme        => 'light',
                }
            ),
        }
    );

    return $class;
}

1;
__END__
=pod

=encoding utf8

=cut
