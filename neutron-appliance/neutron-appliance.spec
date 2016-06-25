%define _version 1.0
%define _release 0

Name:       neutron-appliance
Version:    %{_version}
Release:    %{_release}%{?dist}
Summary:    neutron appliance disk

Group:      ovirt-engine-third-party
License:    GPL
URL:        http://www.eayun.com
Source0:    neutron-appliance-%{_version}.tar.gz
BuildRoot:  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

Requires:   ovirt-hosted-engine-setup
BuildRequires:  imagefactory
BuildRequires:  rpm-build

%description
neutron appliance disk to be imported to hosted_storage for use by eayunos

%prep
%setup -q

%build
export LIBGUESTFS_BACKEND=direct
imagefactory --debug target_image --template rdo-juno-centos-7-ml2-plugin-x86_64.tdl openstack-kvm 2>&1|tee output.log

%install
mkdir -p %{buildroot}/usr/share/neutron-appliance
mkdir -p %{buildroot}/usr/share/ovirt-hosted-engine-setup/plugins/ovirt-hosted-engine-setup
cp `tail output.log|grep 'Image filename'|cut -d' ' -f3` %{buildroot}/usr/share/neutron-appliance/neutron-appliance-disk.qcow2
cp -r otopi/* %{buildroot}/usr/share/ovirt-hosted-engine-setup/plugins/ovirt-hosted-engine-setup
cp -r conf_img %{buildroot}/usr/share/neutron-appliance

%files
%attr(0644,36,36) /usr/share/neutron-appliance/neutron-appliance-disk.qcow2
/usr/share/ovirt-hosted-engine-setup/plugins/ovirt-hosted-engine-setup
/usr/share/neutron-appliance/conf_img

%clean
rm -rf %{buildroot}

%changelog

* Sat Jun 25 2016 walteryang47 <walteryang47@gmail.com> 1.0-0
- First build

