# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::VirtPackage class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2004 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::VirtPackage;

# Programmers' note: Please be *very* careful if you alter this file.
# It is used by dpkg via popen(), so (among other things) that means
# you must not print to STDOUT.

use Fink::Config qw($config $basepath);
use POSIX qw(uname);
use Fink::Status;

use constant {
	STATUS_PRESENT => "install ok installed",
	STATUS_ABSENT  => "purge ok not-installed",
};

use vars qw(
	%options
);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

my @xservers     = ('XDarwin', 'Xquartz', 'XDarwinQuartz');
my $the_instance = undef;

END { }				# module clean-up code here (global destructor)


### constructor

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	$self->initialize();

	$the_instance = $self;
	return $self;
}

### self-initialization

sub initialize {
	my $self    = shift;

	my ($hash);
	my ($dummy);
	my ($darwin_version, $cctools_version, $cctools_single_module);
	# determine the kernel version
	($dummy,$dummy,$darwin_version) = uname();

	# create dummy object for kernel version
	$hash = {};
	$hash->{package} = "darwin";
	$hash->{status} = STATUS_PRESENT;
	$hash->{version} = $darwin_version."-1";
	$hash->{description} = "[virtual package representing the kernel]";
	$hash->{descdetail} = <<END;
This package represents the XNU (Darwin) kernel, which is
a core part of the system for Mac OS X and all other Darwin
variants.
END
	$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$self->{$hash->{package}} = $hash;
	
	# create dummy object for system version, if this is OS X at all
	print STDERR "- checking OSX version... " if ($options{debug});

	$hash = {};
	$hash->{package} = "macosx";
	$hash->{description} = "[virtual package representing the system]";
	$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	if (Fink::Services::get_sw_vers() ne 0) {
		$hash->{status} = STATUS_PRESENT;
		$hash->{version} = Fink::Services::get_sw_vers()."-1";
		print STDERR $hash->{version}, "\n" if ($options{debug});
	} else {
		$hash->{status} = STATUS_ABSENT;
		$hash->{version} = '0-0';
		print STDERR "unknown\n" if ($options{debug});
	}
	$hash->{descdetail} = <<END;
This package represents the Mac OS X software release.
It will not show as installed on pure Darwin systems.
END
	$self->{$hash->{package}} = $hash;

	# create dummy object for system perl
	print STDERR "- checking system perl version... " if ($options{debug});

	$hash = {};
	$hash->{package} = "system-perl";
	$hash->{description} = "[virtual package representing perl]";
	$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the version of perl installed on the
system in /usr/bin/perl.
END

	if (defined Fink::Services::get_system_perl_version()) {
		$hash->{version} = Fink::Services::get_system_perl_version()."-1";
		$hash->{status} = STATUS_PRESENT;
		print STDERR Fink::Services::get_system_perl_version(), "\n" if ($options{debug});
		my $perlver = my $shortver = Fink::Services::get_system_perl_version();
		$shortver =~ s/\.//g;
		my $perlprovides = 'perl' . $shortver . '-core, system-perl' . $shortver;
		if ($perlver ge '5.8.0') {
			$perlprovides .= ', attribute-handlers-pm' . $shortver . ', cgi-pm' . $shortver . ', digest-md5-pm' . $shortver . ', file-spec-pm' . $shortver . ', file-temp-pm' . $shortver . ', filter-simple-pm' . $shortver . ', filter-util-pm' . $shortver . ', getopt-long-pm' . $shortver . ', i18n-langtags-pm' . $shortver . ', libnet-pm' . $shortver . ', locale-maketext-pm' . $shortver . ', memoize-pm' . $shortver . ', mime-base64-pm' . $shortver . ', scalar-list-utils-pm' . $shortver .', test-harness-pm' . $shortver . ', test-simple-pm' . $shortver . ', time-hires-pm' . $shortver;
		}
		$hash->{provides} = $perlprovides;

	} else {
		$hash->{version} = '0-0';
		$hash->{status} = STATUS_ABSENT;
		print STDERR "unknown\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

	# create dummy object for java
	print STDERR "- checking Java directories:\n" if ($options{debug});
	my $javadir = '/System/Library/Frameworks/JavaVM.framework/Versions';
	my $latest_java;
	if (opendir(DIR, $javadir)) {
		for my $dir ( sort readdir(DIR)) {
			chomp($dir);
			next if ($dir =~ /^\.\.?$/);
			print STDERR "  - $dir... " if ($options{debug});
			if ($dir =~ /^\d[\d\.]*$/ and -d $javadir . '/' . $dir . '/Commands') {
				print STDERR "$dir/Commands " if ($options{debug});
				# chop the version down to major/minor without dots
				my $ver = $dir;
				$ver =~ s/[^\d]+//g;
				$ver =~ s/^(..).*$/$1/;
				$hash = {};
				$hash->{package}     = "system-java${ver}";
				$hash->{status}      = STATUS_PRESENT;
				$hash->{version}     = $dir . "-1";
				$hash->{description} = "[virtual package representing Java $dir]";
				$hash->{homepage}    = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
				$hash->{provides}    = 'system-java';
				if ($ver >= 14) {
					$hash->{provides} .= ', jdbc, jdbc2, jdbc3, jdbc-optional';
				}
				$hash->{descdetail}  = <<END;
This package represents the currently installed version
of Java $dir.
END
				$self->{$hash->{package}} = $hash;
				$latest_java = $dir;

				$hash = {};
				$hash->{package}     = "system-java${ver}-dev";
				$hash->{status}      = STATUS_PRESENT;
				$hash->{version}     = $dir . "-1";
				$hash->{description} = "[virtual package representing Java $dir development headers]";
				$hash->{homepage}    = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
				$hash->{descdetail}  = <<END;
This package represents the development headers for
Java $dir.  If this package shows as not being installed,
you must download the Java SDK from Apple at:

  http://connect.apple.com/

(free registration required)
END

				if (-d $javadir . '/' . $dir . '/Headers') {
					print STDERR "$dir/Headers " if ($options{debug});
				} else {
					$hash->{status} = STATUS_ABSENT;
				}
				$self->{$hash->{package}} = $hash;
				print STDERR "\n" if ($options{debug});
			} else {
				print STDERR "nothing\n" if ($options{debug});
			}
		}
		closedir(DIR);
	}

	if (defined $latest_java) {
		$hash = {};
		$hash->{package}     = "system-java";
		$hash->{status}      = "install ok installed";
		$hash->{version}     = $latest_java . "-1";
		$hash->{description} = "[virtual package representing Java $latest_java]";
		$self->{$hash->{package}} = $hash;
	}

	# create dummy object for Java3D
	$hash = {};
	$hash->{package}     = "system-java3d";
	$hash->{status}      = STATUS_PRESENT;
	$hash->{version}     = "0-1";
	$hash->{description} = "[virtual package representing Java3D]";
	$hash->{homepage}    = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$hash->{descdetail}  = <<END;
This package represents the Java3D API.  If it does not show
as installed, you can download it from Apple at:

  http://connect.apple.com/

(free registration required)
END

	print STDERR "- searching for java3d... " if ($options{debug});
	if (-f '/System/Library/Java/Extensions/j3dcore.jar') {
		print STDERR "found /System/Library/Java/Extensions/j3dcore.jar\n" if ($options{debug});
		if (open(FILEIN, '/Library/Receipts/Java3D.pkg/Contents/Info.plist')) {
			local $/ = undef;
			if (<FILEIN> =~ /<key>CFBundleShortVersionString<\/key>[\r\n\s]*<string>([\d\.]+)<\/string>/) {
				$hash->{version} = $1 . '-1';
			}
			close(FILEIN);
		}
	} else {
		$hash->{status} = STATUS_ABSENT;
		$hash->{version} = '0-0';
		print STDERR "missing /System/Library/Java/Extensions/j3dcore.jar\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

	# create dummy object for JavaAdvancedImaging
	$hash = {};
	$hash->{package}     = "system-javaai";
	$hash->{status}      = STATUS_PRESENT;
	$hash->{version}     = "0-1";
	$hash->{description} = "[virtual package representing Java Advanced Imaging]";
	$hash->{homepage}    = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$hash->{descdetail}  = <<END;
This package represents the Java Advanced Imaging API.  If it
does not show as installed, you can download it from Apple at:

  http://connect.apple.com/

(free registration required)
END

	print STDERR "- searching for javaai... " if ($options{debug});
	if (-f '/System/Library/Java/Extensions/jai_core.jar') {
		print STDERR "found /System/Library/Java/Extensions/jai_core.jar\n" if ($options{debug});
		if (open(FILEIN, '/Library/Receipts/JavaAdvancedImaging.pkg/Contents/Info.plist')) {
			local $/ = undef;
			if (<FILEIN> =~ /<key>CFBundleShortVersionString<\/key>[\r\n\s]*<string>([\d\.]+)<\/string>/) {
				$hash->{version} = $1 . '-1';
			}
			close(FILEIN);
		}
	} else {
		$hash->{status} = STATUS_ABSENT;
		$hash->{version} = '0-0';
		print STDERR "missing /System/Library/Java/Extensions/jai_core.jar\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

	# create dummy object for cctools version, if version was found in Config.pm
	print STDERR "- checking for cctools version... " if ($options{debug});

	if (-x "/usr/bin/ld" and -x "/usr/bin/what") {
		foreach(`/usr/bin/what /usr/bin/ld`) {
			if (/cctools-(\d+)/) {
				$cctools_version = $1;
				last;
			}
		}
	} else {
		print STDERR "/usr/bin/ld or /usr/bin/what not executable... " if ($options{debug});
	}

	$hash = {};
	$hash->{package} = "cctools";
	$hash->{status} = STATUS_PRESENT;
	$hash->{description} = "[virtual package representing the developer tools]";
	$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$hash->{builddependsonly} = "true";
	$hash->{descdetail} = <<END;
This package represents the C/C++/ObjC developer tools
provided by Apple.  If it does not show as installed,
you can download it from Apple at:

  http://connect.apple.com/

(free registration required)
END

	if (defined ($cctools_version)) {
		$hash->{version} = $cctools_version."-1";
		print STDERR $hash->{version}, "\n" if ($options{debug});
	} else {
		print STDERR "unknown\n" if ($options{debug});
		$hash->{version} = '0-0';
		$hash->{status} = STATUS_ABSENT;
	}
	$self->{$hash->{package}} = $hash;

	# create dummy object for cctools-single-module, if supported
	print STDERR "- checking for cctools -single_module support:\n" if ($options{debug});

	if (-x "/usr/bin/cc" and my $cctestfile = POSIX::tmpnam() and -x "/usr/bin/touch") {
		system("/usr/bin/touch ${cctestfile}.c");
		my $command = "/usr/bin/cc -o ${cctestfile}.dylib ${cctestfile}.c -dynamiclib -single_module >/dev/null 2>\&1";
		print STDERR "- running $command... " if ($options{debug});
		if (system($command) == 0) {
			print STDERR "-single_module passed\n" if ($options{debug});
			$cctools_single_module = '1.0';
		} else {
			print STDERR "failed\n" if ($options{debug});
			$cctools_single_module = undef;
		}
		unlink($cctestfile);
		unlink("${cctestfile}.c");
		unlink("${cctestfile}.dylib");
	}

	$hash = {};
	$hash->{package} = "cctools-single-module";
	$hash->{status} = STATUS_PRESENT;
	$hash->{version} = $cctools_single_module."-1";
	$hash->{description} = "[virtual package, your dev tools support -single_module]";
	$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$hash->{builddependsonly} = "true";
	$hash->{descdetail} = <<END;
This package represents support for the -single_module
flag in the development tools provided by Apple.  If it
does not show as installed, you can download the latest
developer tools (called XCode for Mac OS X 10.3 and
above) from Apple at:

  http://connect.apple.com/

(free registration required)
END

	if (not $cctools_single_module) {
		$hash->{status} = STATUS_ABSENT;
		if ($cctools_version) {
			$hash->{version} = $cctools_version;
		} else {
			$hash->{version} = '0-0';
		}
	}
	$self->{$hash->{package}} = $hash;

	print STDERR "- checking for various GCC versions:" if ($options{debug});
	if (opendir(DIR, "/usr/bin")) {
		for my $gcc (grep(/^gcc/, readdir(DIR))) {
			if (open(GCC, $gcc . ' --version |')) {
				chomp(my $version = <GCC>);
				close(GCC);
				if ($version =~ /^([\d\.]+)$/ or $version =~ /^gcc.*? \(GCC\) ([\d\.]+) /) {
					$version = $1;
					if ($version eq "2.95.2") {
						$hash = {};
						$hash->{package} = "gcc2";
						$hash->{status} = STATUS_PRESENT;
						$hash->{version} = "$version-1";
						$hash->{description} = "[virtual package representing the gcc $version compiler]";
						$hash->{homepage} = "http://fink.sourceforge.net/faq/comp-general.php#gcc2";
						$hash->{builddependsonly} = "true";
						$hash->{descdetail} = <<END;
This package represents the gcc $version compiler, which
is part of the Apple developer tools (also known as XCode
on Mac OS X 10.3 and above).  The latest versions of the
Apple developer tools are always available from Apple at:

  http://connect.apple.com/

(free registration required)
END

						$self->{$hash->{package}} = $hash;
					}
					my ($shortversion) = $version =~ /^(\d+\.\d+)/;
					$hash = {};
					$hash->{package} = "gcc$shortversion";
					$hash->{status} = STATUS_PRESENT;
					$hash->{version} = "$version-1";
					$hash->{description} = "[virtual package representing the gcc $version compiler]";
					$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
					$hash->{builddependsonly} = "true";
					$hash->{descdetail} = <<END;
This package represents the gcc $version compiler, which
is part of the Apple developer tools (also known as XCode
on Mac OS X 10.3 and above).  The latest versions of the
Apple developer tools are always available from Apple at:

  http://connect.apple.com/

(free registration required)
END
					$self->{$hash->{package}} = $hash;
					print STDERR "  - found $version\n" if ($options{debug});
				} else {
					print STDERR "  - warning, couldn't match '$version'\n" if ($options{debug});
				}
			}
		}
		closedir(DIR);
	} else {
		print STDERR "  - couldn't get the contents of /usr/bin: $!\n" if ($options{debug});
	}

	print STDERR "- checking for gimp-print... " if ($options{debug});
	$hash = {};
	$hash->{package} = "gimp-print-shlibs";
	$hash->{version} = "4.2.5-1";
	$hash->{description} = "[virtual package representing Apple's install of Gimp Print]";
	$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the version of Gimp-Print that
comes with Mac OS X 10.3 and above.  If it shows as not
installed, you must install the GimpPrintPrinterDrivers
package that came with your Mac OS X CDs.
END

	if ( has_lib('libgimpprint.1.1.0.dylib') ) {
		print STDERR "4.2.5-1\n" if ($options{debug});
		$hash->{status} = STATUS_PRESENT;
	} else {
		$hash->{status} = STATUS_ABSENT;
	}
	$self->{$hash->{package}} = $hash;
	
	if ( has_lib('libX11.6.dylib') )
	{
		# check the status of xfree86 packages
		my $packagecount = 0;
		for my $packagename ('system-xfree86', 'xfree86-base', 'xfree86-rootless',
			'xfree86-base-threaded', 'system-xfree86-43', 'system-xfree86-42',
			'xfree86-base-shlibs', 'xfree86', 'system-xtools',
			'xfree86-base-threaded-shlibs', 'xfree86-rootless-shlibs',
			'xfree86-rootless-threaded-shlibs')
		{
			
			if (Fink::Status->query_package($packagename)) {
				print STDERR "- $packagename is installed\n" if ($options{debug});
				$packagecount++;
			}
		}

		# if no xfree86 packages are installed, put in our own placeholder
		if ($packagecount == 0) {

			my $descdetail = <<END;
This package represents a pre-existing installation
of X11 on your system that is not installed through
Fink.

If it shows as not installed, you likely need to
install the X11User and/or X11SDK packages from
Apple, or a similarly-compatible version.  For more
information, please see the FAQ entry on X11
installation at:

  http://fink.sourceforge.net/faq/usage-packages.php#apple-x11-wants-xfree86

END

			$hash = {};
			$hash->{package} = "system-xfree86-shlibs";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing Apple's install of X11]";
			$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = $descdetail;
			$hash->{provides} = 'x11-shlibs, libgl-shlibs, xft1-shlibs, xft2-shlibs, fontconfig1-shlibs, xfree86-base-threaded-shlibs';
			$self->{$hash->{package}} = $hash;

			$hash = {};
			$hash->{package} = "system-xfree86";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing Apple's install of X11]";
			$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = $descdetail;
			$hash->{provides} = 'x11, xserver, libgl, xft1, xft2, fontconfig1, xfree86-base-threaded';
			$self->{$hash->{package}} = $hash;

			$hash = {};
			$hash->{package} = "system-xfree86-dev";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing Apple's install of X11]";
			$hash->{homepage} = "http://fink.sourceforge.net/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = $descdetail;
			$hash->{provides} = 'x11-dev, libgl-dev, xft1-dev, xft2-dev, fontconfig1-dev, xfree86-base-threaded-dev';
			$self->{$hash->{package}} = $hash;

			my ($xver) = check_x11_version();
			if (defined $xver) {
				$hash = {};
				my $provides;

				my $found_xserver = 0;
				print STDERR "- checking for X servers... " if ($options{debug});
				for my $xserver (@xservers) {
					if (-x '/usr/X11R6/bin/' . $xserver) {
						print STDERR "$xserver\n" if ($options{debug});
						$found_xserver++;
						last;
					}
				}
				print STDERR "missing\n" if ($options{debug} and $found_xserver == 0);

				# this is always there if we got this far
				print STDERR "  - system-xfree86-shlibs provides x11-shlibs\n" if ($options{debug});
				push(@{$provides->{'system-xfree86-shlibs'}}, 'x11-shlibs');

				if ( $found_xserver ) {
					print STDERR "  - found an X server, system-xfree86 provides xserver and x11\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'xserver', 'x11');
				}

				# "x11-dev" is for BuildDepends: on x11 packages
				if ( has_header('X11/Xlib.h') ) {
					print STDERR "  - system-xfree86-dev provides x11-dev\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-dev'}}, 'x11-dev');
				}
				# now we do the same for libgl
				if ( has_lib('libGL.1.dylib') ) {
					print STDERR "  - system-xfree86-shlibs provides libgl-shlibs\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-shlibs'}}, 'libgl-shlibs');
					print STDERR "  - system-xfree86 provides libgl\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'libgl');
				}
				if ( has_header('GL/gl.h') and has_lib('libGL.dylib') ) {
					print STDERR "  - system-xfree86-dev provides libgl-dev\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-dev'}}, 'libgl-dev');
				}
				if ( has_lib('libXft.dylib') ) {
					if ( defined readlink('/usr/X11R6/lib/libXft.dylib') ) {
						my $link = readlink('/usr/X11R6/lib/libXft.dylib');
						if ($link =~ /libXft\.(\d)/) {
							my $major_version = $1;
							print STDERR "  - libXft points to Xft${major_version}\n" if ($options{debug});
							print STDERR "    - system-xfree86-dev provides xft${major_version}-dev\n" if ($options{debug});
							push(@{$provides->{'system-xfree86-dev'}}, "xft${major_version}-dev");
							print STDERR "    - system-xfree86 provides xft${major_version}\n" if ($options{debug});
							push(@{$provides->{'system-xfree86'}}, "xft${major_version}");
						}
					}
				}
				for my $ver (1, 2) {
					if ( has_lib("libXft.${ver}.dylib") ) {
						print STDERR "  - system-xfree86-shlibs provides xft${ver}-shlibs\n" if ($options{debug});
						push(@{$provides->{'system-xfree86-shlibs'}}, "xft${ver}-shlibs");
					}
				}
				if ( has_lib('libfontconfig.dylib') and
						defined readlink('/usr/X11R6/lib/libfontconfig.dylib') and
						readlink('/usr/X11R6/lib/libfontconfig.dylib') =~ /libfontconfig\.1/ and
						has_header('fontconfig/fontconfig.h') ) {
					print STDERR "  - libfontconfig points to fontconfig1\n" if ($options{debug});
					print STDERR "    - system-xfree86-dev provides fontconfig1-dev\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-dev'}}, 'fontconfig1-dev');
					print STDERR "    - system-xfree86 provides fontconfig1\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'fontconfig1');
				}
				if ( has_lib('libfontconfig.1.dylib') ) {
					print STDERR "  - system-xfree86-shlibs provides fontconfig1-shlibs\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-shlibs'}}, 'fontconfig1-shlibs');
				}
				print STDERR "- checking for rman... " if ($options{debug});
				if (-x '/usr/X11R6/bin/rman') {
					print STDERR "found, system-xfree86 provides rman\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'rman');
				} else {
					print STDERR "missing\n" if ($options{debug});
				}
				print STDERR "- checking for threaded libXt... " if ($options{debug});
				if (-f '/usr/X11R6/lib/libXt.6.dylib' and -x '/usr/bin/grep') {
					if (system('/usr/bin/grep', '-q', '-a', 'pthread_mutex_lock', '/usr/X11R6/lib/libXt.6.dylib') == 0) {
						print STDERR "threaded\n" if ($options{debug});
						print STDERR "  - system-xfree86-shlibs provides xfree86-base-threaded-shlibs\n" if ($options{debug});
						push(@{$provides->{'system-xfree86-shlibs'}}, 'xfree86-base-threaded-shlibs');
						if (grep(/^x11$/, @{$provides->{'system-xfree86'}})) {
							print STDERR "  - system-xfree86 provides xfree86-base-threaded\n" if ($options{debug});
							push(@{$provides->{'system-xfree86'}}, 'xfree86-base-threaded');
						}
					} else {
						print STDERR "not threaded\n" if ($options{debug});
					}
				} else {
					print STDERR "missing libXt or grep\n" if ($options{debug});
				}

				for my $pkg ('system-xfree86', 'system-xfree86-shlibs', 'system-xfree86-dev') {
					if (exists $provides->{$pkg}) {
						$self->{$pkg} = {
							'package'     => $pkg,
							'status'      => STATUS_PRESENT,
							'version'     => "2:${xver}-2",
							'description' => "[placeholder for user installed x11]",
							'descdetail'  => $descdetail,
							'homepage'    => "http://fink.sourceforge.net/faq/usage-general.php#virtpackage",
							'provides'    => join(', ', @{$provides->{$pkg}}),
						};
						if ($pkg eq "system-xfree86-shlibs") {
							$self->{$pkg}->{'description'} = "[placeholder for user installed x11 shared libraries]";
						} elsif ($pkg eq "system-xfree86-dev") {
							$self->{$pkg}->{'description'} = "[placeholder for user installed x11 development tools]";
							$self->{$pkg}->{builddependsonly} = 'true';
						}
					}
				}
			}
		} else {
			print STDERR "- skipping X11 virtuals, existing X11 packages installed\n" if ($options{debug});
		}
	}
}

### query by package name
# returns false when not installed
# returns full version when installed and configured
sub query_package {
	my $self = shift;
	my $pkgname = shift;
	my ($hash);

	if (not ref($self)) {
		if (defined($the_instance)) {
			$self = $the_instance;
		} else {
			$self = Fink::VirtPackage->new();
		}
	}

	if (exists $self->{$pkgname} and exists $self->{$pkgname}->{status}) {
		my ($purge, $ok, $installstat) = split(/\s+/, $self->{$pkgname}->{status});
		return $self->{$pkgname}->{version} if ($installstat eq "installed" and exists $self->{$pkgname}->{version});
	}
	return undef;
}


### retrieve whole list with versions
# doesn't care about installed status
# returns a hash ref, key: package name, value: hash with core fields
# in the hash, 'package' and 'version' are guaranteed to exist
sub list {
	my $self = shift;
	%options = (@_);

	my ($list, $pkgname, $hash, $newhash, $field);

	if (not ref($self)) {
		if (defined($the_instance)) {
			$self = $the_instance;
		} else {
			$self = Fink::VirtPackage->new();
		}
	}

	$list = {};
	foreach $pkgname (keys %$self) {
		next if $pkgname =~ /^_/;
		$hash = $self->{$pkgname};
		next unless exists $hash->{version};

		$newhash = { 'package' => $pkgname, 'version' => $hash->{version} };
		foreach $field (qw(depends provides conflicts maintainer description descdetail homepage status builddependsonly)) {
			if (exists $hash->{$field}) {
				$newhash->{$field} = $hash->{$field};
			}
		}
		$list->{$pkgname} = $newhash;
	}

	return $list;
}


sub has_header {
	my $headername = shift;
	my $dir;

	print STDERR "- checking for header $headername... " if ($options{debug});
	if ($headername =~ /^\// and -f $headername) {
		print STDERR "found\n" if ($options{debug});
		return 1;
	} else {
		for $dir ('/usr/X11R6/include', $basepath . '/include', '/usr/include') {
			if (-f $dir . '/' . $headername) {
				print STDERR "found in $dir\n" if ($options{debug});
				return 1;
			}
		}
	}
	print "missing\n" if ($options{debug});
	return;
}

sub has_lib {
	my $libname = shift;
	my $dir;

	print STDERR "- checking for library $libname... " if ($options{debug});
	if ($libname =~ /^\// and -f $libname) {
		print STDERR "found\n" if ($options{debug});
		return 1;
	} else {
		for $dir ('/usr/X11R6/lib', $basepath . '/lib', '/usr/lib') {
			if (-f $dir . '/' . $libname) {
				print STDERR "found in $dir\n" if ($options{debug});
				return 1;
			}
		}
	}
	print "missing\n" if ($options{debug});
	return;
}


### Check the installed x11 version
sub check_x11_version {
	my (@XF_VERSION_COMPONENTS, $XF_VERSION);
	for my $checkfile ('xterm.1', 'bdftruncate.1', 'gccmakedep.1') {
		if (-f "/usr/X11R6/man/man1/$checkfile") {
			if (open(CHECKFILE, "/usr/X11R6/man/man1/$checkfile")) {
				while (<CHECKFILE>) {
					if (/^.*Version\S* ([^\s]+) .*$/) {
						$XF_VERSION = $1;
						@XF_VERSION_COMPONENTS = split(/\.+/, $XF_VERSION, 4);
						last;
					}
				}
				close(CHECKFILE);
			} else {
				warn "could not read $checkfile: $!\n";
				return;
			}
		}
		last if (defined $XF_VERSION);
	}
	if (not defined $XF_VERSION) {
		for my $binary ('X', 'XDarwin', 'Xquartz') {
			if (-x '/usr/X11R6/bin/' . $binary) {
				if (open (XBIN, "/usr/X11R6/bin/$binary -version -iokit 2>\&1 |")) {
					while (my $line = <XBIN>) {
						if ($line =~ /XFree86 Version ([\d\.]+)/) {
							$XF_VERSION = $1;
							@XF_VERSION_COMPONENTS = split(/\.+/, $XF_VERSION, 4);
							last;
						}
					}
					close(XBIN);
				} else {
					print STDERR "couldn't run $binary: $!\n";
				}
				last;
			}
		}
	}
	if (not defined $XF_VERSION) {
		print STDERR "could not determine XFree86 version number\n";
		return;
	}

	if (@XF_VERSION_COMPONENTS >= 4) {
		# it's a snapshot (ie, 4.3.99.15)
		# give back 3 parts of the component
		return (join('.', @XF_VERSION_COMPONENTS[0..2]));
	} else {
		return (join('.', @XF_VERSION_COMPONENTS[0..1]));
	}
}
### EOF
1;
