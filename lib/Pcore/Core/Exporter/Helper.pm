package Pcore::Core::Exporter::Helper;

use Pcore;

sub parse_import {
    my $self   = shift;
    my $caller = shift;

    my $tags = [];

    my $pragma = {};

    my $data;

    while ( my $arg = shift ) {
        if ( ref $arg eq 'HASH' ) {
            $data = $arg;
        }
        elsif ( $arg =~ /\A-(.+)\z/sm ) {
            if ( $1 eq 'level' || $1 eq 'caller' ) {
                $pragma->{$1} = shift;
            }
            elsif ( exists ${ $caller . '::EXPORT_PRAGMAS' }{$1} ) {
                $pragma->{$1} = ${ $caller . '::EXPORT_PRAGMAS' }{$1} ? shift : 1;
            }
            else {
                die qq[Unknown exporter pragma found "$arg" while importing package "$caller"];
            }

        }
        else {
            push @{$tags}, $arg;
        }
    }

    return $tags, $pragma, $data;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Exporter::Helper

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
