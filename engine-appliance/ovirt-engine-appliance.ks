lang en_US.UTF-8
keyboard us
timezone --utc Etc/UTC
auth --enableshadow --passalgo=sha512
selinux --permissive
rootpw --lock
user --name=node --lock
firstboot --disabled
services --enabled=ssh
poweroff

clearpart --all --initlabel
bootloader --timeout=1
# Size needs to be something smaller than the disk size, grow ensures that the whole disk is used
part / --size=2048 --grow --fstype=ext4 --fsoptions=discard

%packages --ignoremissing
cloud-init
initial-setup
%end


#
# CentOS repositories
#
url --url=http://192.168.2.65:11080/pulp/repos/centos/7.2.1511/os/x86_64/
repo --name=updates --baseurl=http://192.168.2.65:11080/pulp/repos/centos/7.2.1511/updates/x86_64/
repo --name=extra --baseurl=http://192.168.2.65:11080/pulp/repos/centos/7.2.1511/extras/x86_64/

#
# Adding upstream oVirt
#
%post --erroronfail
set -x

rm -rfv /etc/yum.repos.d/*

cat > /etc/yum.repos.d/local.repo <<__EOF__
[centos-7.2.1511-os-x86_64]
name=Local CentOS 7.2.1511 OS Repo x86_64
baseurl=http://192.168.2.65:11080/pulp/repos/centos/7.2.1511/os/x86_64/
gpgcheck=0
enabled=1

[centos-7.2.1511-updates-x86_64]
name=Local CentOS 7.2.1511 Updates Repo x86_64
baseurl=http://192.168.2.65:11080/pulp/repos/centos/7.2.1511/updates/x86_64/
gpgcheck=0
enabled=1

[centos-7.2.1511-extras-x86_64]
name=Local CentOS 7.2.1511 Extras Repo x86_64
baseurl=http://192.168.2.65:11080/pulp/repos/centos/7.2.1511/extras/x86_64/
gpgcheck=0
enabled=1

[epel-7-x86_64]
name=Local EPEL 7 Repo x86_64
baseurl=http://192.168.2.65:11080/pulp/repos/epel/7/x86_64/
gpgcheck=0
enabled=1

[glusterfs-latest-el7-noarch]
name=Local GlusterFS Latest Repo for EL7 noarch
baseurl=http://192.168.9.60/pulp/repos/gluster-noarch-epel/el7/
gpgcheck=0
enabled=1

[glusterfs-latest-el7-x86_64]
name=Local GlusterFS Latest Repo for EL7 x86_64
baseurl=http://192.168.9.60/pulp/repos/gluster-epel/el7/
gpgcheck=0
enabled=1

[ovirt-36]
name=ovirt 3.6
baseurl=http://192.168.9.60/pulp/repos/ovirt-36/el7/
gpgcheck=0
enabled=1
exclude=ovirt-engine ovirt-engine-appliance ovirt-engine-backend ovirt-engine-dbscripts ovirt-engine-extensions-api-impl ovirt-engine-lib ovirt-engine-restapi ovirt-engine-setup* ovirt-engine-tools* ovirt-engine-userportal* ovirt-engine-vmconsole-proxy-helper ovirt-engine-webadmin-portal* ovirt-engine-websocket-proxy ovirt-hosted-engine-setup

[ovirt-36-static]
name=ovirt 3.6 snapshot static
baseurl=http://192.168.9.60/pulp/repos/ovirt-36-snap-static/el7/
gpgcheck=0
enabled=1

[patternfly]
name=patternfly1
baseurl=http://copr-be.cloud.fedoraproject.org/results/patternfly/patternfly1/epel-7-x86_64/
gpgcheck=0
enabled=1

[eayunos42]
name=EayunOS 4.2 repo
baseurl=http://192.168.2.56/eayunVirt/rpms/EayunOS42/
gpgcheck=0
enabled=1
__EOF__

yum clean all
yum install -y ovirt-engine
yum install -y ovirt-engine-dwh
yum install -y ovirt-engine-webadmin-reports
yum install -y ovirt-imageio-common ovirt-imageio-proxy
yum install -y manage-domains-plugin
yum install -y engine-vm-backup
yum install -y iso-uploader-plugin

#
echo "Creating a partial answer file"
#
DWHPASSWD=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 22`
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
OVESETUP_DWH_CONFIG/dwhDbBackupDir=str:/var/lib/ovirt-engine-dwh/backups
OVESETUP_DWH_CORE/enable=bool:True
OVESETUP_DWH_DB/secured=bool:False
OVESETUP_DWH_DB/restoreBackupLate=bool:True
OVESETUP_DWH_DB/disconnectExistingDwh=none:None
OVESETUP_DWH_DB/host=str:localhost
OVESETUP_DWH_DB/user=str:ovirt_engine_history
OVESETUP_DWH_DB/password=str:$DWHPASSWD
OVESETUP_DWH_DB/dumper=str:pg_custom
OVESETUP_DWH_DB/database=str:ovirt_engine_history
OVESETUP_DWH_DB/performBackup=none:None
OVESETUP_DWH_DB/port=int:5432
OVESETUP_DWH_DB/filter=none:None
OVESETUP_DWH_DB/restoreJobs=int:2
OVESETUP_DWH_DB/securedHostValidation=bool:False
OVESETUP_DWH_PROVISIONING/postgresProvisioningEnabled=bool:True
OVESETUP_ENGINE_CORE/enable=bool:True
OVESETUP_SYSTEM/nfsConfigEnabled=bool:False
OVESETUP_SYSTEM/memCheckEnabled=bool:False
OVESETUP_CONFIG/applicationMode=str:virt
OVESETUP_CONFIG/firewallManager=str:firewalld
OVESETUP_CONFIG/storageType=str:nfs
OVESETUP_CONFIG/sanWipeAfterDelete=bool:False
OVESETUP_CONFIG/updateFirewall=bool:True
OVESETUP_CONFIG/websocketProxyConfig=bool:True
OVESETUP_PROVISIONING/postgresProvisioningEnabled=bool:True
OVESETUP_VMCONSOLE_PROXY_CONFIG/vmconsoleProxyConfig=bool:True
OVESETUP_APACHE/configureRootRedirection=bool:True
OVESETUP_APACHE/configureSsl=bool:True
OSETUP_RPMDISTRO/requireRollback=none:None
OSETUP_RPMDISTRO/enableUpgrade=none:None
__EOF__

echo "Enabling ssh_pwauth in cloud.cfg.d"
cat > /etc/cloud/cloud.cfg.d/42_ovirt_appliance.cfg <<__EOF__
# Enable ssh pwauth by default. This ensures that ssh_pwauth is
# even enabled when cloud-init does not find a seed.
ssh_pwauth: True
__EOF__


#
# Enable the guest agent
#
yum install -y ovirt-guest-agent-common
systemctl enable ovirt-guest-agent.service

rm -vf /etc/yum.repos.d/local.repo

rm -vf /etc/sysconfig/network-scripts/ifcfg-e*
%end
