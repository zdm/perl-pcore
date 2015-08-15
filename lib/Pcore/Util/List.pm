package Pcore::Util::List;

use Pcore qw[-autoload];
use List::AllUtils qw[];    ## no critic qw[Modules::ProhibitEvilModules]

sub autoload {
    my $self   = shift;
    my $method = shift;

    my $sub_name = 'List::AllUtils::' . $method;

    return sub {
        my $self = shift;

        goto &{$sub_name};
    };
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::List

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
