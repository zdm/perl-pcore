package Pcore::API::namecheap;

use Pcore -class, -res;

has api_user => ( required => 1 );
has api_key  => ( required => 1 );
has api_ip   => ( required => 1 );
has proxy    => ();

# https://www.namecheap.com/support/api/methods/domains/get-tld-list.aspx
sub get_tld_list ($self) {

    # my $url_params = [
    #     ApiUser  => $self->{api_user},
    #     ApiKey   => $self->{api_key},
    #     ClientIp => $self->{api_ip},
    #     UserName => $self->{api_user},
    #     Command  => 'namecheap.domains.gettldlist',
    # ];

    # my $url = 'https://api.namecheap.com/xml.response?' . P->data->to_uri($url_params);

    # P->http->get(
    #     $url,
    #     persistent => 0,
    #     timeout    => 180,
    #     recurse    => 0,
    #     bind_ip    => $self->{bind_ip},
    #     on_finish  => sub ($res) {
    #         if ( $res->status != 200 ) {
    #             $cb->( result [ $res->status, $res->reason ] );

    #             return;
    #         }

    #         my $hash = eval { P->data->from_xml( $res->body ) };

    #         if ($@) {
    #             $cb->( result [ $res->status, 'Error decoding response' ] );

    #             return;
    #         }

    #         if ( $hash->{ApiResponse}->{Errors}->[0]->{Error} ) {
    #             $cb->( result [ 400, $hash->{ApiResponse}->{Errors}->[0]->{Error}->[0]->{content} ] );

    #             return;
    #         }

    #         my $data;

    #         for my $tld ( $hash->{ApiResponse}->{CommandResponse}->[0]->{Tlds}->[0]->{Tld}->@* ) {
    #             delete $tld->{content};

    #             my $res;

    #             for my $attr ( keys $tld->%* ) {
    #                 $res->{$attr} = $tld->{$attr}->[0]->{content};

    #                 if ( defined $res->{$attr} ) {
    #                     if ( $res->{$attr} eq 'true' ) {
    #                         $res->{$attr} = 1;
    #                     }
    #                     elsif ( $res->{$attr} eq 'false' ) {
    #                         $res->{$attr} = 0;
    #                     }
    #                 }
    #             }

    #             $data->{ $tld->{Name}->[0]->{content} } = $res;
    #         }

    #         $TLD = $data;

    #         $ENV->share->store( '/data/namecheap-tld.json', $TLD, 'Lazarus-Crawler-Client' );

    #         $cb->( result 200, $TLD );

    #         return;
    #     },
    # );

    return;
}

# https://www.namecheap.com/support/api/methods/domains/check.aspx
# NOTE max 100 domains are allowed, 30 is recommneded
sub check_domains ( $self, $domains ) {
    my $params = {
        Command    => 'namecheap.domains.check',
        DomainList => join( ',', $domains->@* ),
    };

    my $res = $self->_req($params);

    # for my $domain ( $hash->{ApiResponse}->{CommandResponse}->[0]->{DomainCheckResult}->@* ) {
    #     my $domain_name = $domain->{Domain}->[0]->{content};

    #     if ( $domain->{Available}->[0]->{content} eq 'true' ) {
    #         $data->{$domain_name} = 1;
    #     }
    #     else {
    #         $data->{$domain_name} = 0;
    #     }
    # }

    return $res;
}

sub _req ( $self, $params ) {
    my $url_params = {
        ApiUser  => $self->{api_user},
        ApiKey   => $self->{api_key},
        ClientIp => $self->{api_ip},
        UserName => $self->{api_user},
        $params->%*
    };

    my $res = P->http->get(
        'https://api.namecheap.com/xml.response?' . P->data->to_uri($url_params),
        timeout => 60,
        proxy   => $self->{proxy},
    );

    say dump $res;

    return res $res if !$res;

    my $data = eval { P->data->from_xml( $res->{data} ) };

    return res [ 500, 'Error decoding xml' ] if $@;

    return res [ 400, $data->{ApiResponse}->{Errors}->[0]->{Error}->[0]->{content} ] if $data->{ApiResponse}->{Errors}->[0]->{Error};

    return res 200, $data->{ApiResponse}->{CommandResponse}->[0];
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::namecheap

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
