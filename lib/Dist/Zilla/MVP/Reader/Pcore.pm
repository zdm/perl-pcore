package Dist::Zilla::MVP::Reader::Pcore;

use Moose;
use strict;
use warnings;
use utf8;

extends qw[Config::MVP::Reader];

with qw[Config::MVP::Reader::Findable::ByExtension];

no Moose;

sub refined_location {

    # Pcore is required
    return if !$INC{'Pcore.pm'};

    if ( $_[1] =~ /profile\z/sm ) {

        # return $_[1] . '.perl';
    }
    elsif ( $_[1] =~ /dist\z/sm ) {
        return './share/dist.perl' if -f './share/dist.perl';
    }

    return;
}

sub default_extension {
    return 'perl';
}

sub read_into_assembler {
    my ( $self, $location, $asm ) = @_;

    my $cfg = Pcore->cfg->load($location);

    $cfg = $cfg->{dist} if exists $cfg->{dist};

    for my $key ( grep { !ref $cfg->{$_} } keys %{$cfg} ) {
        $asm->add_value( $key, $cfg->{$key} );
    }

    $asm->end_section if $asm->current_section;

    if ( $location =~ /dist.perl\z/sm ) {

        # add @Pcore section
        $asm->begin_section( '@Pcore', '@Pcore' );

        # remove undef plugins
        # 'Plugin[::Name]' => undef
        for my $plugin ( grep { m/[[:upper:]]/sm && !defined $cfg->{$_} } keys %{$cfg} ) {
            $asm->add_value( '-remove', $plugin );
        }

        # close @Pcore section
        $asm->end_section if $asm->current_section;
    }

    # add plugins sections
    for my $section ( grep { m/[[:upper:]]/sm && ref $cfg->{$_} } keys %{$cfg} ) {
        $asm->begin_section( $section, $section );

        for my $key ( keys %{ $cfg->{$section} } ) {
            my $values = ref $cfg->{$section}->{$key} eq 'ARRAY' ? $cfg->{$section}->{$key} : [ $cfg->{$section}->{$key} ];

            for ( @{$values} ) {
                $asm->add_value( $key, $_ );
            }
        }

        $asm->end_section if $asm->current_section;
    }

    return $asm->sequence;
}

__PACKAGE__->meta->make_immutable;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 50                   │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
