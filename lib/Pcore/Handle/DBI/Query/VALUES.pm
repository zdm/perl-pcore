package Pcore::Handle::DBI::Query::VALUES;

use Pcore -class;
use Pcore::Lib::Scalar qw[is_ref is_plain_scalarref is_arrayref is_plain_arrayref is_plain_hashref is_blessed_hashref];

has _buf => ( required => 1 );    # ArrayRef

# VALUES [ { a => 1 }, { b => 1 } ] # get columns from the first not empty hash, columns will be ( "a" )
# VALUES [ {}, { a => 1 }, { b => 1 } ] # perform full scan, columns will be ( "a", "b" ), first row will be ignored
# VALUES [ [], {}, { a => 1 }, { b => 1 } ] # get columns from the first not empty hash, columns will be ( "a" ), first [] will be ignored, first {} will not be ignored

sub get_query ( $self, $dbh, $final, $i ) {
    my ( @sql, @idx, @bind );

    for my $token ( $self->{_buf}->@* ) {

        # skip undefined values
        next if !defined $token;

        # HashRef prosessed as values set
        if ( is_plain_hashref $token) {

            # create fields index
            if ( !@idx ) {

                # first row is a hash without keys
                # create idx by scanning all rows
                # ignore first row
                my $full_scan = is_plain_hashref $self->{_buf}->[0] && !$self->{_buf}->[0]->%*;

                my $idx;

                for my $token ( $self->{_buf}->@* ) {

                    # get hash with keys
                    next if !is_plain_hashref $token || !$token->%*;

                    $idx->@{ keys $token->%* } = ();

                    last if !$full_scan;
                }

                @idx = sort keys $idx->%*;

                die q[unable to build columns index] if !@idx;
            }

            my @row;

            for my $field (@idx) {

                # Scalar or blessed ArrayRef value is processed as parameter
                if ( !is_ref $token->{$field} || is_arrayref $token->{$field} ) {
                    push @row, '$' . $i->$*++;

                    push @bind, $token->{$field};
                }

                # object
                elsif ( is_blessed_hashref $token->{$field} ) {
                    my ( $sql, $bind ) = $token->{$field}->get_query( $dbh, 0, $i );

                    if ($sql) {
                        push @row, $sql;

                        push @bind, $bind->@* if $bind;
                    }
                }
                else {
                    die 'Unsupported ref type';
                }

            }

            push @sql, '(' . join( ', ', @row ) . ')' if @row;
        }

        # ArrayhRef prosessed as values set
        elsif ( is_plain_arrayref $token) {
            my @row;

            for my $field ( $token->@* ) {

                # Scalar or ArrayRef value is processed as parameter
                if ( !is_ref $field || is_arrayref $field ) {
                    push @row, '$' . $i->$*++;

                    push @bind, $field;
                }

                # object
                elsif ( is_blessed_hashref $field ) {
                    my ( $sql, $bind ) = $field->get_query( $dbh, 0, $i );

                    if ($sql) {
                        push @row, $sql;

                        push @bind, $bind->@* if $bind;
                    }
                }
                else {
                    die 'Unsupported ref type';
                }

            }

            push @sql, '(' . join( ', ', @row ) . ')' if @row;
        }
        else {
            die 'Unsupported ref type';
        }
    }

    if (@idx) {
        return '(' . join( ', ', map { $dbh->quote_id($_) } @idx ) . ') VALUES ' . join( ', ', @sql ), \@bind;
    }
    else {
        return 'VALUES ' . join( ', ', @sql ), \@bind;
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 12                   | Subroutines::ProhibitExcessComplexity - Subroutine "get_query" with high complexity score (31)                 |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Handle::DBI::Query::VALUES

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
