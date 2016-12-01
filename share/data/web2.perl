# 'host.tld' => {
#     path   => 1,          # path based web2 url
#     scheme => 'https',    # default scheme
#     status => 404,        # not available response status
#     re     => undef,      # not available response body pattern
# };

{   'tumblr.com' => {
        status => 404,
        re     => qr[Whatever\syou\swere\slooking\sfor\sdoesn't\scurrently\sexist]smi,
    },
    'blogspot' => {
        status => 404,
        re     => qr[is\savailable\sto\sregister]smi,
    },
    'livejournal.com' => {
        status => 404,
        re     => qr[is\snot\scurrently\sregistered]smi,
    },
    'weebly.com' => {
        status => 404,
        re     => undef,
    },
    'over-blog.com' => {
        status => undef,
        re     => qr[Erreur\s+404\s+Page\s+non\s+trouvée]smi,
    },
    'wordpress.com' => {
        status => undef,
        re     => qr[[.]wordpress[.]com</em> doesn\&\#8217;t\&nbsp;exist</h2>]smi,
    },
    'bravehost.com' => {
        status => undef,
        re     => qr[<title>Available\sWebsite</title>]smi,
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
        status => 302,
        re     => undef,
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
        re     => undef,
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
        status => 404,
        re     => qr[But this address is available for your new website!]smi,
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
        status => 302,
        re     => undef,
    },
    'hautetfort.com' => {
        status => 404,
        re     => undef,
    },

    # path - based web2 subdomains
    'journalhome.com' => {
        path   => 1,
        status => 400,
        re     => qr[The\sweblog,\spage\sor\sarticle\syou\sare\slooking\sfor\scould\snot\sbe\slocated]smi,
    },
    'purevolume.com' => {
        path   => 1,
        status => 301,
        re     => qr[Page\sNot\sFound]smi,
    },
    'webjam.com' => {
        path   => 1,
        status => 200,
        re     => qr[(error\s404)]smi,
    },
    'blogster.com' => {
        path   => 1,
        status => undef,
        re     => qr[this\swill\sbe\sa\sreal\s404\serror\sonce\si\sdecide\sthe\skinks\sare\sworked\sout]smi,
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
## |    3 | 86, 98, 118, 137,    | RegularExpressions::ProhibitComplexRegexes - Split long regexps into smaller qr// chunks                       |
## |      | 152                  |                                                                                                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
