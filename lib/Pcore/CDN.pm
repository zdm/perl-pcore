package Pcore::CDN;

use Pcore -class;
use Pcore::Util::Scalar qw[is_plain_arrayref];
use overload '&{}' => sub ( $self, @ ) {
    sub { $self->get_url(@_) }
  },
  fallback => 1;

has bucket        => ( init_arg => undef );
has default_read  => ();
has default_write => ();
has resources     => ();                      # HashRef[CodeRef]

around new => sub ( $orig, $self, $args ) {
    $self = $self->$orig;

    $self->{default_read}  = delete $args->{default_read};
    $self->{default_write} = delete $args->{default_write};

    # load resources
    if ( my $resources = delete $args->{resources} ) {
        for my $lib ( $resources->@* ) {
            P->class->load( $lib =~ s/-/::/smgr );

            my $cdn_resources_path = $ENV->dist($lib)->{share_dir} . '/cdn-resources.perl';

            if ( -f $cdn_resources_path ) {
                my $cdn_resources = P->cfg->read($cdn_resources_path);

                $self->{resources}->@{ keys $cdn_resources->%* } = values $cdn_resources->%*;
            }
        }
    }

    # load buckets
    while ( my ( $name, $cfg ) = each $args->%* ) {
        $self->{bucket}->{$name} = P->class->load( $cfg->{type}, ns => 'Pcore::CDN::Bucket' )->new($cfg);

        $self->{default_read} //= $name;
    }

    return $self;
};

sub bucket ( $self, $name ) { return $self->{bucket}->{$name} }

sub get_url ( $self, $path ) { return $self->{bucket}->{ $self->{default_read} }->get_url($path) }

sub get_script_tag ( $self, $path ) { return qq[<script src="@{[ $self->get_url($path) ]}" integrity="" crossorigin="anonymous"></script>] }

sub get_css_tag ( $self, $path ) { return qq[<link rel="stylesheet" href="@{[ $self->get_url($path) ]}" integrity="" crossorigin="anonymous" />] }

sub get_resources ( $self, @resources ) {
    my @res;

    for my $name (@resources) {
        if ( is_plain_arrayref $name) {
            push @res, $self->{resources}->{ $name->[0] }->( $self, $name->@[ 1 .. $name->$#* ] )->@*;
        }
        else {
            push @res, $self->{resources}->{$name}->($self)->@*;
        }
    }

    return \@res;
}

# TODO write
sub write ( $self, $path, $data, @args ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    return $self->{bucket}->{ $self->{default_write} }->write( $path, $data, @args );
}

sub get_nginx_cfg($self) {
    my @buf;

    for my $buckeet ( $self->{bucket}->%* ) {
        next if !$bucket->{is_local};

        push @buf, $bucket->get_nginx_cfg;
    }

    return join $LF, @buf;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
