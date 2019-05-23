package Pcore::API::Facebook::Marketing;

use Pcore -role, -const;

# https://developers.facebook.com/docs/marketing-api/

# https://developers.facebook.com/docs/graph-api/changelog
const our $VER => 3.3;

sub get_adaccounts ( $self, $user_id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$user_id/adaccounts", undef, undef, $cb );
}

# CAMPAIGNS
sub get_campaigns ( $self, $adaccount_id, $cb = undef ) {
    $adaccount_id = "act_$adaccount_id" if substr( $adaccount_id, 0, 4 ) ne 'act_';

    return $self->_req( 'GET', "v$VER/$adaccount_id/campaigns", undef, undef, $cb );
}

# ADSETS
# https://developers.facebook.com/docs/marketing-api/reference/ad-campaign/
sub get_adsets ( $self, $adaccount_id, $cb = undef ) {
    $adaccount_id = "act_$adaccount_id" if substr( $adaccount_id, 0, 4 ) ne 'act_';

    return $self->_req( 'GET', "v$VER/$adaccount_id/adsets", { fields => 'id,daily_budget,effective_status,lifetime_budget,budget_remaining', }, undef, $cb );
}

sub get_adset ( $self, $adset_id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$adset_id", { fields => 'id,daily_budget,effective_status,lifetime_budget,budget_remaining', }, undef, $cb );
}

# INSIGHTS
# https://developers.facebook.com/docs/marketing-api/insights
# https://developers.facebook.com/docs/marketing-api/reference/ads-insights/
sub get_insights ( $self, $id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$id/insights", { fields => 'impressions,ad_id,clicks,spend,cpc,ctr,reach,adset_name,adset_id', }, undef, $cb );
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
