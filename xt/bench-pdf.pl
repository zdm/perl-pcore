#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Pcore::API::PDF;
use Benchmark;

my $pdf = Pcore::API::PDF->new(
    bin         => $MSWIN ? "$ENV->{DATA_DIR}/prince-12-win64/bin/prince.exe" : 'princexml',
    max_threads => 4,
);

my $html = <<'HTML';
<!doctype html>
<html>
<head>
    <title>Example Domain</title>

    <meta charset="utf-8" />
    <meta http-equiv="Content-type" content="text/html; charset=utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style type="text/css">
    body {
        background-color: #f0f0f2;
        margin: 0;
        padding: 0;
        font-family: "Open Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;

    }
    div {
        width: 600px;
        margin: 5em auto;
        padding: 50px;
        background-color: #fff;
        border-radius: 1em;
    }
    a:link, a:visited {
        color: #38488f;
        text-decoration: none;
    }
    @media (max-width: 700px) {
        body {
            background-color: #fff;
        }
        div {
            width: auto;
            margin: 0 auto;
            border-radius: 0;
            padding: 1em;
        }
    }
    </style>
</head>

<body>
<div>
    <h1>Example Domain</h1>
    <p>This domain is established to be used for illustrative examples in documents. You may use this
    domain in examples without prior coordination or asking for permission.</p>
    <p><a href="http://www.iana.org/domains/example">More information...</a></p>
</div>
</body>
</html>
HTML

my $t0 = time;

my $cv = P->cv->begin;

for ( 1 .. 10 ) {
    $cv->begin;
    $pdf->generate_pdf(
        \$html,
        sub ($res) {

            say $res;

            # P->file->write_bin('1.pdf', $res->{data});exit;

            $cv->end;

            return;
        }
    );
}

$cv->end;

$cv->recv;

say time - $t0;

1;
__END__
=pod

=encoding utf8

=cut
