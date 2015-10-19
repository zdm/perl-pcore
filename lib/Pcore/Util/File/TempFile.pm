package Pcore::Util::File::TempFile;

use Pcore qw[-class];
use File::Temp qw[];    ## no critic qw[Modules::ProhibitEvilModules]

has base     => ( is => 'lazy', isa => Str );
has tmpl     => ( is => 'lazy', isa => Str );
has exlock   => ( is => 'ro',   isa => Bool, default => 0 );
has _binmode => ( is => 'ro',   isa => Str, default => q[], init_arg => 'binmode' );
has autoflush => ( is => 'ro', isa => Bool, default => 0 );
has mode => ( is => 'lazy', isa => Maybe [ Int | Str ], default => q[rw-------] );

has fh => ( is => 'lazy', isa => InstanceOf ['File::Temp'] );

no Pcore;

# modify original File::Temp class
{
    local $^W = 0;    # temporary disable warnings

    File::Temp->overload::OVERLOAD(
        q[""] => sub {
            return $_[0]->path;
        }
    );

    *File::Temp::path = sub {
        my $self = shift;

        ${ *{$self} }[0] = P->file->path( $self->filename )->to_string unless ${ *{$self} }[0];

        return ${ *{$self} }[0];
    };
}

sub _build_fh ($self) {
    my $temp = File::Temp->new( DIR => $self->base, TEMPLATE => $self->tmpl, EXLOCK => $self->exlock );

    binmode $temp, $self->_binmode or die if $self->_binmode;

    $temp->autoflush(1) if $self->autoflush;

    P->file->chmod( $self->mode, $temp->path );

    return $temp;
}

sub _build_base ($self) {
    return "$PROC->{TEMP_DIR}";
}

sub _build_tmpl ($self) {
    return 'temp-' . P->sys->pid . '-XXXXXXXX';
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::File::TempFile

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
