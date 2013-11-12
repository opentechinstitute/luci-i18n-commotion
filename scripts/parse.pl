#!/usr/bin/perl -w
use strict;
my @todo = ("\n\nTo Do:");

push(@todo, "Fix use vs. require");
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use Git::Repository;
use File::Copy;
use File::Next;
use Text::Balanced qw(extract_bracketed extract_delimited extract_tagged);
use List::MoreUtils qw(uniq);
use Text::Diff;

##
## Git Info
##
my $git_account = 'https://github.com/opentechinstitute/';
my @repos = qw(commotion-openwrt commotion-feed avahi-client luci-commotion-apps 
	commotion-dashboard-helper commotion-debug-helper commotiond 
	luci-commotion-quickstart luci-commotion-splash luci-commotion luci-theme-commotion
);
my $working_dir = 'working/';
my $working_source_dir = $working_dir . 'source/';
my $working_translations_dir = $working_dir . 'translations/';

my $stable_dir = '../';
my $stable_translations_dir = $stable_dir . 'translations/';


##
## Translation files
## 
my $po_dir = '../'; # Location of translation files

# Prepare working directory
if (not -e $working_dir) {
	print("Creating working directories\n");
	make_path($working_dir, $working_source_dir, $working_translations_dir, {verbose=>1})
		|| die "ERROR: Couldn't create " . $working_dir . "\n";	
}

# Update code repos
foreach my $repo (@repos) {
	if (not -e $working_source_dir . $repo) {
		my $origin = $git_account . $repo;
		print("Cloning " . $origin . " into " . $working_source_dir ."\n");
		Git::Repository->run( clone => $origin => $working_source_dir . $repo)
			|| warn "Couldn't clone " . $origin . "\n";
	} else {
		print("Updating " . $repo . "\n");
		my $r = Git::Repository->new( work_tree => $working_source_dir . $repo, { quiet => 1 });
		$r->command(pull => 'origin', 'master') || warn "Couldn't pull remotes\n";
	}
}

# Fetch most recent PO files
push(@todo, "add transifex github integration");
print("Updating translation files\n");
my $r = Git::Repository->new ( work_tree => $po_dir, { quiet => 1 });
$r->command(pull =>'--rebase', 'origin', 'master') || warn "Couldn't pull stable branch\n";

# Create working PO file from stable PO file
push(@todo, "Create .po headers");
my $working_translations_file = $working_translations_dir . 'working.commotion-luci-en.po';

if (-e '../translations/commotion-luci-en.po') {
	copy('../translations/commotion-luci-en.po', $working_translations_file) || die "Couldn't copy English PO file: $!\n";
} else {
	warn "Couldn't find stable English PO file\n";
}

# Traverse source directories, identifying translatable text
my @working_files;
##
## File Scan Options
##
my $descend_filter = sub { $_ ne '.git' };
my $file_filter = sub { $_ =~ '.htm' or $_ =~ '.lua' };
my $scan = File::Next::files( {
	descend_filter => $descend_filter,
	file_filter => $file_filter,
	error_handler => sub { my $msg = shift; warn($msg) },
	},
	$working_source_dir);
while (defined(my $file = $scan->())) {
	push(@working_files, $file);
}

##
## Separate text strings from translation tags
##
## string parsing functions from luci.subsignal.org
## http://luci.subsignal.org/trac/browser/luci/trunk/build/i18n-scan.pl
## copyright 2013 by jow 

# looks like stringtable is a hash so it can handle multi-line strings
my %stringtable;
foreach my $file (@working_files) {
	chomp $file;
# read file into $raw
	if( open S, "< $file" ) {
		local $/ = undef;
		my $raw = <S>;
		close S;

# copy $raw to $text for manipulation
		my $text = $raw;

# search $text for translate flags
		while( $text =~ s/ ^ .*? (?:translate|translatef|i18n|_) [\n\s]* \( /(/sgx ) {
# separate usable $code from $text. $code and $text reverse of expected
			( my $code, $text ) = extract_bracketed($text, q{('")});
# strip newlines and extra whitespace out of $code
			$code =~ s/\\\n/ /g;
			$code =~ s/^\([\n\s]*//;
			$code =~ s/[\n\s]*\)$//;

			my $res = "";
			my $sub = "";

# Check code for quoted text. Store in $sub
			if( $code =~ /^['"]/ ) {
				while( defined $sub ) {
					( $sub, $code ) = extract_delimited($code, q{'"}, q{\s*(?:\.\.\s*)?});

					if( defined $sub && length($sub) > 2 ) {
# use sub to build $res
						$res .= substr $sub, 1, length($sub) - 2;
					} else {
						undef $sub;
					}
				}
# Check code for tagged text. store in $res
			} elsif( $code =~ /^(\[=*\[)/ ) {
				my $stag = quotemeta $1;
				my $etag = $stag;
				$etag =~ s/\[/]/g;

				( $res ) = extract_tagged($code, $stag, $etag);

				$res =~ s/^$stag//;
				$res =~ s/$etag$//;
			}

# Strip superfluous strings out of $res
			$res = dec_lua_str($res);
# add $res to %stringtable
			if ($res) {
				push(@{ $stringtable{$file} }, $res);
			}
		}

		$text = $raw;
# Same steps for lua code
		while( $text =~ s/ ^ .*? <% -? [:_] /<%/sgx ) {
			( my $code, $text ) = extract_tagged($text, '<%', '%>');

			if( defined $code ) {
				$code = dec_tpl_str(substr $code, 2, length($code) - 4);
				push(@{ $stringtable{$file} }, $code);
			}
		}
	}
}

# Create new PO file
# English PO file can be overwritten each time
my $new_strings_file = $working_translations_dir . 'new_strings.txt';
my $po_header = &Generate_PO_Header();

open (NS, "> $new_strings_file");
if ($po_header) {
	print NS $po_header;
}

foreach my $file (sort keys %stringtable) {
	(my $filename = $file) =~ s|$working_source_dir||;
	print NS "\n#: $filename\n";
	foreach my $string ( uniq @{ $stringtable{$file} } ) {	
		print NS "msgid \"$string\"\n";
		print NS "msgstr \"$string\"\n\n";
	}
} 
close(NS);

# Compare new strings to stable strings
open(STABLE, "< $working_translations_file");
#my @diff = split("\n", diff($working_translations_file, $new_strings_file));
my @diff = diff($working_translations_file, $new_strings_file);
close(STABLE);

foreach (@diff) {
	if ($_ =~ m|^[+-]msgid|) {
#		print "Change: $_\n";
	}
}
print Dumper(@diff);
# Commit working PO file

# Upload to Transifex/GitHub

push(@todo, "Move common functions to subroutines");
# print to do list
foreach (@todo) { print "$_\n"; }

##
## Translation tags
##
sub dec_lua_str
{
        my $s = shift;
        $s =~ s/[\s\n]+/ /g;
        $s =~ s/\\n/\n/g;
        $s =~ s/\\t/\t/g;
        $s =~ s/\\(.)/$1/g;
        $s =~ s/^ //;
        $s =~ s/ $//;
        return $s;
}

sub dec_tpl_str
{
        my $s = shift;
        $s =~ s/-$//;
        $s =~ s/[\s\n]+/ /g;
        $s =~ s/^ //;
        $s =~ s/ $//;
        $s =~ s/\\/\\\\/g;
        return $s;
}

sub Generate_PO_Header {
	my $po_header = "See existing PO files for header requirements\n\n";
	return($po_header);
}
