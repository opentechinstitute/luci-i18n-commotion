#!/usr/bin/perl -w
use strict;

use Data::Dumper;
use App::Ack;
use Git::Repository; 
use File::Path qw(make_path remove_tree);
#use Text::Balanced
#use File::Find::Rule;

##
## Git Info
##
my $git_account = 'https://github.com/opentechinstitute/';
my @repos = qw(commotion-openwrt commotion-feed avahi-client avahi-client 
	luci-commotion-apps commotion-dashboard-helper commotion-debug-helper 
	commotiond luci-commotion-apps luci-commotion-quickstart 
	luci-commotion-splash luci-commotion luci-theme-commotion
);
my $git_working_dir = 'git_working_dir/';


##
## Translation files
## 
my $po_dir; # Location of translation files
my %translate_flags = (
	'translate(' => ')',
	'<%:' => '%>'
);


# Prepare working directory
if (not -e $git_working_dir) {
	print("Creating working directory " . $git_working_dir . "\n");
	make_path($git_working_dir)
		|| die "ERROR: Couldn't create " . $git_working_dir . "\n";	
}

# Update code repos
foreach my $repo (@repos) {
	if (not -e $git_working_dir . $repo) {
		my $origin = $git_account . $repo;
		print("Cloning " . $origin . " into " . $git_working_dir ."\n");
		Git::Repository->run( clone => $origin => $git_working_dir . $repo)
			|| warn "Couldn't clone " . $origin . "\n";
	} else {
		print("Updating " . $repo . "\n");
		my $r = Git::Repository->new( work_tree => $git_working_dir . $repo );
		$r->run(pull => 'origin', 'master') || die "Couldn't pull remotes\n";
	}
}

# Fetch most recent PO files

# Traverse source directories, identifying translatable text

# Separate text strings from translation tags

# Compare strings to current PO file
## Discard matching strings
## Add new/modified strings to working PO file

# Commit working PO file

# Upload to Transifex/GitHub
