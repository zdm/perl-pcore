package Pcore::Util::Path::MIME;

use Pcore -role, -const;
use Pcore::Util::Scalar qw[is_plain_arrayref is_plain_scalarref];

has _mime_type     => ( init_arg => undef );
has _mime_category => ( init_arg => undef );

# apache MIME types
# http://svn.apache.org/viewvc/httpd/httpd/trunk/docs/conf/mime.types?view=co
our $MIME_TYPES;

const our @DEFAULT_MIME_TYPE => 'application/octet-stream';

around _clear_cache => sub ( $orig, $self ) {
    delete $self->@{qw[_mime_type _mime_category]};

    return $self->$orig;
};

sub _load_mime_types {
    unless ($MIME_TYPES) {
        $MIME_TYPES = P->cfg->read( $ENV->{share}->get('data/mime.json') );

        # index MIME categories
        for my $suffix ( keys $MIME_TYPES->{suffix}->%* ) {
            my $type;

            if ( is_plain_arrayref $MIME_TYPES->{suffix}->{$suffix} ) {
                $type = $MIME_TYPES->{suffix}->{$suffix}->[0];

                $MIME_TYPES->{category}->{$type} = $MIME_TYPES->{suffix}->{$suffix}->[1] if $MIME_TYPES->{suffix}->{$suffix}->[1];

                $MIME_TYPES->{suffix}->{$suffix} = $type;
            }
            else {
                $type = $MIME_TYPES->{suffix}->{$suffix};
            }

            if ( !$MIME_TYPES->{category}->{$type} && $type =~ m[\A(.+?)/]sm ) {
                $MIME_TYPES->{category}->{$type} = $1;
            }
        }

        # compile shebang
        for my $key ( keys $MIME_TYPES->{shebang}->%* ) {
            $MIME_TYPES->{shebang}->{$key} = qr/$MIME_TYPES->{shebang}->{$key}/sm;
        }
    }

    return;
}

# shebang Bool or ScalarRef to file content
sub mime_type ( $self, $shebang = undef ) {
    _load_mime_types() if !defined $MIME_TYPES;

    if ( !exists $self->{_mime_type} ) {
        my $detected;

        # filename
        if ( my $filename = $self->{filename} ) {
            if ( $self->{_mime_type} = $MIME_TYPES->{filename}->{$filename} ) {
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
            if ( $self->{_mime_type} = ( $MIME_TYPES->{suffix}->{$suffix} // $MIME_TYPES->{suffix}->{ lc $suffix } ) ) {
                $detected = 1;
            }
        }

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
                for my $mime_type ( keys $MIME_TYPES->{shebang}->%* ) {
                    if ( $1 =~ $MIME_TYPES->{shebang}->{$mime_type} ) {
                        $detected = 1;

                        $self->{_mime_type} = $mime_type;

                        last;
                    }
                }
            }
        }

        $self->{_mime_type} = undef if !$detected;
    }

    return $self->{_mime_type};
}

sub mime_category ($self) {
    if ( !exists $self->{_mime_category} ) {
        if ( my $mime_type = $self->mime_type ) {
            $self->{_mime_category} = $MIME_TYPES->{category}->{$mime_type};
        }
        else {
            $self->{_mime_category} = undef;
        }
    }

    return $self->{_mime_category};
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
