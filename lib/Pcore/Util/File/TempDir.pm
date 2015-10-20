package Pcore::Util::File::TempDir;

use Pcore qw[-class];
use File::Temp qw[];    ## no critic qw[Modules::ProhibitEvilModules]

has base => ( is => 'lazy', isa => Str );
has tmpl => ( is => 'lazy', isa => Str );
has mode => ( is => 'lazy', isa => Maybe [ Int | Str ], default => q[rwx------] );
has lazy => ( is => 'ro', isa => Bool, default => 1 );

has _temp => ( is => 'lazy', isa => InstanceOf ['File::Temp::Dir'] );
has path => ( is => 'lazy', isa => Str );

use overload            #
  q[""] => sub {
    my $self = shift;

    return $self->path;
  },
  fallback => undef;

no Pcore;

sub BUILD {
    my $self = shift;

    $self->_temp unless $self->lazy;

    return;
}

sub _build__temp {
    my $self = shift;

    my $temp = File::Temp->newdir( DIR => $self->base, TEMPLATE => $self->tmpl );

    P->file->chmod( $self->mode, $temp->dirname );

    return $temp;
}

sub _build_path {
    my $self = shift;

    return P->path( $self->_temp->dirname, is_dir => 1 )->realpath->to_string;
}

sub _build_base {
    my $self = shift;

    return "$PROC->{TEMP_DIR}";
}

sub _build_tmpl {
    my $self = shift;

    return 'temp-' . P->sys->pid . '-XXXXXXXX';
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File::TempDir

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
