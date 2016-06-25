#
# ovirt-hosted-engine-setup -- ovirt hosted engine setup
# Copyright (C) 2013-2015 Red Hat, Inc.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#


"""
Neutron image creation plugin.
"""


import gettext
import grp
import pwd
import os
import uuid
import tarfile
import tempfile
import subprocess


from otopi import plugin
from otopi import transaction
from otopi import util


from ovirt_hosted_engine_ha.lib import heconflib
from ovirt_hosted_engine_ha.agent import constants as agentconst
from ovirt_hosted_engine_setup import constants as ohostedcons
from ovirt_hosted_engine_setup import domains as ohosteddomains


def _(m):
    return gettext.dgettext(message=m, domain='ovirt-hosted-engine-setup')


class NeutronImageTransaction(transaction.TransactionElement):
    """Neutron image transaction element."""

    def __init__(self, parent, src, img_uuid, vol_uuid):
        super(NeutronImageTransaction, self).__init__()
        self._parent = parent
        self._src = src
        self.img_uuid = img_uuid
        self.vol_uuid = vol_uuid
        self._prepared = False

    def __str__(self):
        return _("Image Transaction")

    def _get_volume_path(self):
        """
        Return path of the volume file inside the domain
        """
        return heconflib.get_volume_path(
            self._parent.environment[
                ohostedcons.StorageEnv.DOMAIN_TYPE
            ],
            self._parent.environment[ohostedcons.StorageEnv.SD_UUID],
            self.img_uuid,
            self.vol_uuid
        )

    def _uploadVolume(self):
        try:
            destination = self._get_volume_path()
        except RuntimeError as e:
            return (1, str(e))
        try:
            self._parent.execute(
                (
                    self._parent.command.get('sudo'),
                    '-u',
                    'vdsm',
                    '-g',
                    'kvm',
                    self._parent.command.get('qemu-img'),
                    'convert',
                    '-O',
                    'raw',
                    self._src,
                    destination
                ),
                raiseOnError=True
            )
        except RuntimeError as e:
            self._parent.logger.debug('error uploading neutron image: ' + str(e))
            return (1, str(e))
        return (0, 'OK')

    def prepare(self):
        self._prepared = True

    def abort(self):
        self._parent.logger.info(
            _('Neutron image not uploaded to data domain')
        )

    def commit(self):
        self._parent.logger.info(
            _(
                'Uploading neutron disk volume to data domain '
                '(could take a few minutes depending on archive size)'
            )
        )
        status, message = self._uploadVolume()
        if status != 0:
            raise RuntimeError(message)
        self._parent.logger.info(_('Neutron Image successfully imported'))


@util.export
class Plugin(plugin.PluginBase):
    """
    Neutron vm image creation plugin.
    """

    def __init__(self, context):
        super(Plugin, self).__init__(context=context)

    @plugin.event(
        stage=plugin.Stages.STAGE_MISC,
        after=(
            ohostedcons.Stages.SANLOCK_INITIALIZED,
        ),
        condition=lambda self: not self.environment[
            ohostedcons.CoreEnv.IS_ADDITIONAL_HOST
        ],
    )
    def _misc(self):
        image_size_gb = 10
        image_desc = '{"DiskAlias":"Neutron_appliance_disk","DiskDescription":"Neutron appliance disk, based on Centos 7.0.1406, powered by EayunStack 1.1"}'

        sdUUID = self.environment[ohostedcons.StorageEnv.SD_UUID]
        spUUID = self.environment[ohostedcons.StorageEnv.SP_UUID]
        imgUUID = str(uuid.uuid4())
        volUUID = str(uuid.uuid4())
        self.environment['neutron_img_uuid'] = imgUUID
        self.environment['neutron_vol_uuid'] = volUUID
        cli = self.environment[ohostedcons.VDSMEnv.VDS_CLI]

        if self.environment[ohostedcons.StorageEnv.DOMAIN_TYPE] in (
            ohostedcons.DomainTypes.ISCSI,
            ohostedcons.DomainTypes.FC,
        ):
            # Checking the available space on VG where
            # we have to preallocate the image
            vginfo = cli.getVGInfo(
                self.environment[ohostedcons.StorageEnv.VG_UUID]
            )
            self.logger.debug(vginfo)
            if vginfo['status']['code'] != 0:
                raise RuntimeError(vginfo['status']['message'])
            vgfree = int(vginfo['info']['vgfree'])
            available_gb = vgfree / pow(2, 30)
            required_size = image_size_gb + int(self.environment[
                ohostedcons.StorageEnv.CONF_IMAGE_SIZE_GB
            ])
            if required_size > available_gb:
                raise ohosteddomains.InsufficientSpaceError(
                    _(
                        'Error: the VG on block device has capacity of only '
                        '{available_gb} GiB while '
                        '{required_size} GiB is required for the neutron image'
                    ).format(
                        available_gb=available_gb,
                        required_size=required_size,
                    )
                )

        self.logger.info(_('Creating Neutron VM Image'))
        self.logger.debug('createVolume for neutron')
        volFormat = ohostedcons.VolumeFormat.RAW_FORMAT
        preallocate = ohostedcons.VolumeTypes.SPARSE_VOL
        if self.environment[ohostedcons.StorageEnv.DOMAIN_TYPE] in (
            ohostedcons.DomainTypes.ISCSI,
            ohostedcons.DomainTypes.FC,
        ):
            # Can't use sparse volume on block devices
            preallocate = ohostedcons.VolumeTypes.PREALLOCATED_VOL

        diskType = 2

        heconflib.create_and_prepare_image(
            self.logger,
            cli,
            volFormat,
            preallocate,
            sdUUID,
            spUUID,
            imgUUID,
            volUUID,
            diskType,
            image_size_gb,
            image_desc,
        )
        with transaction.Transaction() as localtransaction:
            localtransaction.append(
                NeutronImageTransaction(
                    parent=self,
                    src='/usr/share/neutron-appliance/neutron-appliance-disk.qcow2',
                    img_uuid=imgUUID,
                    vol_uuid=volUUID,
                )
            )

        # create conf image
        conf_img_uuid = str(uuid.uuid4())
        conf_vol_uuid = str(uuid.uuid4())
        self.environment['neutron_conf_img_uuid'] = conf_img_uuid
        self.environment['neutron_conf_vol_uuid'] = conf_vol_uuid
        heconflib.create_and_prepare_image(
            self.logger,
            self.environment[ohostedcons.VDSMEnv.VDS_CLI],
            ohostedcons.VolumeFormat.RAW_FORMAT,
            ohostedcons.VolumeTypes.PREALLOCATED_VOL,
            sdUUID,
            spUUID,
            conf_img_uuid,
            conf_vol_uuid,
            diskType,
            self.environment[ohostedcons.StorageEnv.CONF_IMAGE_SIZE_GB],
            '{"Updated":true,"Size":10240,"Last Updated":"Sun Jun 26 10:21:01 CST 2016","Storage Domains":[{"uuid":"%s"}],"Disk Description":"OVF_STORE"}'
                % self.environment[ohostedcons.StorageEnv.SD_UUID],
        )

    @plugin.event(
        stage=plugin.Stages.STAGE_CLOSEUP,
        after=(
            ohostedcons.Stages.IMAGES_REPREPARED,
        ),
        condition=lambda self: not self.environment[
            ohostedcons.CoreEnv.IS_ADDITIONAL_HOST
        ],
    )
    def _closeup_create_neutron_tar(self):
        dest = heconflib.get_volume_path(
            self.environment[
                ohostedcons.StorageEnv.DOMAIN_TYPE
            ],
            self.environment[ohostedcons.StorageEnv.SD_UUID],
            self.environment['neutron_conf_img_uuid'],
            self.environment['neutron_conf_vol_uuid']
        )

        tempdir = tempfile.gettempdir()
        fd, _tmp_tar = tempfile.mkstemp(
            suffix='.tar',
            dir=tempdir,
        )
        os.close(fd)
        self.logger.debug('temp conf img tar file: ' + _tmp_tar)
        tar = tarfile.TarFile(name=_tmp_tar, mode='w')
        conf_img_dir = '/usr/share/neutron-appliance/conf_img/'
        for filename in os.listdir(conf_img_dir):
            if not filename.startswith('.'):
                if filename.endswith('.ovf'):
                    with open(conf_img_dir + filename, 'r') as f:
                        content = f.read()
                        content = content.replace('{img_uuid}', self.environment['neutron_img_uuid'])
                        content = content.replace('{vol_uuid}', self.environment['neutron_vol_uuid'])
                        content = content.replace('{sd_uuid}', self.environment[ohostedcons.StorageEnv.SD_UUID])
                        heconflib._add_to_tar(
                            tar,
                            filename,
                            content,
                        )
                if filename.endswith('.json'):
                    with open(conf_img_dir + filename, 'r') as f:
                        content = f.read()
                        content = content.replace('{sd_uuid}', self.environment[ohostedcons.StorageEnv.SD_UUID])
                        heconflib._add_to_tar(
                            tar,
                            filename,
                            content,
                        )
        tar.close()
        os.chown(
            _tmp_tar,
            pwd.getpwnam(agentconst.VDSM_USER).pw_uid,
            grp.getgrnam(agentconst.VDSM_GROUP).gr_gid,
        )

        self.logger.info('Saving neutron template conf image volume: %s' % self.environment['neutron_vol_uuid'])

        cmd_list = [
            'sudo',
            '-u',
            agentconst.VDSM_USER,
            'dd',
            'if={source}'.format(source=_tmp_tar),
            'of={dest}'.format(dest=dest),
            'bs=4k',
        ]
        self.logger.debug("conf img executing: '{cmd}'".format(cmd=' '.join(cmd_list)))
        pipe = subprocess.Popen(
            cmd_list,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stdout, stderr = pipe.communicate()
        pipe.wait()
        self.logger.debug('stdout: ' + str(stdout))
        self.logger.debug('stderr: ' + str(stderr))
        os.unlink(_tmp_tar)
        if pipe.returncode != 0:
            raise RuntimeError('Unable to write ConfImage')



# vim: expandtab tabstop=4 shiftwidth=4
