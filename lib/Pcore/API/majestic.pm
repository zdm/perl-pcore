package Pcore::API::majestic;

use Pcore -class, -res;
use Pcore::Util::Scalar qw[is_plain_arrayref];
use Pcore::Util::Data qw[to_uri from_json];

has api_key              => ();    # direct access to the API, access is restricted by IP address
has openapp_access_token => ();    # OpenApp access, user key, identify user
has openapp_private_key  => ();    # OpenApp access, application vendor key, identify application

has max_threads => 3;
has proxy       => ();

has _semaphore => sub ($self) { Coro::Semaphore->new( $self->{max_threads} ) }, is => 'lazy';

sub test ($self) {
    return res $self->get_subscription_info;
}

# https://developer-support.majestic.com/api/commands/get-anchor-text.shtml
sub get_anchor_text ( $self, $domain, %args ) {
    my $params = {
        cmd                  => 'GetAnchorText',
        datasource           => 'fresh',
        item                 => $domain,
        Count                => $args{num_anchors} || 10,    # Number of results to be returned back. Max. 1_000
        TextMode             => 0,
        Mode                 => 0,
        FilterAnchorText     => undef,
        FilterAnchorTextMode => 0,
        FilterRefDomain      => undef,
        UsePrefixScan        => 0,
    };

    my $res = $self->_req($params);

    return $res;
}

# https://developer-support.majestic.com/api/commands/get-index-item-info.shtml
# items - up to 100 items
sub get_index_item_info ( $self, $items, %args ) {
    $items = [$items] if !is_plain_arrayref $items;

    my $params = {
        cmd   => 'GetIndexItemInfo',
        items => scalar $items->@*,
        $args{datasource}                    ? ( datasource                 => $args{datasource} )     : (),
        $args{desired_topics}                ? ( DesiredTopics              => $args{desired_topics} ) : (),
        $args{add_all_topics}                ? ( AddAllTopics               => 1 )                     : (),
        $args{enable_resource_unit_failover} ? ( EnableResourceUnitFailover => 1 )                     : (),
    };

    for my $i ( 0 .. $items->$#* ) {
        $params->{"item$i"} = $items->[$i];
    }

    my $res = $self->_req($params);

    return $res;
}

# https://developer-support.majestic.com/api/commands/get-back-link-data.shtml
# TODO - add all params
sub get_backlink_data ( $self, $item, %args ) {
    my $params = {
        cmd  => 'GetBackLinkData',
        item => $item,
        $args{datasource}       ? ( datasource     => $args{datasource} ) : (),
        $args{count}            ? ( Count          => $args{count} )      : (),
        $args{from}             ? ( From           => $args{from} )       : (),
        $args{mode}             ? ( Mode           => 1 )                 : (),
        $args{show_domain_info} ? ( ShowDomainInfo => 1 )                 : (),
    };

    my $res = $self->_req($params);

    return $res;
}

# https://developer-support.majestic.com/api/commands/get-subscription-info.shtml
sub get_subscription_info ( $self, %args ) {
    my $params = {
        cmd => 'GetSubscriptionInfo',
        %args
    };

    my $res = $self->_req($params);

    return $res;
}

# BULK CHECK
# NOTE max. 100k domains
# sub bulk_check ( $self, $domains, $cb ) {

#     # login
#     $self->_login( sub ($res) {
#         if ( !$res ) {
#             $cb->($res);

#             return;
#         }

#         my $cookies = $res->{data};

#         my $job_id = P->uuid->str;

#         my $body = qq[-----------------------------3733385012218\r\nContent-Disposition: form-data; name=\"file\"; filename="$job_id"\r\nContent-Type: text/plain\r\n\r\n@{[ join( "\n", $domains->@*) . "\n" ]}\r\n-----------------------------3733385012218\r\nContent-Disposition: form-data; name="ajaxLoadUrl"\r\n\r\n/reports/downloads/confirm-file-upload/backlinksAjax\r\n-----------------------------3733385012218\r\nContent-Disposition: form-data; name="fileType"\r\n\r\nSingleColumn\r\n-----------------------------3733385012218\r\nContent-Disposition: form-data; name="IndexDataSource"\r\n\r\nF\r\n-----------------------------3733385012218--\r\n];

#         # send domains
#         P->http->post(
#             'https://majestic.com/reports/bulk-backlinks-upload',
#             useragent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:53.0) Gecko/20100101 Firefox/53.0',
#             cookies   => $cookies,
#             headers   => {
#                 CONTENT_TYPE => 'multipart/form-data; boundary=---------------------------3733385012218',
#                 REFERER      => 'https://majestic.com/reports/bulk-backlink-checker',
#             },
#             body      => $body,
#             on_finish => sub ($res) {
#                 if ( !$res ) {
#                     $cb->( result [ 500, 'Send domains error' ] );
#                 }
#                 elsif ( $res->decoded_body->$* =~ /fileupload_uid=([[:xdigit:]-]+)/sm ) {
#                     my $uid = $1;

#                     my $params = {
#                         fileupload_uid       => $uid,
#                         addFileToRecrawlList => 'false',
#                         index_data_source    => 'Fresh',
#                         tool                 => 'BacklinkChecker',
#                     };

#                     P->http->get(
#                         'https://majestic.com/reports/downloads/accept-file-upload-charges?' . P->data->to_uri($params),
#                         useragent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:53.0) Gecko/20100101 Firefox/53.0',
#                         cookies   => $cookies,
#                         headers   => {                                                                                   #
#                             REFERER => "https://majestic.com/reports/downloads/confirm-file-upload?tool=BacklinkChecker&fileupload_uid=$uid",
#                         },
#                         on_finish => sub ($res) {
#                             if ( !$res ) {
#                                 $cb->( result [ $res->status, $res->reason ] );
#                             }
#                             else {
#                                 if ( $res->decoded_body->$* =~ /$uid/sm ) {
#                                     $cb->( result 200, $job_id );
#                                 }
#                                 else {
#                                     $cb->( result [ 500, 'Unknown confirmation error' ] );
#                                 }
#                             }

#                             return;
#                         }
#                     );
#                 }
#                 else {
#                     $cb->( result [ 500, 'Send domains error - no job UID returned' ] );
#                 }

#                 return;
#             }
#         );

#         return;
#     } );

#     return;
# }

# sub bulk_check_result ( $self, $id, $mapping, $cb ) {

#     # login
#     $self->_login( sub ($res) {
#         if ( !$res ) {
#             $cb->($res);

#             return;
#         }

#         my $cookies = $res->{data};

#         P->http->get(
#             'https://majestic.com/reports/downloads',
#             useragent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:53.0) Gecko/20100101 Firefox/53.0',
#             cookies   => $cookies,
#             on_finish => sub ($res) {
#                 if ( !$res ) {
#                     $cb->( result [ 500, 'Get jobs list error' ] );

#                     return;
#                 }
#                 else {
#                     if ( $res->decoded_body->$* =~ /\Q$id\E/sm ) {
#                         if ( $res->decoded_body->$* =~ /<a href="\/reports\/downloads\/([[:xdigit:]-]+)">\s+\Q$id\E/sm ) {
#                             my $file_id = $1;

#                             P->http->get(
#                                 "https://majestic.com/reports/downloads/$file_id",
#                                 useragent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:53.0) Gecko/20100101 Firefox/53.0',
#                                 cookies   => $cookies,
#                                 on_finish => sub ($res) {
#                                     if ( !$res ) {
#                                         $cb->( result [ 500, 'Job download error' ] );
#                                     }
#                                     else {
#                                         IO::Uncompress::Unzip::unzip( $res->body, \my $data );

#                                         my @lines = split "\n", $data;

#                                         my $header = [ map { $mapping->{$_} || '_' } map { s/"//smg; $_ } split /,/sm, shift @lines ];    ## no critic qw[ControlStructures::ProhibitMutatingListFunctions]

#                                         my $items;

#                                         for my $line (@lines) {
#                                             my $item->@{ $header->@* } = map { s/"//smg; $_ } split /,/sm, $line;                         ## no critic qw[ControlStructures::ProhibitMutatingListFunctions]

#                                             delete $item->{_};

#                                             push $items->@*, $item;
#                                         }

#                                         $cb->( result 200, $items );
#                                     }

#                                     return;
#                                 }
#                             );
#                         }
#                         else {
#                             $cb->( result [ 400, 'Job not ready' ] );
#                         }
#                     }
#                     else {
#                         $cb->( result [ 404, 'Job not found' ] );
#                     }
#                 }

#                 return;
#             }
#         );
#     } );

#     return;
# }

# sub _login ( $self, $cb ) {

#     # login is valid for 1 day
#     if ( $self->{_cookies} && $self->{_cookies_time} + 60 * 60 * 24 > time ) {
#         $cb->( result 200, $self->{_cookies} );
#     }
#     else {
#         push $self->{_login_requests}->@*, $cb;

#         return if $self->{_login_requests}->@* > 1;

#         state $on_finish = sub ( $self, $res ) {
#             while ( my $cb = shift $self->{_login_requests}->@* ) {
#                 AE::postpone { $cb->($res) };
#             }

#             return;
#         };

#         my $cookies = {};

#         P->http->post(
#             'https://majestic.com/account/login',
#             useragent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:53.0) Gecko/20100101 Firefox/53.0',
#             cookies   => $cookies,
#             headers   => { CONTENT_TYPE => 'application/x-www-form-urlencoded' },
#             body      => P->data->to_uri( { EmailAddress => $self->{username}, Password => $self->{password}, RememberMe => 1 } ),
#             on_finish => sub ($res) {
#                 if ( !$res ) {
#                     undef $self->{_cookies};

#                     $on_finish->( $self, result [ 500, 'Login error' ] );
#                 }
#                 elsif ( $res->decoded_body->$* =~ /in a lot today/sm ) {
#                     undef $self->{_cookies};

#                     $on_finish->( $self, result [ 500, 'Login error - captcha' ] );
#                 }
#                 else {
#                     $self->{_cookies} = $cookies;

#                     $self->{_cookies_time} = time;

#                     $on_finish->( $self, result 200, $cookies );
#                 }

#                 return;
#             }
#         );
#     }

#     return;
# }

sub _req ( $self, $params ) {
    my $guard = $self->{max_threads} && $self->_semaphore->guard;

    my $url = 'https://api.majestic.com/api/json?';

    if ( $self->{api_key} ) {
        $url .= "app_api_key=$self->{api_key}&";
    }
    elsif ( $self->{openapp_private_key} && $self->{openapp_access_token} ) {
        $url .= "accesstoken=$self->{openapp_access_token}&privatekey=$self->{openapp_private_key}&";
    }

    $url .= to_uri $params;

    my $res = P->http->get( $url, proxy => $self->{proxy} );

    if ($res) {
        my $data = eval { from_json $res->{data} };

        if ($@) {
            $res = res [ 500, 'Error decoding response' ];
        }
        elsif ( $data->{Code} ne 'OK' ) {
            $res = res [ 400, $data->{ErrorMessage} ];
        }
        else {
            $res = res 200, $data;
        }
    }

    return $res;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::majestic

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
