package Pcore::API::Facebook::Marketing;

use Pcore -role, -const;

# https://developers.facebook.com/docs/marketing-api/

# https://developers.facebook.com/docs/graph-api/changelog
const our $VER => 3.3;

sub get_adaccounts ( $self, $user_id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$user_id/adaccounts", undef, undef, $cb );
}

sub get_adaccount_campaigns ( $self, $adaccount_id, $cb = undef ) {
    $adaccount_id = "act_$adaccount_id" if substr( $adaccount_id, 0, 4 ) ne 'act_';

    return $self->_req( 'GET', "v$VER/$adaccount_id/campaigns", undef, undef, $cb );
}

sub get_adaccount_adsets ( $self, $adaccount_id, $cb = undef ) {
    $adaccount_id = "act_$adaccount_id" if substr( $adaccount_id, 0, 4 ) ne 'act_';

    return $self->_req( 'GET', "v$VER/$adaccount_id/adsets", undef, undef, $cb );
}

# https://developers.facebook.com/docs/marketing-api/insights
sub get_insights ( $self, $id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$id/insights", undef, undef, $cb );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Facebook::Marketing

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
