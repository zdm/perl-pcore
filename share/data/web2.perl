{   'tumblr.com' => {
        status => undef,
        host   => undef,
        re     => qr[<p data-translation="message">Whatever you were looking for doesn't currently exist at this address[.] Unless you were looking for this error page, in which case: Congrats! You totally found it[.]]smi,
    },
    'blogspot' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'livejournal.com' => {
        status => undef,
        host   => undef,
        re     => qr[The\s+journal\s+<b>.+?</b>\s+is\s+not\s+currently\s+registered]smi,
    },
    'weebly.com' => {
        status => undef,
        host   => undef,
        re     => qr[<div class="alert-heading">Site Not Published</div>]smi,
    },
    'over-blog.com' => {
        status => undef,
        host   => undef,
        re     => qr[Erreur\s+404\s+Page\s+non\s+trouvée]smi,
    },
    'wordpress.org' => {
        status => undef,
        host   => 'wordpress.org',
        re     => undef,
    },
    'bravenet.com' => {
        status => undef,
        host   => undef,
        re     => qr[<title>Page\sNot\sFound</title>]smi,
    },
    'jimdo.com' => {
        status => 403,
        host   => undef,
        re     => undef,
    },
    'newsvine.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'wix.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'typepad.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'webs.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'hubpages.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'wikidot.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'xanga.com' => {
        status => undef,
        host   => undef,
        re     => qr[We\saren't\sshowing\sany\sblog\sarchives\ssaved\sfor\sthis\spage]smi,
    },
    'skyrock.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'jigsy.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'snappages.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'bravesites.com' => {
        status => 404,
        host   => undef,
        re     => qr[<title>Available\sWebsite</title>]smi,
    },
    'startlogic.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'thoughts.com' => {
        status => undef,
        host   => 'thoughts.com',
        re     => undef,
    },
    'diaryland.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'webnode.com' => {
        status => undef,
        host   => undef,
        re     => qr[exist[.]\sBut\sthis\saddress\sis\savailable\sfor\syour\snew\swebsite!]smi,
    },
    'moonfruit.com' => {
        status => 404,
        host   => undef,
        re     => qr[Click\sbelow\sto\sstart\sbuilding\syour\snew\swebsite,\sshop\sor\sblog]smi,
    },
    'ucoz.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'sitew.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'webstarts.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'beep.com' => {
        status => 404,
        host   => undef,
        re     => qr[Do\syou\swant\syour\sown\sfree\swebsite]smi,
    },
    'pen.io' => {
        status => undef,
        host   => undef,
        re     => qr[<input\splaceholder="your-page-url"\stype="text"\sid="page-name"\sname="page_name"\s/>]smi,
    },
    'blinkweb.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'hpage.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },
    'hautetfort.com' => {
        status => 404,
        host   => undef,
        re     => undef,
    },

    # path - based web2 subdomains
    'journalhome.com' => {
        path_subdomain => 1,
        status         => 404,
        host           => undef,
        re             => undef,
    },
    'purevolume.com' => {
        path_subdomain => 1,
        status         => 404,
        host           => undef,
        re             => undef,
    },
    'webjam.com' => {
        path_subdomain => 1,
        status         => 404,
        host           => undef,
        re             => undef,
    },
    'blogster.com' => {
        path_subdomain => 1,
        status         => undef,
        host           => undef,
        re             => qr[unknown\s+realm]smi,
    },
    'twitter.com' => {
        path_subdomain => 1,
        scheme         => 'https',
        status         => 404,
        host           => undef,
        re             => undef,
    },
}
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-config" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 4, 14, 74, 114, 119, │ RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       │
## │      │ 144                  │                                                                                                                │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
