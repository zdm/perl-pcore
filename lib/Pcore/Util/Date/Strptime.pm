package Pcore::Util::Date::Strptime;

use Pcore -class, -const;

# %a - the abbreviated weekday name ('Sun')
# %A - the full weekday  name ('Sunday')
# %b - the abbreviated month name ('Jan')
# %B - the full  month  name ('January')
# %c - the preferred local date and time representation
# %d - day of the month (01..31)
# %e - day of the month without leading zeroes (1..31)
# %H - hour of the day, 24-hour clock (00..23)
# %I - hour of the day, 12-hour clock (01..12)
# %j - day of the year (001..366)
# %k - hour of the day, 24-hour clock w/o leading zeroes ( 0..23)
# %l - hour of the day, 12-hour clock w/o leading zeroes ( 1..12)
# %m - month of the year (01..12)
# %M - minute of the hour (00..59)
# %p - meridian indicator ('AM'  or  'PM')
# %P - meridian indicator ('am'  or  'pm')
# %S - second of the minute (00..60)
# %U - week number  of the current year, starting with the first Sunday as the first day of the first week (00..53)
# %W - week number  of the current year, starting with the first Monday as the first day of the first week (00..53)
# %w - day of the week (Sunday is 0, 0..6)
# %x - preferred representation for the date alone, no time
# %X - preferred representation for the time alone, no date
# %y - year without a century (00..99)
# %Y - year with century
# %Z - time zone name
# %z - +/- hhmm or hh:mm
# %% - literal '%' character

const our $WEEKDAY => [qw[monday tuesday wednesday thursday friday saturday sunday]];

const our $WEEKDAY_ABBR => [qw[mon tue wed thu fri sat sun]];

const our $MONTH => [qw[january february march april may june july august september october november december]];

const our $MONTH_ABBR => [qw[jan feb mar apr may jun jul aug sep oct nov dec]];

const our $MONTH_NUM => { map { $_ => state $i++ + 1 } $MONTH->@* };

const our $MONTH_ABBR_NUM => { map { $_ => state $i++ + 1 } $MONTH_ABBR->@* };

const our $TIMEZONE => {
    a      => '+0100',
    acdt   => '+1030',
    acst   => '+0930',
    adt    => undef,
    aedt   => '+1100',
    aes    => '+1000',
    aest   => '+1000',
    aft    => '+0430',
    ahdt   => '-0900',
    ahst   => '-1000',
    akdt   => '-0800',
    akst   => '-0900',
    amst   => '+0400',
    amt    => '+0400',
    anast  => '+1300',
    anat   => '+1200',
    art    => '-0300',
    ast    => undef,
    at     => '-0100',
    awst   => '+0800',
    azost  => '+0000',
    azot   => '-0100',
    azst   => '+0500',
    azt    => '+0400',
    b      => '+0200',
    badt   => '+0400',
    bat    => '+0600',
    bdst   => '+0200',
    bdt    => '+0600',
    bet    => '-1100',
    bnt    => '+0800',
    bort   => '+0800',
    bot    => '-0400',
    bra    => '-0300',
    bst    => undef,
    bt     => undef,
    btt    => '+0600',
    c      => '+0300',
    cast   => '+0930',
    cat    => undef,
    cct    => undef,
    cdt    => undef,
    cest   => '+0200',
    cet    => '+0100',
    cetdst => '+0200',
    chadt  => '+1345',
    chast  => '+1245',
    ckt    => '-1000',
    clst   => '-0300',
    clt    => '-0400',
    cot    => '-0500',
    cst    => undef,
    csut   => '+1030',
    cut    => '+0000',
    cvt    => '-0100',
    cxt    => '+0700',
    chst   => '+1000',
    d      => '+0400',
    davt   => '+0700',
    ddut   => '+1000',
    dnt    => '+0100',
    dst    => '+0200',
    e      => '+0500',
    easst  => '-0500',
    east   => undef,
    eat    => '+0300',
    ect    => undef,
    edt    => undef,
    eest   => '+0300',
    eet    => '+0200',
    eetdst => '+0300',
    egst   => '+0000',
    egt    => '-0100',
    emt    => '+0100',
    est    => undef,
    esut   => '+1100',
    f      => '+0600',
    fdt    => undef,
    fjst   => '+1300',
    fjt    => '+1200',
    fkst   => '-0300',
    fkt    => '-0400',
    fst    => undef,
    fwt    => '+0100',
    g      => '+0700',
    galt   => '-0600',
    gamt   => '-0900',
    gest   => '+0500',
    get    => '+0400',
    gft    => '-0300',
    gilt   => '+1200',
    gmt    => '+0000',
    gst    => undef,
    gt     => '+0000',
    gyt    => '-0400',
    gz     => '+0000',
    h      => '+0800',
    haa    => '-0300',
    hac    => '-0500',
    hae    => '-0400',
    hap    => '-0700',
    har    => '-0600',
    hat    => '-0230',
    hay    => '-0800',
    hdt    => '-0930',
    hfe    => '+0200',
    hfh    => '+0100',
    hg     => '+0000',
    hkt    => '+0800',
    hl     => undef,     # 'local',
    hna    => '-0400',
    hnc    => '-0600',
    hne    => '-0500',
    hnp    => '-0800',
    hnr    => '-0700',
    hnt    => '-0330',
    hny    => '-0900',
    hoe    => '+0100',
    hst    => '-1000',
    i      => '+0900',
    ict    => '+0700',
    idle   => '+1200',
    idlw   => '-1200',
    idt    => undef,
    iot    => '+0500',
    irdt   => '+0430',
    irkst  => '+0900',
    irkt   => '+0800',
    irst   => '+0430',
    irt    => '+0330',
    ist    => undef,
    it     => '+0330',
    ita    => '+0100',
    javt   => '+0700',
    jayt   => '+0900',
    jst    => '+0900',
    jt     => '+0700',
    k      => '+1000',
    kdt    => '+1000',
    kgst   => '+0600',
    kgt    => '+0500',
    kost   => '+1200',
    krast  => '+0800',
    krat   => '+0700',
    kst    => '+0900',
    l      => '+1100',
    lhdt   => '+1100',
    lhst   => '+1030',
    ligt   => '+1000',
    lint   => '+1400',
    lkt    => '+0600',
    lst    => undef,     # 'local',
    lt     => undef,     # 'local',
    m      => '+1200',
    magst  => '+1200',
    magt   => '+1100',
    mal    => '+0800',
    mart   => '-0930',
    mat    => '+0300',
    mawt   => '+0600',
    mdt    => '-0600',
    med    => '+0200',
    medst  => '+0200',
    mest   => '+0200',
    mesz   => '+0200',
    met    => undef,
    mewt   => '+0100',
    mex    => '-0600',
    mez    => '+0100',
    mht    => '+1200',
    mmt    => '+0630',
    mpt    => '+1000',
    msd    => '+0400',
    msk    => '+0300',
    msks   => '+0400',
    mst    => '-0700',
    mt     => '+0830',
    mut    => '+0400',
    mvt    => '+0500',
    myt    => '+0800',
    n      => '-0100',
    nct    => '+1100',
    ndt    => '-0230',
    nft    => undef,
    nor    => '+0100',
    novst  => '+0700',
    novt   => '+0600',
    npt    => '+0545',
    nrt    => '+1200',
    nst    => undef,
    nsut   => '+0630',
    nt     => '-1100',
    nut    => '-1100',
    nzdt   => '+1300',
    nzst   => '+1200',
    nzt    => '+1200',
    o      => '-0200',
    oesz   => '+0300',
    oez    => '+0200',
    omsst  => '+0700',
    omst   => '+0600',
    oz     => undef,     # 'local',
    p      => '-0300',
    pdt    => '-0700',
    pet    => '-0500',
    petst  => '+1300',
    pett   => '+1200',
    pgt    => '+1000',
    phot   => '+1300',
    pht    => '+0800',
    pkt    => '+0500',
    pmdt   => '-0200',
    pmt    => '-0300',
    pnt    => '-0830',
    pont   => '+1100',
    pst    => undef,
    pwt    => '+0900',
    pyst   => '-0300',
    pyt    => '-0400',
    q      => '-0400',
    r      => '-0500',
    r1t    => '+0200',
    r2t    => '+0300',
    ret    => '+0400',
    rok    => '+0900',
    s      => '-0600',
    sadt   => '+1030',
    sast   => undef,
    sbt    => '+1100',
    sct    => '+0400',
    set    => '+0100',
    sgt    => '+0800',
    srt    => '-0300',
    sst    => undef,
    swt    => '+0100',
    t      => '-0700',
    tft    => '+0500',
    tha    => '+0700',
    that   => '-1000',
    tjt    => '+0500',
    tkt    => '-1000',
    tmt    => '+0500',
    tot    => '+1300',
    trut   => '+1000',
    tst    => '+0300',
    tuc    => '+0000',
    tvt    => '+1200',
    u      => '-0800',
    ulast  => '+0900',
    ulat   => '+0800',
    usz1   => '+0200',
    usz1s  => '+0300',
    usz3   => '+0400',
    usz3s  => '+0500',
    usz4   => '+0500',
    usz4s  => '+0600',
    usz5   => '+0600',
    usz5s  => '+0700',
    usz6   => '+0700',
    usz6s  => '+0800',
    usz7   => '+0800',
    usz7s  => '+0900',
    usz8   => '+0900',
    usz8s  => '+1000',
    usz9   => '+1000',
    usz9s  => '+1100',
    utz    => '-0300',
    uyt    => '-0300',
    uz10   => '+1100',
    uz10s  => '+1200',
    uz11   => '+1200',
    uz11s  => '+1300',
    uz12   => '+1200',
    uz12s  => '+1300',
    uzt    => '+0500',
    v      => '-0900',
    vet    => '-0400',
    vlast  => '+1100',
    vlat   => '+1000',
    vtz    => '-0200',
    vut    => '+1100',
    w      => '-1000',
    wakt   => '+1200',
    wast   => undef,
    wat    => '+0100',
    west   => '+0100',
    wesz   => '+0100',
    wet    => '+0000',
    wetdst => '+0100',
    wez    => '+0000',
    wft    => '+1200',
    wgst   => '-0200',
    wgt    => '-0300',
    wib    => '+0700',
    wit    => '+0900',
    wita   => '+0800',
    wst    => undef,
    wtz    => '-0100',
    wut    => '+0100',
    x      => '-1100',
    y      => '-1200',
    yakst  => '+1000',
    yakt   => '+0900',
    yapt   => '+1000',
    ydt    => '-0800',
    yekst  => '+0600',
    yekt   => '+0500',
    yst    => '-0900',
    z      => '+0000',
    utc    => '+0000',
};

const our $OFFSET => { map { $_ => abs $TIMEZONE->{$_} >= 100 ? ( int( abs $TIMEZONE->{$_} / 100 ) * 60 + abs( $TIMEZONE->{$_} ) % 100 ) / ( $TIMEZONE->{$_} < 0 ? -1 : 1 ) : $TIMEZONE->{$_} } grep { defined $TIMEZONE->{$_} } keys $TIMEZONE->%* };

# TODO shortcuts for directly supported Time::Moment strings
const our $STRPTIME_TOKEN => {
    a => [ join( q[|], $WEEKDAY_ABBR->@* ) ],                                 # the abbreviated weekday name ('Sun')
    A => [ join( q[|], sort $WEEKDAY->@* ) ],                                 # the full weekday  name ('Sunday')
    b => [ join( q[|], sort $MONTH_ABBR->@* ), 'month', $MONTH_ABBR_NUM ],    # the abbreviated month name ('Jan')
    B => [ join( q[|], sort $MONTH->@* ), 'month', $MONTH_NUM ],              # the full  month  name ('January')
    d => [ '\d\d',     'day' ],                                               # day of the month (01..31)
    H => [ '\d\d',     'hour' ],                                              # hour of the day, 24-hour clock (00..23)
    m => [ '\d\d',     'month' ],                                             # month of the year (01..12)
    M => [ '\d\d',     'minute' ],                                            # minute of the hour (00..59)
    S => [ '\d\d',     'second' ],                                            # second of the minute (00..60)
    y => [ '\d\d',     'year', sub { $_ += $_ >= 69 ? 1900 : 2000 } ],        # year without a century (00..99)
    Y => [ '\d\d\d\d', 'year' ],                                              # year with century
    Z => [ join( q[|], sort { length $b <=> length $a } grep { defined $OFFSET->{$_} } keys $OFFSET->%* ), 'offset', $OFFSET ],    # time zone name
    z => [ '[+-]\d\d:?\d\d', 'offset', sub { s/://sm; $_ = ( int( abs $_ / 100 ) * 60 + abs %100 ) / ( $_ < 0 ? -1 : 1 ) if abs >= 100 } ],    # +/-hhmm, +/-hh:mm
};

sub strptime_compile_pattern ( $self, $pattern, $use_cache = 1 ) {
    state $split_re = qr/%([@{[ join q[|], keys $STRPTIME_TOKEN->%* ]}])/smo;

    state $cache = {};

    return $cache->{$pattern} if $use_cache and $cache->{$pattern};

    my $res;

    my ( $re, $map, $coerce );

    my $match_id = 0;

    for my $token ( split $split_re, $pattern ) {
        if ( !exists $STRPTIME_TOKEN->{$token} ) {
            $re .= fc $token;
        }
        else {
            $re .= "($STRPTIME_TOKEN->{$token}->[0])";

            if ( my $attr = $STRPTIME_TOKEN->{$token}->[1] ) {

                # adding new attr or replacing old attr with the new without coercion
                if ( !$map->{$attr} || ( $coerce->{$attr} && !$STRPTIME_TOKEN->{$token}->[2] ) ) {
                    $map->{$attr} = $match_id;

                    if ( $STRPTIME_TOKEN->{$token}->[2] ) {
                        $coerce->{$attr} = $STRPTIME_TOKEN->{$token}->[2];
                    }
                    else {
                        delete $coerce->{$attr};
                    }
                }
            }

            $match_id++;
        }
    }

    undef $coerce if $coerce && !keys $coerce->%*;

    $res = [ qr/$re/smo, $map, $coerce ];

    $cache->{$pattern} = $res if $use_cache;

    return $res;
}

sub strptime_match_pattern ( $self, $str, $pattern ) {
    if ( my @match = fc($str) =~ $pattern->[0] ) {
        my $args->@{ keys $pattern->[1]->%* } = @match[ values $pattern->[1]->%* ];

        if ( $pattern->[2] ) {
            for my $attr ( keys $pattern->[2]->%* ) {
                my $coerce = $pattern->[2]->{$attr};

                if ( ref $coerce eq 'HASH' ) {
                    $args->{$attr} = $coerce->{ $args->{$attr} };
                }
                else {
                    \$_ = \$args->{$attr};

                    $coerce->&*;
                }
            }
        }

        return P->date->new( $args->%* );
    }
    else {
        die q[Strftime pattern does not match];
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 358, 373, 416, 427,  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |      | 430, 444             |                                                                                                                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 362, 363             | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 373                  | BuiltinFunctions::ProhibitReverseSortBlock - Forbid $b before $a in sort blocks                                |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Date::Strptime

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
