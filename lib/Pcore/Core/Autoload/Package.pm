package Pcore::Core::Autoload::Package;

use Pcore;
use Pcore::Core::Autoload::Role;

{
    no strict qw[refs];

    *{ __PACKAGE__ . '::AUTOLOAD' } = \&Pcore::Core::Autoload::Role::AUTOLOAD;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Autoload::Package

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
