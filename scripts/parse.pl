#!/usr/bin/perl -w

#**
# @file parse.pl
# @brief Scan all specified Commotion git repositories and generate updated
# PO files for upload to the Transifex translation service.
#
# @author Andrew Reynolds, andrew@opentechinstitute.org
#
# @internal
# Created November 10, 2013
# Company The Open Technology Institute
# Copyright Copyright (c) 2013, Andrew Reynolds
#
# This file is part of Commotion, Copyright (c) 2014, Andrew Reynolds
#
# Commotion is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# Commotion is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Commotion. If not, see <http://www.gnu.org/licenses/>.
#
# =====================================================================================
#*

use strict;
use File::Path qw(make_path remove_tree);
use Git::Repository;
use File::Copy;
use File::Next;
use Text::Balanced qw(extract_bracketed extract_delimited extract_tagged);
use DateTime;

#**
# @var verbosity Print debug messages
# @param 0|1 0 == off, 1 == on
#*
my $verbosity = 1;
my @todo = ("\n\nTo Do:");
push(@todo, "Fix use vs. require");

## TODO: for next major revision:
## Look for ways to minimize string overlap
## http://www.perlmonks.org/?node_id=816086
push(@todo, "minimize duplicate strings in po files - http://www.perlmonks.org/?node_id=816086");

#**
# @var repos Repos to be scanned for translatable strings
# @param name Repo common name. Used as primary key.
# @param source Named k:v pair specifying location of remote git repo. Value of name parameter.
# @param branch Named k:v pair listing appropriate repo branch as defined in commotion-feed. Value of name parameter.
#*
my %repos = (
	'luci-commotion-apps' => {
		'source' => 'https://github.com/opentechinstitute/luci-commotion-apps.git',
		'branch' => 'master',
	},
	
	'luci-theme-commotion' => {
		'source' => 'https://github.com/opentechinstitute/luci-theme-commotion.git',
		'branch' => 'master',
	},
	'luci-commotion' => {
		'source' => 'https://github.com/opentechinstitute/luci-commotion.git',
		'branch' => 'master',
	},
	'commotion-dashboard-helper' => {
		'source' => 'https://github.com/opentechinstitute/commotion-dashboard-helper.git',
		'branch' => 'master',
	}, 
	'commotiond commotion-service-manager' => {
		'source' => 'https://github.com/opentechinstitute/commotion-service-manager.git',
		'branch' => 'master',
	},
	'commotion-router' => {
		'source' => 'https://github.com/opentechinstitute/commotion-router.git',
		'branch' => 'master',
	},
	'commotion-feed' => {
		'source' => 'https://github.com/opentechinstitute/commotion-feed.git',
		'branch' => 'master',
	}, 
	'commotion-lua-helpers' => {
		'source' => 'https://github.com/opentechinstitute/commotion-lua-helpers.git',
		'branch' => 'master',
	},
	'serval-dna' => {
		'source' => 'https://github.com/opentechinstitute/commotion-dashboard-helper.git',
		'branch' => 'commotion-wireless',
	},
	'luci-commotion-splash' => {
		'source' => 'https://github.com/opentechinstitute/luci-commotion-splash.git',
		'branch' => 'master',
	},
	'commotion-debug-helper' => {
		'source' => 'https://github.com/opentechinstitute/commotion-debug-helper.git',
		'branch' => 'master',
	},
	'luci-i18n-commotion' => {
		'source' => 'https://github.com/opentechinstitute/luci-i18n-commotion.git',
		'branch' => 'master',
	}, 
	'olsrd' => {
		'source' => 'https://github.com/opentechinstitute/olsrd.git',
		'branch' => 'master',
	},
);

#**
# @section Directories 
# @brief Define internal directory structure, including translation source and working area.
# Include trailing slashes!
#*
my $working_dir = 'working/';
my $working_source_dir = $working_dir . 'source/';
my $working_translations_dir = $working_dir . 'translations/';
my $stable_translations_dir = $working_source_dir . 'luci-i18n-commotion/translations/';

#**
# @brief Prepare working directories
#*
if (not -e $working_dir) {
	print("Creating working directories\n");
	make_path($working_dir, $working_source_dir, $working_translations_dir, {verbose=>1})
		|| die "ERROR: Couldn't create " . $working_dir . "\n";	
}

#**
# @brief Iterate over commotion-router packages defined in %repos.
# If working copy does not exist, clone it and check out proper branch.
# If working copy does exist, check out proper branch and pull updates.
#*
foreach my $repo (keys %repos) {
	if (not -e $working_source_dir . $repo) {
		print("Cloning " . $repo . " into " . $working_source_dir ."\n");
		Git::Repository->run( clone => $repos{$repo}{'source'} => $working_source_dir . $repo)
			|| warn "Couldn't clone " . $repos{$repo}{'source'} . "\n";
		my $r = Git::Repository->new( work_tree => $working_source_dir . $repo);
		print("\tChecking out $repos{$repo}{'branch'} branch\n");
		$r->command(checkout => $repos{$repo}{'branch'}) || die "Couldn't check out proper branch\n";
	} else {
		print("Updating " . $repo . "\n");
		my $r = Git::Repository->new( work_tree => $working_source_dir . $repo);
		$r->command(checkout => $repos{$repo}{'branch'}) || die "Couldn't check out proper branch\n";
		$r->command(pull => 'origin', $repos{$repo}{'branch'}, { quiet => 1 }) || warn "Couldn't pull remotes\n";
	}
}


#**
# @section Locate Translation Files
# @brief Find current set of translation files (.po) and copy to working area
#* 
push(@todo, "add transifex github integration");

opendir(DIR, $stable_translations_dir) or warn "Couldn't open stable po dir: $!";
my @po_files = glob "$stable_translations_dir*.po"; 
closedir(DIR);

for (0..$#po_files){
	$po_files[$_] =~ s/^$stable_translations_dir//;
}

#**
# Copy stable PO file to working area.
#*
if (@po_files) {
	foreach (@po_files) {
		if ($verbosity == 1) { print("Copying $_ to $working_translations_dir\n"); }
		copy($stable_translations_dir . $_, $working_translations_dir . $_) || die "Couldn't copy PO file $_: $!\n";
	}
} else {
	warn "Couldn't find any stable PO files!\n";
}

#**
# @section String extraction
# @brief Traverse git repos, searching files of specified type for translatable strings
# and separating strings from their tags.
#*


#**
# @brief File Scan Options
# @param descend_filter define directories to be searched or ignored
# @param file_filter define filetypes to be searched or ignored
#*
my $descend_filter = sub { $_ ne '.git' };
my $file_filter = sub { $_ =~ '.htm' or $_ =~ '.lua' };
my @working_source_files;
my $scan = File::Next::files( {
	descend_filter => $descend_filter,
	file_filter => $file_filter,
	error_handler => sub { my $msg = shift; warn($msg) },
	},
	$working_source_dir);
while (defined(my $file = $scan->())) {
	push(@working_source_files, $file);
}

#**
# Separate text strings from translation tags
# @brief string parsing functions from luci.subsignal.org (copyright 2013 by jow)
# @see http://luci.subsignal.org/trac/browser/luci/trunk/build/i18n-scan.pl
# @see Extract_Translations()
# @see Extract_Luci_Translations()
#*

#**
# @var stringtable contains filename and all translatable strings from that file
#*
my %stringtable;
foreach my $file (@working_source_files) {
	chomp $file;
	if ($verbosity == 1) { print "Populating string table from $file\n"; }
	# read file into $raw
	if( open S, "< $file" ) {
		local $/ = undef;
		my $raw = <S>;
		close S;

		my @res = Extract_Translations($raw);
		if (@res) {
			push(@{ $stringtable{$file} }, @res);
		}
		my @code = Extract_Luci_Translations($raw);
		if (@code) {
			push(@{ $stringtable{$file} }, @code);
		}
	}
}

#**
# @section Create new PO files
# @brief Using list of new strings, check for existing translations and generate new PO files.
# @see Fetch_Translations()
# @see _Generate_PO_Body()
# @see _Generate_PO_Header()
# @see Write_PO_File()
#*
foreach my $po_file (@po_files) { 
	if ($verbosity == 1) { print "Salvaging translations from $po_file\n"; }
	my $translations = ();
	# English file can be overwritten each time

	# NOTE: we don't care about anything but msgid changes
	# and existence of previous translations

	# Generate id:str pairs for PO files
	# NOTE: translations is a hash ref
	unless ($po_file =~ m|-en.po$|) {
		$translations = Fetch_Translations($working_translations_dir . $po_file);
	}
	
	if ($verbosity == 1) { print "Generating file header for $po_file\n"; }
	my @po_header = _Generate_PO_Header($working_translations_dir . $po_file);
	
	if ($verbosity == 1) { print "Generating file body for $po_file\n"; }
	my @po_body = _Generate_PO_Body($working_translations_dir . $po_file, \%stringtable, $translations);
	
	# Write File
	print "Writing to $working_translations_dir$po_file\n";
	Write_PO_File($working_translations_dir . $po_file, \@po_header, \@po_body);
}

print "\n\n\nFile generation complete.\nNew PO files can be found in $working_translations_dir\n";

# Upload to Transifex/GitHub
# http://support.transifex.com/customer/portal/topics/440186-api/articles

# print to do list
if ($verbosity == 1) { foreach (@todo) { print "$_\n"; } }

exit 0;

#**
# @function Extract_Translations
# @brief Use translation tags to find translatable text
# @param text Raw text from repo files
# @retval res Unique translatable strings without translation tags
#*
sub Extract_Translations {
	my $text = pop(@_);
	my @res = ();
	my $res = "";
	my $sub = "";
	# search $text for translate flags
	while( $text =~ s/ ^ .*? (?:translate|translatef|i18n|_) [\n\s]* \( /(/sgx ) {
		# separate usable $code from $text. $code and $text reverse of expected
		( my $code, $text ) = extract_bracketed($text, q{('")});
		# strip newlines and extra whitespace out of $code
		$code =~ s/\\\n/ /g;
		$code =~ s/^\([\n\s]*//;
		$code =~ s/[\n\s]*\)$//;



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
		if ($res) {
			push(@res, $res);
		}
		# add $res to %stringtable
	}
	@res = uniq(@res);
	return(@res);
}

#**
# @function Extract_Translations
# @brief Use translation tags to find translatable text. Similar to Extract_Translations
# @param text Raw text from repo files
# @retval res Unique translatable strings without translation tags
#*
sub Extract_Luci_Translations {
	my $text = pop(@_);
	my @code;
	while( $text =~ s/ ^ .*? <% -? [:_] /<%/sgx ) {
		( my $code, $text ) = extract_tagged($text, '<%', '%>');

		if( defined $code ) {
			$code = dec_tpl_str(substr $code, 2, length($code) - 4);
		}
		push(@code, $code);
	}
	@code = uniq(@code);
	return(@code);
}

#**
# @function dec_lua_str
# @param s Translatable string
# @brief Strip translation tags
# @see Extract_Translations
#*
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

#**
# @function dec_tpl_str
# @param s Translatable string
# @brief Strip translation tags
# @see Extract_Luci_Translations
#*
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

#**
# @function Fetch_Translations
# @brief Saves existing translations to pre-populate new PO files and minimize retranslation effort
# @param working_po_file An existing PO file containing previous translations
# @retval translations Uses string:translation as key:value to be checked against new strings
#*
sub Fetch_Translations {
	my $working_po_file = pop(@_);
	if ($verbosity == 1) { print "Getting translations for $working_po_file\n"; }
	my %translations;
	open(WPO, "< $working_po_file") || die "Couldn't open translation file: $!\n";
	my @wpo = <WPO>;
	close(WPO);
	for (my $i = 0; $i < $#wpo; $i++) {
		local $/ = "";
		chomp($wpo[$i]);
		if ($wpo[$i] =~ m|^msgid|) {
			my $mid = $wpo[$i];
			unless ($wpo[$i+1] =~ m|^msgstr|) {
				$mid = $mid . $wpo[$i+1];
			} else {
				my $mstr = $wpo[$i+1];
				# quote removal might be better with extract
				$mid =~ s|^msgid "?||;
				$mid =~ s|"?$||;
				$mstr =~ s|^msgstr "?||;
				$mstr =~ s|"?$||;
				chomp($mstr);
				$translations{$mid} = $mstr;
			}
		}
		
	}
	return \%translations;
}

#**
# @function _Generate_PO_Header
# @brief Generates the standard PO file header used by Transifex.
# @param working_po_file Language-specific PO file
# @retval po_header Array containing header lines
#*
sub _Generate_PO_Header {
	my $working_po_file = pop;	
	my @po_header;
	# DateTime is probably overkill
	my $dt = DateTime->now();
	$dt = $dt.'\n"';
	#my $date = strftime "%Y-%m-%d %R\n";
	#"PO-Revision-Date: 2013-08-16 20:50+0000\n"
	open(WPF, "< $working_po_file");
	while(<WPF>) {
		chomp;
		if ($_ =~ m|^\"PO-Revision-Date\:\ |) {
			$_ = $& . $dt;
		}
		push(@po_header, $_);
		last if ($_ =~ m|^"Plural|);
	}
	close(WPF);
	return(@po_header);
}

#**
# @function _Generate_PO_Body
# @brief Generates new string:translation pairs in the Transifex format.
# @param working_po_file Language-specific PO file
# @param stringtable Translatable strings used in the most recent version of Commotion
# @param translations Previously translated strings
# @retval wps Array containing header lines
#*
sub _Generate_PO_Body {
	my ($working_po_file, $stringtable, $translations) = @_;
	my @wps = ();

	# Get k:v else write k:msgstr
	foreach my $f (keys %{$stringtable}) {
		chomp($f);
		push(@wps, "#: $f");
		foreach my $id ( @{$stringtable->{$f}} ) {
			my $str;
			if ($working_po_file =~ m|-en.po$|) {
				$str = 'msgstr "' . $id . '"';
			} else {
				# need to do better string extraction
				if ( exists $translations->{$id} ) {
					$str = 'msgstr "' . $translations->{$id} . '"';
				} else {
					$str = 'msgstr ""';
				}
			}
			my $mid = 'msgid "' . $id . '"';
			push(@wps, $mid);
			push(@wps, $str);
		}
		push(@wps, "\n");
	}
	@wps = uniq(@wps);
	return(@wps);
}

#**
# @function Write_PO_File
# @brief Write a correctly structured PO file containing only current strings
# @param working_po_file PO file to be written
# @param po_header Array containing standard PO file header
# @param po_body Array containing all new translatable strings and any relevant translations
#*
sub Write_PO_File {
	# NOTE: po_header and po_body are array references
	my ($working_po_file, $po_header, $po_body) = @_;

	open(WPO, "> $working_po_file") || die "Couldn't open $working_po_file: $!\n";
	foreach (@{$po_header}) {
		print WPO $_,"\n";
	}
	foreach (@{$po_body}) {
		print WPO $_,"\n";
	}
	close(WPO);
	return;
}

#**
# @function uniq
# @brief Return only unique elements from a list. Case sensitive. Not the List::MoreUtils function by same name.
# @param a List of elements to be checked
# @retval r List of unique elements
#*
sub uniq {
	my %seen = ();
	my @r = ();
	#**
	# Does not handle multidimensional arrays well
	#*
	foreach my $item (@_) {
		if ($item eq 'msgstr ""' || $item eq '\n') {
			push(@r, $item);
			next;
		}
		unless ($seen{$item}) {
			push @r, $item;
			$seen{$item} = 1;
		}
	}
	return @r;
}
