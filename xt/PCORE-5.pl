#!/usr/bin/env perl

package main v0.1.0;

use Pcore;

my $temp_dir = $PROC->{TEMP_DIR} . 'PCORE-5';
P->file->mkpath($temp_dir);
my $cwd = P->file->cwd;
P->file->chdir($temp_dir);

{
    my $chdir_guard = P->file->chdir($cwd);
    P->file->rmtree($temp_dir);

    print 'Press ENTER to continue...';
    <STDIN>;
}

say 'DONE';

1;
__END__
=pod

=encoding utf8

=head1 REQUIRED ARGUMENTS

=over

=back

=head1 OPTIONS

=over

=back

=cut
