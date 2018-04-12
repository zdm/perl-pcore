package Pcore::Util::Result1;

use Pcore -export => [qw[res]];
use Pcore::Util::Result::Status;
use Pcore::Util::Scalar qw[refaddr is_plain_arrayref is_plain_hashref];

my ( %status, %reason, %headers, %data );

use overload    #
  q[bool] => sub {
    return substr $status{ refaddr $_[0] }, 0, 1 == 2;
  },
  q[""] => sub {
    return $status{ refaddr $_[0] } . q[ ] . $reason{ refaddr $_[0] };
  },
  q[0+] => sub {

    # return $rows{ refaddr $_[0] };
  },
  q[@{}] => sub {
    return $data{ refaddr $_[0] };
  },
  q[%{}] => sub {
    return $data{ refaddr $_[0] }->[0];
  },
  fallback => 1;

sub DESTROY ($self) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) {
        my $id = refaddr $self;

        delete $status{$id};
        delete $reason{$id};
        delete $headers{$id};
        delete $data{$id};
    }

    return;
}

sub res ( $status, @args ) : prototype($;@) {
    my $self = bless \my $scalar, __PACKAGE__;

    my $id = refaddr $self;

    if ( is_plain_arrayref $status ) {
        $status{$id} = $status->[0];

        if ( is_plain_hashref $status->[1] ) {
            $reason{$id} = Pcore::Util::Result::Status::get_reason( undef, $status->[0], $status->[1] );

            # $status{$id} = $status->[1];
        }
        else {
            $reason{$id} = $status->[1] // get_reason( undef, $status->[0], $status->[2] );

            # $args{status_reason} = $status->[2];
        }
    }
    else {
        $status{$id} = $status;

        $reason{$id} = Pcore::Util::Result::Status::get_reason( undef, $status, undef );
    }

    if ( !@args ) {
        $data{$id} = [ {} ];
    }
    elsif ( @args == 1 ) {
        $data{$id} = $args[0] // [];
    }
    elsif ( @args % 2 ) {
        $data{$id} = shift @args // [];

        $headers{$id} = {@args};

    }
    else {
        $headers{$id} = {@args};
    }

    $data{$id} = [ $data{$id} ] if !is_plain_arrayref $data{$id};

    return $self;
}

sub status ($self) {
    return $status{ refaddr $self };
}

sub reason ($self) {
    return $reason{ refaddr $self };
}

# allowed attributes:
# - rows - DBI rows;
# - total - total records in table
# - error - error message, or Hashrefaddr field_name => field_validation_error;
sub headers ($self) : lvalue {
    return $headers{ refaddr $self };
}

sub rows ($self) {
    return $headers{ refaddr $self }->{rows} // 0;
}

sub data ($self) : lvalue {
    return $data{ refaddr $self };
}

# STATUS METHODS
sub is_info ($self) {
    return substr $status{ refaddr $_[0] }, 0, 1 == 1;
}

sub is_success ($self) {
    return substr $status{ refaddr $_[0] }, 0, 1 == 2;
}

sub is_redirect ($self) {
    return substr $status{ refaddr $_[0] }, 0, 1 == 3;
}

sub is_error ($self) {
    return substr $status{ refaddr $_[0] }, 0, 1 >= 4;
}

sub is_client_error ($self) {
    return substr $status{ refaddr $_[0] }, 0, 1 == 4;
}

sub is_server_error ($self) {
    return substr $status{ refaddr $_[0] }, 0, 1 >= 5;
}

# SERIALIZE
sub TO_DUMP ( $self, $dumper, @ ) {
    my %args = (
        path => undef,
        splice @_, 2,
    );

    my $tags;

    my $res = $dumper->_dump( $self->TO_JSON, path => $args{path} );

    return $res, $tags;
}

*TO_JSON = *TO_CBOR = sub ($self) {
    my $id = refaddr $self;

    return {
        status  => $status{$id},
        reason  => $reason{$id},
        headers => $headers{$id},
        data    => $data{$id},
    };
};

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    1 | 173                  | Documentation::RequirePackageMatchesPodName - Pod NAME on line 177 does not match the package declaration      |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Result

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
