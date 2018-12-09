package Pcore::CDN::Bucket;

use Pcore -role;
use Pcore::Util::UUID qw[uuid_v1mc_str];
use overload '&{}' => sub ( $self, @ ) {
    return sub { $self->get_url(@_) }
  },
  fallback => 1;

requires qw[upload];

has id            => sub {uuid_v1mc_str}, init_arg => undef;
has native_cdn    => ();
has cache_control => ();                                       # HashRef
has can_upload    => ( init_arg => undef );

has _cache_control_sorted => ( init_arg => undef );

around BUILD => sub ( $orig, $self, $args ) {
    $self->$orig($args);

    # set default cache control settings
    $self->{cache_control}->{'/'}        //= 'public, private, must-revalidate, proxy-revalidate';
    $self->{cache_control}->{'/static/'} //= 'public, max-age=30672000';

    return;
};

sub get_url ( $self, $path ) { return "$self->{prefix}/$path" }

sub get_nginx_cfg ($self) {return}

sub find_cache_control ( $self, $path ) {
    my $map = $self->{_cache_control_sorted} //= [ reverse sort { length $a <=> length $b } keys $self->{cache_control}->%* ];

    for my $loc ( $map->@* ) {
        return $self->{cache_control}->{$loc} if substr( $path, 0, length $loc ) eq $loc;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN::Bucket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
