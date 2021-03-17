Name: cdlabelgen
Summary: Generates frontcards and traycards for inserting in CD/DVD jewel cases.
Version: 4.3.0
Release: 1
Source: http://www.aczoom.com/pub/tools/cdlabelgen-%{version}.tgz
URL: http://www.aczoom.com/tools/cdinsert/
BuildRoot: /tmp/%{name}-root
License: BSD
Group: Applications/Publishing
BuildArch: noarch
AutoReqProv: no
# cdlabelgen requires:
Requires: perl >= 0:5.005, perl(Getopt::Long), perl(Socket)
# cdinsert.pl requires additional:
# Requires: perl(CGI) >= 3.21, perl(CGI::Carp), perl(File::Copy), perl(Getopt::Std), perl(POSIX), perl(HTML::Template), perl(HTML::FillInForm)

%description
Cdlabelgen is a utility which generates frontcards and traycards (in
PostScript(TM) format) for CD/DVD jewelcases.

%prep
%setup -q

%build
pod2man cdlabelgen.pod > cdlabelgen.1
pod2html cdlabelgen.pod > cdlabelgen.html

%install
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_datadir}/cdlabelgen
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man1
install -m 755 cdlabelgen $RPM_BUILD_ROOT%{_bindir}
install -m 644 postscript/* $RPM_BUILD_ROOT%{_datadir}/cdlabelgen
install -m 644 cdlabelgen.1 $RPM_BUILD_ROOT%{_mandir}/man1

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc ChangeLog README INSTALL INSTALL.WEB cdinsert.pl
%{_bindir}/cdlabelgen
%{_datadir}/cdlabelgen
%{_mandir}/*/*

%changelog
* Wed Jul 15 2003 Avinash Chopde <avinash@aczoom.com>
- see file ChangeLog for newer changes

* Wed Aug 21 2002 Alessandro Dotti Contra <alessandro.dotti@libero.it>
- update for version 2.5.0

* Thu Mar 14 2002 Peter Bieringer <pb@bieringer.de>
- update for version 2.2.1

* Wed Feb 20 2002 Peter Bieringer <pb@bieringer.de>
- update for version 2.2.0

* Mon May 21 2001 Tim Powers <timp@redhat.com>
- built for the distro

* Mon Jul 24 2000 Prospector <prospector@redhat.com>
- rebuilt

* Mon Jul 10 2000 Tim Powers <timp@redhat.com>
- rebuilt

* Mon Jun 5 2000 Tim Powers <timp@redhat.com>
- fix man page location

* Mon May 8 2000 Tim Powers <timp@redhat.com>
- rebuilt for 7.0
* Tue Jan 4 2000 Tim Powers <timp@redhat.com>
- removed unneeded defines
- rebuilt for 6.2
* Mon Aug 23 1999 Preston Brown <pbrown@redhat.com>
- adopted for Powertools 6.1.
