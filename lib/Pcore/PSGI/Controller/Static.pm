package Pcore::PSGI::Controller::Static;

use Pcore qw[-role];

has static_root          => ( is => 'lazy', isa => ArrayRef [Str] );
has static_cache_control => ( is => 'lazy', isa => ArrayRef [Str] );
has static_no_cache      => ( is => 'lazy', isa => Bool );

no Pcore;

sub _build_static_cache_control {
    my $self = shift;

    return [qw[public private must-revalidate proxy-revalidate]];
}

sub _build_static_no_cache {
    my $self = shift;

    return 0;    # don't use cache for static files, static_cache attribute are ignored
}

sub serve_static_root {
    my $self = shift;
    my $path = shift;
    my $root = shift;

    if ( my $realpath = $self->find_realpath( $path, $root ) ) {
        my $last_modified = [ stat $realpath ]->[9];

        # process cache settings
        if ( $self->static_no_cache ) {
            return $self->res->add_fh($realpath)->set_last_modified($last_modified)->set_no_cache;
        }
        elsif ( $self->is_file_modified($last_modified) ) {
            return $self->res->add_fh($realpath)->set_last_modified($last_modified)->set_cache_control( $self->static_cache_control );
        }
        else {
            return $self->res->set_status(304);
        }
    }
    else {
        return $self->res->set_status(404);
    }

    return;
}

sub find_realpath {
    my $self = shift;
    my $path = shift;
    my $root = shift;

    $root = [$root] unless ref $root eq 'ARRAY';

    for my $r ( @{$root} ) {
        if ( my $root_realpath = P->file->path( $r, is_dir => 1 )->realpath ) {
            if ( my $realpath = P->file->path( $root_realpath . $path->to_abs )->realpath ) {
                if ( $realpath->is_rel_to($root_realpath) ) {    # check, that founded path is in given root
                    return $realpath;
                }
            }
        }
    }

    return;
}

sub is_file_modified {                                           # compare date with headers
    my $self          = shift;
    my $last_modified = shift;                                   # mandatory, epoch
    my %args          = (
        cache_control     => $self->req->headers->{CACHE_CONTROL}     || undef,
        if_modified_since => $self->req->headers->{IF_MODIFIED_SINCE} || undef,    # RFC HTTP date
        @_,
    );

    if ( $args{cache_control} && $args{cache_control} =~ /no-cache/sm ) {          # Cache-Control: no-cache - don't use cache
        return 1;
    }
    else {
        if ( $args{if_modified_since} ) {
            return P->date->from_epoch($last_modified)->is_after( P->date->parse( $args{if_modified_since} ) ) ? 1 : 0;
        }
        else {
            return 1;
        }
    }
}

1;
__END__
=pod

=encoding utf8

=cut
