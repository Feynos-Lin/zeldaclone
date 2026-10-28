# The Godot binary carries the game data appended to its end,
# so it must never be stripped or post-processed.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global __strip /bin/true
%define _build_id_links none

Name:           wrenmoor
Version:        %{_wren_version}
Release:        1
Summary:        Wrenmoor - an N64-style action adventure prototype
License:        All rights reserved
URL:            https://github.com/Feynos-Lin/zeldaclone
BuildArch:      x86_64
AutoReqProv:    no
Requires:       libglvnd-glx

%description
A small walled town, a field beyond its gate, and a cave the dead keep
crawling out of. Low-poly, fog-drenched, N64-style action adventure.

%install
mkdir -p %{buildroot}/opt/wrenmoor %{buildroot}%{_bindir} %{buildroot}%{_datadir}/applications %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
install -m 0755 %{_wren_src}/build/linux/wrenmoor %{buildroot}/opt/wrenmoor/wrenmoor
ln -s /opt/wrenmoor/wrenmoor %{buildroot}%{_bindir}/wrenmoor
install -m 0644 %{_wren_src}/packaging/wrenmoor.desktop %{buildroot}%{_datadir}/applications/wrenmoor.desktop
install -m 0644 %{_wren_src}/icon.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/wrenmoor.svg

%files
/opt/wrenmoor/wrenmoor
%{_bindir}/wrenmoor
%{_datadir}/applications/wrenmoor.desktop
%{_datadir}/icons/hicolor/scalable/apps/wrenmoor.svg
