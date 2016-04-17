# 'host.tld' => {
#     path   => 1,          # path based web2 url
#     scheme => 'https',    # default scheme
#     status => 404,        # not available response status
#     re     => undef,      # not available response body pattern
# };

{   'tumblr.com' => {
        status => undef,
        re     => qr[<p data-translation="message">Whatever you were looking for doesn't currently exist at this address[.] Unless you were looking for this error page, in which case: Congrats! You totally found it[.]]smi,
    },
    'blogspot' => {
        status => 404,
        re     => undef,
    },
    'livejournal.com' => {
        status => undef,
        re     => qr[The\s+journal\s+<b>.+?</b>\s+is\s+not\s+currently\s+registered]smi,
    },
    'weebly.com' => {
        status => undef,
        re     => qr[<div class="alert-heading">Site Not Published</div>]smi,
    },
    'over-blog.com' => {
        status => undef,
        re     => qr[Erreur\s+404\s+Page\s+non\s+trouvée]smi,
    },
    'wordpress.com' => {
        status => undef,
        re     => qr[[.]wordpress[.]com</em> doesn\&\#8217;t\&nbsp;exist</h2>]smi,
    },
    'bravenet.com' => {
        status => undef,
        re     => qr[<title>Page\sNot\sFound</title>]smi,
    },
    'jimdo.com' => {
        status => 403,
        re     => undef,
    },
    'newsvine.com' => {
        status => 404,
        re     => undef,
    },
    'typepad.com' => {
        status => 404,
        re     => undef,
    },
    'webs.com' => {
        status => 404,
        re     => undef,
    },
    'hubpages.com' => {
        status => 404,
        re     => undef,
    },
    'wikidot.com' => {
        status => 404,
        re     => undef,
    },
    'xanga.com' => {
        status => undef,
        re     => qr[We\saren't\sshowing\sany\sblog\sarchives\ssaved\sfor\sthis\spage]smi,
    },
    'skyrock.com' => {
        status => 404,
        re     => undef,
    },
    'jigsy.com' => {
        status => 404,
        re     => undef,
    },
    'snappages.com' => {
        status => 404,
        re     => undef,
    },
    'bravesites.com' => {
        status => 404,
        re     => qr[<title>Available\sWebsite</title>]smi,
    },
    'startlogic.com' => {
        status => 404,
        re     => undef,
    },
    'thoughts.com' => {
        status => undef,
        re     => qr[<h1>Share your thoughts and connect with like minded people[.]</h1>]smi,
    },
    'diaryland.com' => {
        status => 404,
        re     => undef,
    },
    'webnode.com' => {
        status => undef,
        re     => qr[exist[.]\sBut\sthis\saddress\sis\savailable\sfor\syour\snew\swebsite!]smi,
    },
    'moonfruit.com' => {
        status => 404,
        re     => qr[Click\sbelow\sto\sstart\sbuilding\syour\snew\swebsite,\sshop\sor\sblog]smi,
    },
    'ucoz.com' => {
        status => 404,
        re     => undef,
    },
    'sitew.com' => {
        status => 404,
        re     => undef,
    },
    'webstarts.com' => {
        status => 404,
        re     => undef,
    },
    'beep.com' => {
        status => 404,
        re     => qr[Do\syou\swant\syour\sown\sfree\swebsite]smi,
    },
    'pen.io' => {
        status => undef,
        re     => qr[<input\splaceholder="your-page-url"\stype="text"\sid="page-name"\sname="page_name"\s/>]smi,
    },
    'blinkweb.com' => {
        status => 404,
        re     => undef,
    },
    'hpage.com' => {
        status => 404,
        re     => undef,
    },
    'hautetfort.com' => {
        status => 404,
        re     => undef,
    },

    # path - based web2 subdomains
    'journalhome.com' => {
        path   => 1,
        status => 404,
        re     => undef,
    },
    'purevolume.com' => {
        path   => 1,
        status => 404,
        re     => undef,
    },
    'webjam.com' => {
        path   => 1,
        status => 404,
        re     => undef,
    },
    'blogster.com' => {
        path   => 1,
        status => undef,
        re     => qr[unknown\s+realm]smi,
    },
    'twitter.com' => {
        path   => 1,
        scheme => 'https',
        status => 404,
        re     => undef,
    },
}
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-config" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 10, 18, 62, 86, 94,  | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |      | 98, 118              |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
