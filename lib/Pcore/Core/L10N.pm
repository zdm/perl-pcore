package Pcore::Core::L10N;

use Pcore -export;
use Pcore::Util::Scalar qw[is_plain_hashref];

our $EXPORT = {    #
    DEFAULT => [qw[l10n $l10n]],
};

our $PACKAGE_DOMAIN     = {};
our $LOCALE             = undef;
our $MESSAGES           = {};
our $LOCALE_PLURAL_FORM = {};

tie our $l10n->%*, 'Pcore::Core::L10N::_l10n';

sub set_locale ($locale = undef) {
    $LOCALE = $locale if @_;

    return $LOCALE;
}

sub register_package_domain ( $package, $domain ) {
    $PACKAGE_DOMAIN->{$package} = $domain;

    return;
}

sub load_domain_locale ( $domain, $locale ) : prototype($$) {
    my $dist = $ENV->{_dist_idx}->{$domain};

    die qq[l10n domain "$domain" is not registered] if !$domain;

    my $po_path = "$dist->{share_dir}l10n/$locale.po";

    if ( !-f $po_path ) {
        $MESSAGES->{$domain}->{$locale} = {};

        return;
    }

    my ( $messages, $plural_form, $msgid );

    for my $line ( P->file->read_lines($po_path)->@* ) {

        # skip comments
        next if substr( $line, 0, 1 ) eq '#';

        if ( $line =~ /\Amsgid\s"(.+?)"/sm ) {
            $msgid = $1;

            $messages->{$msgid} = [];
        }
        elsif ( $line =~ /\Amsgid_plural\s/sm ) {
            next;
        }
        elsif ( $line =~ /\Amsgstr\s"(.+?)"/sm ) {
            $messages->{$msgid}->[0] = $1;
        }
        elsif ( $line =~ /\Amsgstr\[(\d+)\]\s"(.+?)"/sm ) {
            $messages->{$msgid}->[$1] = $2;
        }
        elsif ( $line =~ /"(.+?):\s(.+?)\\n"/sm ) {
            $plural_form = $2 if $1 eq 'Plural-Forms';
        }
    }

    if ($plural_form) {
        if ( $plural_form =~ /.+?;\s+plural=[(](.+?)[)];/sm ) {
            my $exp = $1;

            if ( exists $LOCALE_PLURAL_FORM->{$locale}->{exp} ) {
                die qq[Plural form expression for locale "$locale" redefined] if $LOCALE_PLURAL_FORM->{$locale}->{exp} ne $exp;
            }
            else {
                $LOCALE_PLURAL_FORM->{$locale}->{exp} = $exp;
            }

            $exp =~ s/n/\$_[0]/smg;

            $LOCALE_PLURAL_FORM->{$locale}->{code} = eval "sub { return $exp }";    ## no critic qw[BuiltinFunctions::ProhibitStringyEval]
        }
    }

    $MESSAGES->{$domain}->{$locale} = $messages;

    return;
}

# TODO get domain from caller
sub l10n ( $msgid, $msgid_plural = undef, $num = undef ) : prototype($;$$) {
    return bless {
        domain       => $PACKAGE_DOMAIN->{ caller() },
        msgid        => $msgid,
        msgid_plural => $msgid_plural,
        num          => $num // 1,
      },
      'Pcore::Core::L10N::_deferred';
}

package Pcore::Core::L10N::_deferred;

use Pcore -class;

use overload    #
  q[""] => sub {
    return $_[0]->to_string;
  },
  q[&{}] => sub {
    my $self = $_[0];

    return sub { $self->to_string(@_) };
  },
  bool => sub {
    return 1;
  },
  fallback => undef;

has domain       => ();
has msgid        => ();
has msgid_plural => ();
has num          => ();

sub to_string ( $self, $num = undef ) {
    if ( !$self->{msgid_plural} ) {
        return $self->{msgid} if !defined $LOCALE;

        Pcore::Core::L10N::load_domain_locale( $self->{domain}, $LOCALE ) if !exists $Pcore::Core::L10N::MESSAGES->{ $self->{domain} }->{$LOCALE};

        return $Pcore::Core::L10N::MESSAGES->{ $self->{domain} }->{$LOCALE}->{ $self->{msgid} }->[0] // $self->{msgid};
    }
    else {
        $num //= $self->{num};

        goto ENGLISH if !defined $LOCALE;

        Pcore::Core::L10N::load_domain_locale( $self->{domain}, $LOCALE ) if !exists $Pcore::Core::L10N::MESSAGES->{ $self->{domain} }->{$LOCALE};

        goto ENGLISH if !defined $LOCALE_PLURAL_FORM->{$LOCALE}->{code};

        my $idx = $LOCALE_PLURAL_FORM->{$LOCALE}->{code}->($num);

        return $Pcore::Core::L10N::MESSAGES->{ $self->{domain} }->{$LOCALE}->{ $self->{msgid} }->[$idx] if defined $Pcore::Core::L10N::MESSAGES->{ $self->{domain} }->{$LOCALE}->{ $self->{msgid} }->[$idx];

      ENGLISH:
        if ( $num == 1 ) {
            return $self->{msgid};
        }
        else {
            return $self->{msgid_plural} // $self->{msgid};
        }
    }
}

package Pcore::Core::L10N::_l10n;

sub TIEHASH ( $self, @args ) {
    return bless {}, $self;
}

# TODO domain
sub FETCH {
    return bless {
        domain => $PACKAGE_DOMAIN->{ caller() },
        msgid  => $_[1],
      },
      'Pcore::Core::L10N::_deferred';
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 15                   | Miscellanea::ProhibitTies - Tied variable used                                                                 |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 93, 164              | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::L10N - localization subsystem.

=head1 SYNOPSIS

    use Pcore -l10n;

    P->set_locale('ru');

    say l10n('single');
    say l10n( 'single', 'plural', 1 );
    say l10n( 'single', 'plural' )->(5);
    say $l10n->{'single'};

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=head1 AUTHOR

zdm <zdm@softvisio.net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2016 by zdm.

=cut
