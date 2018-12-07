package Pcore::CDN;

use Pcore -class;
use Pcore::Util::Scalar qw[weaken is_ref is_plain_arrayref is_plain_coderef];
use overload '&{}' => sub ( $self, @ ) {
    sub { $self->get_url(@_) }
  },
  fallback => 1;

has native_cdn => ();
has bucket     => ( init_arg => undef );
has resources  => ();                      # HashRef[CodeRef]

around new => sub ( $orig, $self, $args ) {
    $self = $self->$orig;

    $self->{native_cdn} = delete $args->{native_cdn};

    # load resources
    if ( my $resources = delete $args->{resources} ) {
        for my $lib ( $resources->@* ) {
            P->class->load( $lib =~ s/-/::/smgr );

            my $cdn_resources_path = $ENV->dist($lib)->{share_dir} . '/cdn.perl';

            if ( -f $cdn_resources_path ) {
                my $cdn_resources = P->cfg->read($cdn_resources_path);

                $self->{resources}->@{ keys $cdn_resources->%* } = values $cdn_resources->%*;
            }
        }
    }

    # create buckets
    while ( my ( $name, $cfg ) = each $args->%* ) {

        # skip aliases
        next if !is_ref $cfg;

        my $bucket = $self->{bucket}->{$name} = P->class->load( $cfg->{type}, ns => 'Pcore::CDN::Bucket' )->new($cfg);

        $self->{bucket}->{default} //= $bucket;

        $self->{bucket}->{default_upload} //= $bucket if $bucket->{can_upload};
    }

    # assign buckets aliases
    while ( my ( $name, $target ) = each $args->%* ) {

        # skip buckets
        next if is_ref $target;

        $self->{bucket}->{$name} = $self->{bucket}->{$target};
    }

    $self->{bucket}->{default_upload} = $self->{bucket}->{default} if !defined $self->{bucket}->{default_upload} && $self->{bucket}->{default}->{can_upload};

    return $self;
};

sub bucket ( $self, $name ) { return $self->{bucket}->{$name} }

sub get_url ( $self, $path ) {
    my $bucket_name;

    # extract bucket
    if ( substr( $path, 0, 1 ) eq '/' ) {
        $path = "$path" if is_ref $path;

        $bucket_name = substr $path, 0, index( $path, '/', 1 ) + 1, '';
        substr $bucket_name, 0,  1, '';
        substr $bucket_name, -1, 1, '';
    }
    else {
        $bucket_name = 'default';
    }

    my $bucket = $self->{bucket}->{$bucket_name};

    die qq[Bucket "$bucket_name" is not defined] if !defined $bucket;

    return $bucket->get_url($path);
}

sub get_resources ( $self, @resources ) {
    my @res;

    for my $res (@resources) {
        my ( $name, %args, $bucket_name );

        if ( is_plain_arrayref $res) {
            ( $name, %args ) = $res->@*;
        }
        else {
            $name = $res;
        }

        if ( substr( $name, 0, 1 ) eq '/' ) {
            $bucket_name = substr $name, 0, index( $name, '/', 1 ) + 1, '';
            substr $bucket_name, 0,  1, '';
            substr $bucket_name, -1, 1, '';
        }
        else {
            $bucket_name = 'default';
        }

        my $bucket = $self->{bucket}->{$bucket_name};

        die qq[Bucket "$bucket_name" is not defined] if !defined $bucket;

        die qq[CDN resource "$name" is not defined] if !defined $self->{resources}->{$name};

        my $native = $args{native_cdn} // $bucket->{native_cdn} // $self->{native_cdn};

        push @res, $self->{resources}->{$name}->( $self, $bucket, $native, \%args );
    }

    return \@res;
}

sub get_resource_root ( $self, $name, %args ) {
    my $bucket_name;

    # extract bucket
    if ( substr( $name, 0, 1 ) eq '/' ) {
        $bucket_name = substr $name, 0, index( $name, '/', 1 ) + 1, '';
        substr $bucket_name, 0,  1, '';
        substr $bucket_name, -1, 1, '';
    }
    else {
        $bucket_name = 'default';
    }

    my $bucket = $self->{bucket}->{$bucket_name};

    die qq[Bucket "$bucket_name" is not defined] if !defined $bucket;

    die qq[CDN resource "$name" is not defined] if !defined $self->{resources}->{$name};

    my $native = $args{native_cdn} // $bucket->{native_cdn} // $self->{native_cdn};

    return scalar $self->{resources}->{$name}->( $self, $bucket, $native, \%args );
}

sub get_script_tag ( $self, $url ) { return qq[<script src="$url" integrity="" crossorigin="anonymous"></script>] }

sub get_css_tag ( $self, $url ) { return qq[<link rel="stylesheet" href="$url" integrity="" crossorigin="anonymous" />] }

sub upload ( $self, $path, $data, @args ) {
    my $bucket_name;

    # extract bucket
    if ( substr( $path, 0, 1 ) eq '/' ) {
        $path = "$path" if is_ref $path;

        $bucket_name = substr $path, 0, index( $path, '/', 1 ) + 1, '';
        substr $bucket_name, 0,  1, '';
        substr $bucket_name, -1, 1, '';
    }
    else {
        $bucket_name = 'default_upload';
    }

    my $bucket = $self->{bucket}->{$bucket_name};

    die qq[Bucket "$bucket_name" is not defined] if !defined $bucket;

    return $bucket->upload( $path, $data, @args );
}

sub sync ( $self, $local, $remote, @locations ) {
    $local = $self->{bucket}->{$local};

    my $local_locations = $local->{locations};

    my $locations;

    for my $location (@locations) {
        my $match = '';

        for my $loc_cache ( keys $local_locations->%* ) {
            $match = $loc_cache if length $loc_cache > length $match && index( $location, $loc_cache ) == 0;
        }

        $locations->{$location} = $match ? $local_locations->{$match} : undef;
    }

    return $self->{bucket}->{$remote}->sync( $local->{libs}, $locations );
}

sub get_nginx_cfg($self) {
    my @buf;

    my $processed;

    for my $bucket ( $self->{bucket}->%* ) {
        next if !$bucket->{is_local} || exists $processed->{ $bucket->{id} };

        $processed->{ $bucket->{id} } = 1;

        push @buf, $bucket->get_nginx_cfg;
    }

    return join $LF, @buf;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 70, 71, 72, 99, 100, | ValuesAndExpressions::ProhibitEmptyQuotes - Quotes used with a string containing no non-whitespace characters  |
## |      |  101, 126, 127, 128, |                                                                                                                |
## |      |  156, 157, 158, 179  |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
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
