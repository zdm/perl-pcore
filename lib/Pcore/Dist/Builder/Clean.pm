package Pcore::Dist::Builder::Clean;

use Pcore qw[-class];

with qw[Pcore::Dist::Builder];

no Pcore;

our $DIRS = [

    # general build
    'blib',

    # Module::Build
    '_build',
];

my $FILES = [

    # general build
    qw[META.yml MYMETA.json MYMETA.yml],

    # Module::Build
    qw[_build_params Build Build.bat],

    # MakeMaker
    qw[Makefile pm_to_blib],
];

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run;

    return;
}

sub run ($self) {
    for my $dir ( $DIRS->@* ) {
        P->file->rmtree($dir);
    }

    for my $file ( $FILES->@* ) {
        unlink $file or die qq[Can't unlink "$file"] if -f $file;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder::Clean - clean dist directory from known build garbage

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
