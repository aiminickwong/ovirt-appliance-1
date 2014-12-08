
#
# How to use
# $ export ALL_PROXY=10.0.2.2:3128
# $ make run-install
#

KICKSTART = kickstarts/runtime-layout.ks

DISK_NAME = hda.qcow2
#DISK_SIZE = 10G
DISK_SIZE = 50G

VM_RAM = 2048
VM_SMP = 4

QEMU = qemu-kvm
QEMU_APPEND =
CURL = curl -L -O

CENTOS_RELEASEVER = 6.5
CENTOS_ANACONDA_RELEASEVER = 6.5
CENTOS_URL = http://192.168.2.194/centos6.5
CENTOS_ANACONDA_URL = $(CENTOS_URL)


SHELL = /bin/bash


.INTERMEDIATE: spawned_pids

vmlinuz:
	$(CURL) $(CENTOS_ANACONDA_URL)/isolinux/vmlinuz

initrd.img:
	$(CURL) $(CENTOS_ANACONDA_URL)/isolinux/initrd.img


define TREEINFO
[general]
name = CentOS-$(CENTOS_RELEASEVER)
family = CentOS
variant = CentOS
version = $(CENTOS_RELEASEVER)
packagedir =
arch = x86_64

[images-x86_64]
kernel = vmlinuz
initrd = initrd.img
endef

.PHONY: .treeinfo
export TREEINFO
.treeinfo:
	echo -e "$$TREEINFO" > $@

run-install: PYPORT:=$(shell echo $$(( 50000 + $$RANDOM % 15000 )) )
run-install: vmlinuz initrd.img .treeinfo $(KICKSTART)
	python -m SimpleHTTPServer $(PYPORT) & echo $$! > spawned_pids
	qemu-img create -f qcow2 $(DISK_NAME) $(DISK_SIZE)
	$(QEMU) \
		-vnc 0.0.0.0:7 \
		-serial stdio \
		-smp $(VM_SMP) -m $(VM_RAM) \
		-hda $(DISK_NAME) \
		-kernel vmlinuz \
		-initrd initrd.img \
		-append "console=ttyS0 repo=$(CENTOS_URL) ks=http://10.0.2.2:$(PYPORT)/$(KICKSTART) quiet $(QEMU_APPEND)" ; \
	kill $$(cat spawned_pids)
