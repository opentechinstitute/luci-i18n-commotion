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
foreach my $r (@repos) {
	if (not -e $git_working_dir . $r) {
		print($git_working_dir . $r . " Does not exist\n");
		my $origin = $git_account . $r;
		print("Cloning " . $origin . " into " . $git_working_dir ."\n");
		Git::Repository->run( clone => $origin => $git_working_dir . $r)
			|| warn "Couldn't clone " . $origin . "\n";
	} else {
		# pull origin master
		#	my $dir = &Fetch($d);
		#	print("$dir\n");
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

sub Fetch {
	my $dir = pop(@_);
	
	# https://github.com/opentechinstitute/olsrd.git
	my $git_account = 'https://github.com/opentechinstitute/';
	my @repos = qw(commotion-openwrt commotion-feed avahi-client avahi-client 
		luci-commotion-apps commotion-dashboard-helper commotion-debug-helper 
		commotion commotiond ldns lua-uri luci-commotion-apps luci-commotion-quickstart 
		luci-commotion-splash luci-commotion luci-i18n-commotion luci-theme-commotion
		olsrd serval-crypto serval-dna xssfilter
	);
	foreach my $r (@repos) {
		my $clone_url = $git_account . $r . '.git'
	}
	# start from an existing working copy
	#$r = Git::Repository->new( work_tree => $dir );
	return($dir);
}
