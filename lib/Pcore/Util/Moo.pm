package Pcore::Util::Moo;

use Pcore;

no Pcore;

sub get_attrs {
    my $self = shift;
    my $class = ref $_[0] || $_[0];

    return exists $Moo::MAKERS{$class} ? $Moo::MAKERS{$class}->{constructor}->{attribute_specs} : undef;
}

sub get_attr {
    my $self  = shift;
    my $class = shift;
    my $attr  = shift;

    if ( my $attrs = $self->get_attrs($class) ) {
        return exists $attrs->{$attr} ? $attrs->{$attr} : undef;
    }
    else {
        return;
    }
}

sub is_role {
    my $self = shift;
    my $class = ref $_[0] || $_[0];

    return Moo::Role->is_role($class) ? 1 : 0;
}

1;
__END__
=pod

=encoding utf8

=cut
