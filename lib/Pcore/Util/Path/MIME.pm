package Pcore::Util::Path::MIME;

use Pcore -role, -const;
use Pcore::Util::Scalar qw[is_plain_arrayref is_plain_scalarref];

has _mime_type     => ( init_arg => undef );
has _mime_tag      => ( init_arg => undef );
has _mime_compress => ( init_arg => undef );

# apache MIME types
# http://svn.apache.org/viewvc/httpd/httpd/trunk/docs/conf/mime.types?view=co
our $MIME;

const our $DEFAULT_MIME_TYPE => 'application/octet-stream';

around _clear_cache => sub ( $orig, $self ) {
    delete $self->@{qw[_mime_type _mime_tag _mime_compress]};

    return $self->$orig;
};

sub _load_mime_types {
    unless ($MIME) {
        $MIME = P->cfg->read( $ENV->{share}->get('data/mime.yaml') );

        # index MIME types
        for my $suffix ( keys $MIME->{suffix}->%* ) {

            # convert to ArrayRef
            $MIME->{suffix}->{$suffix} = [ $MIME->{suffix}->{$suffix}, [], undef ] if !is_plain_arrayref $MIME->{suffix}->{$suffix};

            $MIME->{suffix}->{$suffix}->[1] = [ $MIME->{suffix}->{$suffix}->[1] // () ] if !is_plain_arrayref $MIME->{suffix}->{$suffix}->[1];

            my $type = $MIME->{suffix}->{$suffix}->[0];

            # set mime type compress option
            $MIME->{type}->{$type}->[1] = $MIME->{suffix}->{$suffix}->[2] if defined $MIME->{suffix}->{$suffix}->[2];

            my $tags;

            # extract tag from type
            if ( $type =~ m[\A(.+?)/]sm ) { $tags->{$1} = 1 }

            for my $tag ( $MIME->{suffix}->{$suffix}->[1]->@* ) { $tags->{$tag} = 1 }

            $MIME->{type}->{$type}->[0]->@{ keys $tags->%* } = values $tags->%*;

            $MIME->{suffix}->{$suffix}->[1] = $tags;
        }

        # compile shebang
        for my $key ( keys $MIME->{shebang}->%* ) {
            $MIME->{shebang}->{$key} = qr/$MIME->{shebang}->{$key}/sm;
        }
    }

    return;
}

# shebang Bool or ScalarRef to file content
sub mime_type ( $self, $shebang = undef ) {
    _load_mime_types() if !defined $MIME;

    if ( !exists $self->{_mime_type} ) {
        my $detected;

        # filename
        if ( my $filename = $self->{filename} ) {
            if ( $self->{_mime_type} = $MIME->{filename}->{$filename} ) {
                $detected = 1;
            }
        }

        # path has no filename
        else {
            $detected = 1;
            $self->{_mime_type} = undef;
        }

        # suffix
        if ( !$detected && ( my $suffix = $self->{suffix} ) ) {
            if ( my $detected_suffix = ( $MIME->{suffix}->{$suffix} // $MIME->{suffix}->{ lc $suffix } ) ) {
                $detected = 1;
                $self->{_mime_type} = $detected_suffix->[0];
            }
        }

        # shebang
        if ( !$detected && $shebang ) {
            my $buf_ref;

            if ( is_plain_scalarref $shebang ) {
                $buf_ref = $shebang;
            }
            elsif ( -f $self ) {

                # read first 50 bytes
                P->file->read_bin(
                    $self,
                    buf_size => 50,
                    cb       => sub {
                        $buf_ref = $_[0] if $_[0];

                        return;
                    }
                );
            }

            if ( $buf_ref && $buf_ref->$* =~ /\A(#!.+?)$/sm ) {
                for my $mime_type ( keys $MIME->{shebang}->%* ) {
                    if ( $1 =~ $MIME->{shebang}->{$mime_type} ) {
                        $detected = 1;

                        $self->{_mime_type} = $mime_type;

                        last;
                    }
                }
            }
        }

        $self->{_mime_type} = $DEFAULT_MIME_TYPE if !$detected;
    }

    return $self->{_mime_type};
}

sub mime_tag ($self) {
    if ( !exists $self->{_mime_tag} ) {
        if ( my $mime_type = $self->mime_type ) {
            $self->{_mime_tag} = $MIME->{type}->{$mime_type}->[0];
        }
        else {
            $self->{_mime_tag} = {};
        }
    }

    return $self->{_mime_tag};
}

sub mime_compress ($self) {
    if ( !exists $self->{_mime_compress} ) {
        my $compress;

        # suffix
        if ( my $suffix = $self->{suffix} ) {
            if ( my $detected_suffix = ( $MIME->{suffix}->{$suffix} // $MIME->{suffix}->{ lc $suffix } ) ) {
                $compress = $detected_suffix->[2];
            }
        }

        if ( !defined $compress && ( my $mime_type = $self->mime_type ) ) {
            $compress = $MIME->{type}->{$mime_type}->[1];
        }

        $self->{_mime_compress} = $compress;
    }

    return $self->{_mime_compress};
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Path::MIME

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
