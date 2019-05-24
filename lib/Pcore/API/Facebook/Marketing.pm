package Pcore::API::Facebook::Marketing;

use Pcore -role, -const;

# https://developers.facebook.com/docs/marketing-api/

# https://developers.facebook.com/docs/graph-api/changelog
const our $VER => 3.3;

const our $FB_ADACC_STATUS_ACTIVE              => 1;
const our $FB_ADACC_STATUS_DISABLED            => 2;
const our $FB_ADACC_STATUS_UNSETTLED           => 3;
const our $FB_ADACC_STATUS_PENDING_RISK_REVIEW => 7;
const our $FB_ADACC_STATUS_PENDING_SETTLEMENT  => 8;
const our $FB_ADACC_STATUS_IN_GRACE_PERIOD     => 9;
const our $FB_ADACC_STATUS_PENDING_CLOSURE     => 100;
const our $FB_ADACC_STATUS_CLOSED              => 101;
const our $FB_ADACC_STATUS_ANY_ACTIVE          => 201;
const our $FB_ADACC_STATUS_ANY_CLOSED          => 202;

const our $FB_ADACC_DISABLE_REASON_NONE                    => 0;
const our $FB_ADACC_DISABLE_REASON_ADS_INTEGRITY_POLICY    => 1;
const our $FB_ADACC_DISABLE_REASON_ADS_IP_REVIEW           => 2;
const our $FB_ADACC_DISABLE_REASON_RISK_PAYMENT            => 3;
const our $FB_ADACC_DISABLE_REASON_GRAY_ACCOUNT_SHUT_DOWN  => 4;
const our $FB_ADACC_DISABLE_REASON_ADS_AFC_REVIEW          => 5;
const our $FB_ADACC_DISABLE_REASON_BUSINESS_INTEGRITY_RAR  => 6;
const our $FB_ADACC_DISABLE_PERMANENT_CLOSE                => 7;
const our $FB_ADACC_DISABLE_REASON_UNUSED_RESELLER_ACCOUNT => 8;
const our $FB_ADACC_DISABLE_REASON_UNUSED_ACCOUNT          => 9;

# ADACCOUNTS
# # https://developers.facebook.com/docs/marketing-api/reference/ad-account/
sub get_adaccounts ( $self, $user_id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$user_id/adaccounts", { fields => 'account_id,id,name,age,amount_spent,balance,currency,account_status,disable_reason,is_prepay_account,spend_cap,min_campaign_group_spend_cap,min_daily_budget', }, undef, $cb );
}

# CAMPAIGNS
# https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group
sub get_campaigns ( $self, $adaccount_id, $cb = undef ) {
    $adaccount_id = "act_$adaccount_id" if substr( $adaccount_id, 0, 4 ) ne 'act_';

    return $self->_req( 'GET', "v$VER/$adaccount_id/campaigns", { fields => 'id,budget_remaining,configured_status,daily_budget,lifetime_budget,effective_status,name', }, undef, $cb );
}

# ADSETS
# https://developers.facebook.com/docs/marketing-api/reference/ad-campaign/
sub get_adsets ( $self, $adaccount_id, $cb = undef ) {
    $adaccount_id = "act_$adaccount_id" if substr( $adaccount_id, 0, 4 ) ne 'act_';

    return $self->_req( 'GET', "v$VER/$adaccount_id/adsets", { fields => 'id,name,daily_budget,effective_status,lifetime_budget,budget_remaining,campaign', }, undef, $cb );
}

sub get_adset ( $self, $adset_id, $cb = undef ) {
    return $self->_req( 'GET', "v$VER/$adset_id", { fields => 'id,name,daily_budget,effective_status,lifetime_budget,budget_remaining', }, undef, $cb );
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
