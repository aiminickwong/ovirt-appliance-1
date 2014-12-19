#EayunOS Engine Appliance kickstart file

#version=DEVEL

#install

# Installation in text mode
text

# Use network installation
#url --url=http://192.168.2.194/centos6.5/
repo --name="CentOS"  --baseurl=http://192.168.3.239:11080/pulp/repos/centos/6.5/os/x86_64/ --cost=10
repo --name="EPEL6" --baseurl=http://192.168.3.239:11080/pulp/repos/epel/6/x86_64/
repo --name="ovirt239-mirros" --baseurl=http://192.168.3.239:11080/pulp/repos/ovirt/3.5/EL6/ --cost=50
repo --name="ovirt239" --baseurl=http://192.168.3.239/CI-Repos/EayunOS-4.1-testing/x86_64/ --cost=10
repo --name="ovirt159" --baseurl=http://192.168.3.159/eayunVirt/rpms/EayunOS41Prev/ --cost=10
repo --name="eayundm" --baseurl=http://192.168.2.194/repo/eayun-sm/ --cost=10

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
#selinux --permissive

# System timezone
timezone --utc Asia/Shanghai


# System services（need to verify）
#services --enabled="network,sshd,rsyslog,cloud-init,cloud-init-local,cloud-config,cloud-final"
services --enabled="network,sshd,rsyslog"
services --disabled="cloud-init,cloud-init-local,cloud-config,cloud-final"

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
ovirt-engine
ovirt-guest-agent
ovirt-guest-tools
subscription-manager
simple.ovirt.brand
manage-domains-plugin
ovirt-engine-reports
ovirt-engine-reports-setup
ovirt-engine-dwh
ovirt-engine-dwh-setup
engine-vm-backup
ovirt-optimizer
ovirt-optimizer-dependencies
ovirt-optimizer-jboss7
ovirt-optimizer-ui
ovirt-optimizer-setup
patternfly1
engine-reports-config-passwd
wqy-microhei-fonts
hostusb-passthrough
jboss-jackson-bugfix
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

echo "Packages within this cloud image:" | tee /tmp/install.log
echo "-----------------------------------------------------------------------" | tee /tmp/install.log
rpm -qa | tee /tmp/install.log
echo "-----------------------------------------------------------------------" | tee /tmp/install.log

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
#yum install -y ovirt-engine ovirt-guest-agent ovirt-guest-tools
yum install -y eayunos-engine-console

#
echo "Generate a random password"
#
ENGINEADMINPW=`dd if=/dev/urandom bs=512 count=1 2> /dev/null | tr -cd '[:alnum:]' | fold -w10 | head -n1`
REPORTSADMINPW=$ENGINEADMINPW
mkdir /.eayunos
echo $ENGINEADMINPW > /.eayunos/engineadminpw
echo $REPORTSADMINPW > /.eayunos/reportsadminpw
echo "Creating a partial answer file"
cat > /root/eayunos-engine-answers <<__EOF__
# action=setup
[environment:default]
OVESETUP_DIALOG/confirmSettings=bool:True
OVESETUP_CONFIG/applicationMode=str:both
OVESETUP_CONFIG/remoteEngineSetupStyle=none:None
OVESETUP_CONFIG/adminPassword=str:$ENGINEADMINPW
OVESETUP_CONFIG/storageIsLocal=bool:False
OVESETUP_CONFIG/firewallManager=str:iptables
OVESETUP_CONFIG/remoteEngineHostRootPassword=none:None
OVESETUP_CONFIG/updateFirewall=bool:False
OVESETUP_CONFIG/remoteEngineHostSshPort=none:None
OVESETUP_CONFIG/fqdn=str:localhost.localdomain
OVESETUP_CONFIG/storageType=none:None
OSETUP_RPMDISTRO/requireRollback=none:None
OSETUP_RPMDISTRO/enableUpgrade=none:None
OVESETUP_DB/database=str:engine
OVESETUP_DB/fixDbViolations=none:None
OVESETUP_DB/secured=bool:False
OVESETUP_DB/host=str:localhost
OVESETUP_DB/user=str:engine
OVESETUP_DB/securedHostValidation=bool:False
OVESETUP_DB/port=int:5432
OVESETUP_ENGINE_CORE/enable=bool:True
OVESETUP_CORE/engineStop=none:None
OVESETUP_SYSTEM/memCheckEnabled=bool:False
OVESETUP_SYSTEM/nfsConfigEnabled=bool:True
OVESETUP_PKI/organization=str:localdomain
OVESETUP_CONFIG/isoDomainMountPoint=str:/var/lib/exports/iso
OVESETUP_CONFIG/isoDomainName=str:WGT_DOMAIN
OVESETUP_CONFIG/isoDomainACL=str:*(rw)
OVESETUP_AIO/configure=none:None
OVESETUP_AIO/storageDomainName=none:None
OVESETUP_AIO/storageDomainDir=none:None
OVESETUP_PROVISIONING/postgresProvisioningEnabled=bool:True
OVESETUP_APACHE/configureRootRedirection=bool:True
OVESETUP_APACHE/configureSsl=bool:True
OVESETUP_CONFIG/websocketProxyConfig=bool:True
OVESETUP_DWH_CORE/enable=bool:True
OVESETUP_DWH_DB/database=str:ovirt_engine_history
OVESETUP_DWH_DB/secured=bool:False
OVESETUP_DWH_DB/host=str:localhost
OVESETUP_DWH_DB/disconnectExistingDwh=none:None
OVESETUP_DWH_DB/restoreBackupLate=bool:True
OVESETUP_DWH_DB/user=str:ovirt_engine_history
OVESETUP_DWH_DB/securedHostValidation=bool:False
OVESETUP_DWH_DB/performBackup=none:None
OVESETUP_DWH_DB/password=str:history
OVESETUP_DWH_DB/port=str:5432
OVESETUP_DWH_PROVISIONING/postgresProvisioningEnabled=bool:True
OVESETUP_REPORTS_CORE/enable=bool:True
OVESETUP_REPORTS_CONFIG/adminPassword=str:$REPORTSADMINPW
OVESETUP_REPORTS_DB/database=str:ovirt_engine_reports
OVESETUP_REPORTS_DB/secured=bool:False
OVESETUP_REPORTS_DB/host=str:localhost
OVESETUP_REPORTS_DB/user=str:ovirt_engine_reports
OVESETUP_REPORTS_DB/securedHostValidation=bool:False
OVESETUP_REPORTS_DB/port=str:5432
OVESETUP_REPORTS_PROVISIONING/postgresProvisioningEnabled=bool:True
__EOF__

#fix pki-pkcs12-extract.sh script
echo "fix pki-pkcs12-extract.sh script"
sed -i "s/key=\/dev\/fd\/1/key=\/proc\/self\/fd\/1/g" /usr/share/ovirt-engine/bin/pki-pkcs12-extract.sh
sed -i "s/cert=\/dev\/fd\/1/cert=\/proc\/self\/fd\/1/g" /usr/share/ovirt-engine/bin/pki-pkcs12-extract.sh

echo "Deploy engine"
engine-setup --config-append=/root/eayunos-engine-answers --offline

#auto init WGT_DOMAIN isodomain
ISOPATH=`find /var/lib/exports/iso -name 11111111-1111-1111-1111-111111111111`
ln /usr/share/ovirt-guest-tools/ovirt-guest-tools-*.iso $ISOPATH/WGT-3.5_5.iso

#ovirt-engine-rename workaround
sed -i '164,184s/^/#&/g'  /usr/share/ovirt-engine/setup/bin/../plugins/ovirt-engine-rename/ovirt-engine/database.py
sed -i '164i\\tpass' /usr/share/ovirt-engine/setup/bin/../plugins/ovirt-engine-rename/ovirt-engine/database.py

#UIPlugin setup
ovirt-optimizer-setup --password=$ENGINEADMINPW
vm-backup-setup --password=$ENGINEADMINPW
engine-manage-domains-setup

#Generated firewall rule
echo "Generated firewall rule"
cat > /etc/sysconfig/iptables <<EOF
# Generated by ovirt-engine installer
#filtering rules
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -p icmp -m icmp --icmp-type any -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 111 -j ACCEPT
-A INPUT -p udp -m state --state NEW -m udp --dport 111 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 662 -j ACCEPT
-A INPUT -p udp -m state --state NEW -m udp --dport 662 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 875 -j ACCEPT
-A INPUT -p udp -m state --state NEW -m udp --dport 875 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 892 -j ACCEPT
-A INPUT -p udp -m state --state NEW -m udp --dport 892 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 2049 -j ACCEPT
-A INPUT -p udp -m state --state NEW -m udp --dport 32769 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 32803 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 5432 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A INPUT -p udp -m state --state NEW -m udp --dport 7410 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 6100 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT

#drop all rule
-A INPUT -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOF

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

%post --erroronfail
#
#Modify release infomation
#
echo "Modify /etc/issue"
cat > /etc/issue <<EOF
EayunOS Engine Appliance release 4.1.0
Kernel \r on an \m

Please login as 'engineadm' to configure the appliance
EOF

cat > /etc/eayunos-release <<EOF
EayunOS Engine Appliance release 4.1.0 (Beta)
EOF

cat > /etc/redhat-release <<EOF
EayunOS Engine Appliance release 4.1.0 (Beta)
EOF

cat > /etc/centos-release <<EOF
EayunOS Engine Appliance release 4.1.0 (Beta)
EOF
%end

%post --erroronfail
#
#permit sshd password authentication
#
sed -i "s/^PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
%end

#%post --erroronfail
#
#Erase installization file & log
#
#rm -rf /root/anaconda-ks.cfg
#rm -rf /root/eayunos-engine-answers
#rm -rf /tmp/ks-*
#%end

