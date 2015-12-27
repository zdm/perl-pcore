package Pcore::AE::Crawler::Request::GoogleSearch;

use Pcore -class;
use Pcore::Util::Text qw[decode_eol decode_html_entities];
use HTML::LinkExtor qw[];
use Pcore::Captcha::Antigate;

with qw[Pcore::AE::Crawler::Request];
extends qw[Pcore::HTTP::Request];

has start => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );
has num   => ( is => 'ro', isa => PositiveInt,       default => 100 );
has captcha_api_key => ( is => 'ro', isa => Str );

has _captcha => ( is => 'lazy', isa => InstanceOf ['Pcore::Captcha::Antigate'], init_arg => undef );

has _ua => ( is => 'lazy', default => sub { P->ua->new( { useragent => 'Links (2.1; Linux 2.6.18-gentoo-r6 x86_64; 80x24)', cookie_jar => 1 } ) }, init_arg => undef );

no Pcore;

our $_CAPTCHA_LOCKED = 0;

sub _build_type {
    my $self = shift;

    return 'google';
}

sub _build__captcha {
    my $self = shift;

    return Pcore::Captcha::Antigate->new( { api_key => $self->captcha_api_key } );
}

sub process_response ( $self, $res ) {
    if ( $res->status == 200 ) {    # success
        $self->_process_content( $res->body );
    }
    elsif ( $res->status == 503 ) {    # captcha
        if ( $self->captcha_api_key ) {
            return sub {
                my $responder = shift;

                $self->_resolve_captcha( $responder, $res );    # resolve captcha

                return;
            };
        }
    }

    return;
}

# PARSERS
sub _process_content ( $self, $content_ref ) {
    decode_eol $content_ref->$*;

    $content_ref->$* =~ s/\n//smg;                                                     # remove \n
    $content_ref->$* =~ s[\A.+(<body[^>]*>.+?</body[^>]*>).*\z][$1]sm;                 # leave only <body>...</body> content
    $content_ref->$* =~ s[<(?:script|style)[^>]*>.+?</(?:script|style)[^>]*>][]smg;    # remove <script>...</script>, <style>...</style>

    # parse total results
    $self->results->{total} = $self->_parse_total_results($content_ref);

    # parse results
    $self->results->{results} = $self->_parse_results($content_ref);

    # parse related searches
    $self->results->{related} = $self->_parse_related_searches($content_ref);

    # parse pages navigation
    $self->results->{pages} = $self->_parse_pages($content_ref);

    return;
}

sub _parse_total_results {
    my $self        = shift;
    my $content_ref = shift;

    my ($total) = $content_ref->$* =~ m[<div.*?id="resultStats"[^>]*>.+?([\d.,]+?)\sresults</div>]sm;

    return $total ? $total =~ s/[.,]//smgr : undef;
}

sub _parse_results {
    my $self        = shift;
    my $content_ref = shift;

    my ($search) = $content_ref->$* =~ m[<div id="search">.*?<ol>(.+?)</ol>]sm;

    if ($search) {
        if ( my @results = split m[<li class="g">]sm, $search ) {
            my $search_results = [];

            for my $result (@results) {
                my ( $href, $title ) = $result =~ m[<h\d[^>]*><a.*?href="(/url[^"]+?)"[^>]*>(.+?)</a>]sm;    # ignore url to google map

                if ( $href && $title ) {
                    $self->_remove_tags( \$title );                                                          # remove tags

                    my ($desc) = $result =~ m[<span class="st">(.+)?</span>]sm;

                    $self->_remove_tags( \$desc ) if $desc;

                    push $search_results,
                      { title => $title,
                        desc  => $desc,
                        href  => $href,
                      };
                }
            }

            return $search_results;
        }
    }

    return;
}

sub _parse_related_searches {
    my $self        = shift;
    my $content_ref = shift;

    my ($related) = $content_ref->$* =~ m[Searches related to.+?<table[^>]*>(.+?)</table[^>]*>]sm;

    if ($related) {
        if ( my @links = $related =~ m[<a\s[^>]*>(.+?)</a>]smg ) {
            for my $link (@links) {
                $self->_remove_tags( \$link );    # remove tags
            }

            return \@links;
        }
    }

    return;
}

sub _parse_pages {
    my $self        = shift;
    my $content_ref = shift;

    my ($nav) = $content_ref->$* =~ m[<table.*?id="nav"[^>]*>(.+?)</table[^>]*>]sm;

    if ($nav) {
        my $links = HTML::LinkExtor->new(undef);
        $links->parse($nav);

        my $start = {};

        for my $link ( $links->links ) {
            my ($start_pos) = $link->[2] =~ m[&start=(\d+)]sm;

            if ( defined $start_pos ) {
                $start->{$start_pos} = 1;
            }
        }

        return [ sort keys $start ];
    }

    return;
}

# UTIL
sub _remove_tags {
    my $self = shift;
    my $str  = shift;

    try {
        decode_html_entities $str->$*;
    };

    $str->$* =~ s[<[^>]+?>][]smg;    # remove tags

    return;
}

# CAPTCHA
sub _resolve_captcha ( $self, $responder, $res ) {
    if ( !$_CAPTCHA_LOCKED ) {
        $_CAPTCHA_LOCKED = 1;

        my ($id) = $res->body->$* =~ m[name="id" value="(\d+)"]sm;

        my ($continue) = $res->body->$* =~ m[name="continue" value="([^"]+)"]sm;

        $self->_get_captcha_image(
            $id,
            $res->url,
            sub ($image_ref) {
                $self->_captcha->add(
                    captcha => $image_ref,
                    cb      => sub ($captcha) {
                        if ( $captcha->error ) {
                            $_CAPTCHA_LOCKED = 0;

                            # reload captcha image
                            $self->_resolve_captcha( $responder, $res );
                        }
                        else {
                            $self->_verify_captcha( $responder, $captcha, $res->url, $id, $continue );
                        }

                        return;
                    },
                );

                return;
            }
        );
    }
    else {
        my $t;

        my $create_timer;

        my $timer_cb = sub {
            undef $t;

            if ($_CAPTCHA_LOCKED) {
                $create_timer->();
            }
            else {
                $responder->( $self->repeat );
            }

            return;
        };

        $create_timer = sub {
            $t = AE::timer 3, undef, $timer_cb;

            return;
        };

        $create_timer->();
    }

    return;
}

sub _get_captcha_image ( $self, $id, $url, $cb ) {
    my $uri = P->uri( '/sorry/image', base => $url );

    $self->_ua->request(
        $uri->to_string . qq[?id=$id&hl=en],
        on_finish => sub ($res) {
            $cb->( $res->body );

            return;
        },
    );

    return;
}

sub _verify_captcha ( $self, $responder, $captcha, $url, $id, $continue ) {
    my $uri = P->uri( '/sorry/CaptchaRedirect', base => $url );

    $self->_ua->request(
        $uri->to_string . qq[?continue=$continue&id=$id&submit=Submit&captcha=] . $captcha->result,
        on_finish => sub ($res) {
            if ( $res->status == 503 ) {    # captcha recognized incorrectly
                $self->_captcha->report_failure($captcha);

                $self->_resolve_captcha( $responder, $res );
            }
            else {
                $self->_process_content( $res->body );

                $self->res->set_status( $res->status );

                $self->res->set_reason( $res->reason );

                $responder->( $self->done );

                $_CAPTCHA_LOCKED = 0;
            }

            return;
        },
    );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 258                  │ Subroutines::ProhibitManyArgs - Too many arguments                                                             │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
