#EayunOS Engine Appliance kickstart file

#version=DEVEL

#install

# Installation in text mode
text

# Use network installation
url --url=http://192.168.3.239/mirrors/CentOS/6.5/os/x86_64/
repo --name="CentOS"  --baseurl=http://192.168.3.239/mirrors/CentOS/6.5/os/x86_64/ --cost=100
repo --name="EPEL6" --baseurl=http://192.168.3.239/mirrors/epel/6/x86_64/

# System language
lang en_US.UTF-8

# keyboard layouts
keyboard us

# Poweroff after installation
poweroff

# Network information
#network --onboot yes --device eth0 --bootproto dhcp --noipv6
network --activate

#Define root password
rootpw --lock --plaintext none

# Firewall configuration
firewall --disabled

# System authorization information
authconfig --enableshadow --passalgo=sha512

# SELinux configuration
selinux --permissive

# System timezone
timezone Asia/Shanghai


# System services（need to verify）
#services --enabled="network,sshd,rsyslog,cloud-init,cloud-init-local,cloud-config,cloud-final"
services --enabled="network,sshd,rsyslog"
services --disabled="cloud-init"

# System bootloader configuration
#bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet"
bootloader --location=mbr --timeout=1 --append="console=tty1 linux edd=off"

# The following is the partition information you requested
# Note that any partitions you deleted are not expressed
# here so unless you clear all partitions first, this is
# not guaranteed to work
#clearpart --all --drives=sda
#volgroup VolGroup --pesize=4096 pv.008002
#logvol / --fstype=ext4 --name=lv_root --vgname=VolGroup --grow --size=1024 --maxsize=51200
#logvol swap --name=lv_swap --vgname=VolGroup --grow --size=819 --maxsize=819

#part /boot --fstype=ext4 --size=500
#part pv.008002 --grow --size=1

# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all
# Disk partitioning information
part / --size 8000 --fstype ext4 --fsoptions discard


%packages --ignoremissing
@core
cloud-init
cloud-utils-growpart
dracut-modules-growroot
grubby
heat-cfntools
rsync
syslinux-extlinux
tar
%end

# Centos6 & EPEL6 does not have these packages
#dracut-config-generic
#initial-setup
#kernel-core

%post --erroronfail

# Create grub.conf for EC2. This used to be done by appliance creator but
# anaconda doesn't do it. And, in case appliance-creator is used, we're
# overriding it here so that both cases get the exact same file.
# Note that the console line is different -- that's because EC2 provides
# different virtual hardware, and this is a convenient way to act differently
echo -n "Creating grub.conf for pvgrub"
rootuuid=$( awk '$2=="/" { print $1 };'  /etc/fstab )
mkdir /boot/grub
echo -e 'default=0\ntimeout=0\n\n' > /boot/grub/grub.conf
for kv in $( ls -1v /boot/vmlinuz* |grep -v rescue |sed s/.*vmlinuz-//  ); do
  echo "title EayunOS 4.1 ($kv)" >> /boot/grub/grub.conf
  echo -e "\troot (hd0,0)" >> /boot/grub/grub.conf
  echo -e "\tkernel /boot/vmlinuz-$kv ro root=$rootuuid no_timer_check console=tty1 LANG=en_US.UTF-8" >> /boot/grub/grub.conf
  echo -e "\tinitrd /boot/initramfs-$kv.img" >> /boot/grub/grub.conf
  echo
done
%end

%post --erroronfail
# older versions of livecd-tools do not follow "rootpw --lock" line above
# https://bugzilla.redhat.com/show_bug.cgi?id=964299
#passwd -l root #ERROR
# remove the user anaconda forces us to make
#userdel -r none #user none does not exsit

echo -n "Network fixes"
# initscripts don't like this file to be missing.
cat > /etc/sysconfig/network << EOF
NETWORKING=yes
NOZEROCONF=yes
EOF

# For cloud images, 'eth0' _is_ the predictable device name, since
# we don't want to be tied to specific virtual (!) hardware
rm -f /etc/udev/rules.d/70*
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

# simple eth0 config, again not hard-coded to the build hardware
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
PERSISTENT_DHCLIENT="yes"
EOF

# generic localhost names
cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF
echo .

# make sure firstboot doesn't start
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

echo "Cleaning old yum repodata."
yum history new
yum clean all
truncate -c -s 0 /var/log/yum.log

echo "Import RPM GPG key"
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

echo "Packages within this cloud image:"
echo "-----------------------------------------------------------------------"
rpm -qa
echo "-----------------------------------------------------------------------"

echo "Fixing SELinux contexts."
touch /var/log/cron
touch /var/log/boot.log
mkdir -p /var/cache/yum
#chattr -i /boot/extlinux/ldlinux.sys
#/usr/sbin/fixfiles -R -a restore
# "fixfiles" is in /sbin for centos6
/sbin/fixfiles -R -a restore
#chattr +i /boot/extlinux/ldlinux.sys


%end

%post --erroronfail
#
echo "Preparing unconfigured"
#
#touch /.unconfigured
echo "Nothing to do"
%end

%post --erroronfail
#
echo "Pre-Installing oVirt stuff"
#
##yum install -y http://resources.ovirt.org/pub/yum-repo/ovirt-release35.rpm
#rpm -ivh http://resources.ovirt.org/pub/yum-repo/ovirt-release35.rpm
rpm -ivh http://192.168.2.194/ovirt3.5/local-ovirt-1.0-1.el6.x86_64.rpm
yum install -y ovirt-engine ovirt-guest-agent

#
echo "Creating a partial answer file"
#
cat > /root/ovirt-engine-answers <<__EOF__
[environment:default]
OVESETUP_CORE/engineStop=none:None
OVESETUP_DIALOG/confirmSettings=bool:True
OVESETUP_DB/database=str:engine
OVESETUP_DB/fixDbViolations=none:None
OVESETUP_DB/secured=bool:False
OVESETUP_DB/securedHostValidation=bool:False
OVESETUP_DB/host=str:localhost
OVESETUP_DB/user=str:engine
OVESETUP_DB/port=int:5432
OVESETUP_SYSTEM/nfsConfigEnabled=bool:False
OVESETUP_CONFIG/applicationMode=str:virt
OVESETUP_CONFIG/firewallManager=str:iptables
OVESETUP_CONFIG/websocketProxyConfig=none:True
OVESETUP_CONFIG/storageType=str:nfs
OVESETUP_PROVISIONING/postgresProvisioningEnabled=bool:True
OVESETUP_APACHE/configureRootRedirection=bool:True
OVESETUP_APACHE/configureSsl=bool:True
OSETUP_RPMDISTRO/requireRollback=none:None
OSETUP_RPMDISTRO/enableUpgrade=none:None
__EOF__

%end

%post --erroronfail
#
echo "Enabling sudo for wheels"
#
sed -i "/%wheel.*NOPASSWD/ s/^#//" /etc/sudoers
passwd --delete root
passwd --expire root
%end

#%post --erroronfail
#
#echo "Zeroing out empty space."
#
# This forces the filesystem to reclaim space from deleted files
#dd bs=1M if=/dev/zero of=/var/tmp/zeros || :
#rm -f /var/tmp/zeros
#echo "(Don't worry -- that out-of-space error was expected.)"

#%end

%post --erroronfail
#
#echo "Clear repo directory"
#
rm -rf /etc/yum.repos.d/*
%end

%post --erroronfail
#
#echo "Empty resolv.conf contents"
#
echo "" > /etc/resolv.conf
%end
