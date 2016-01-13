package header;

use utf8;
use strict;
use warnings ( qw[all], FATAL => qw[utf8], NONFATAL => qw[] );
no if $^V ge 'v5.18', warnings => 'experimental';
use if $^V lt 'v5.23', warnings => 'experimental::autoderef', FATAL => 'experimental::autoderef';
use if $^V ge 'v5.10', feature => ':all';
no  if $^V ge 'v5.16', feature => 'array_base';
use if $^V ge 'v5.22', re      => 'strict';
use if $^V ge 'v5.10', mro     => 'c3';
no multidimensional;

sub import {
    my ( $self, %args ) = @_;

    my $caller = $args{-caller} // caller;

    utf8->import();
    strict->import();
    $self->warnings;
    feature->import(':all')         if $^V ge 'v5.10';
    feature->unimport('array_base') if $^V ge 'v5.16';
    re->import('strict')            if $^V ge 'v5.22';
    mro::set_mro( $caller, 'c3' ) if $^V ge 'v5.10';
    multidimensional->unimport;

    return;
}

sub warnings {
    my ($self) = @_;

    warnings->import( 'all', FATAL => qw[utf8], NONFATAL => qw[] );
    warnings->unimport('experimental') if $^V ge 'v5.18';
    warnings->import( 'experimental::autoderef', FATAL => qw[experimental::autoderef] ) if $^V lt 'v5.23';

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "header" does not start with a upper case letter                   │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

header

=head1 SYNOPSIS

    use header;

    # or re-export

    sub import {
        header->import( -caller => caller );
    }

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
