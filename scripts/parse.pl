#!/usr/bin/perl -w
use strict;

use Data::Dumper;
use App::Ack;
use Git::Repository; 
use File::Find::Rule;

my $source_root = '/home/areynold/Documents/Scripts/OTI/source/';
my $po_dir;

my %translate_flags = (
	'translate(' => ')',
	'<%:' => '%>'
);

# Update code repos
my @source_dirs = File::Find::Rule->maxdepth(1)->directory->in($source_root);
foreach my $d (@source_dirs) {
	my $dir = &Fetch($d);
	print("$dir\n");
}
# Fetch most recent PO files

# Traverse source directories, identifying translatable text

# Separate text strings from translation tags

# Compare strings to current PO file
## Discard matching strings
## Add new/modified strings to working PO file

# Commit working PO file

# Upload to Transifex/GitHub

sub Fetch {
	my $dir = pop(@_);
	# start from an existing working copy
	#$r = Git::Repository->new( work_tree => $dir );
	return($dir);
}
