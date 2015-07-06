package Dist::Zilla::Stash::Pcore::Bitbucket;

use Moose;
use Pcore;

with qw[Dist::Zilla::Role::Stash];

has username => ( is => 'ro', isa => 'Str', required => 1 );

no Pcore;
no Moose;

__PACKAGE__->meta->make_immutable;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::Stash::Pcore::Bitbucket

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
