import fnmatch
import os
import tarfile
import ConfigParser

import koji
import koji.tasks as tasks
from __main__ import BuildRoot

__all__ = ('SaveFailedTreeTask',)

CONFIG_FILE = '/etc/kojid/plugins/save_failed_tree.conf'
config = None


def omit_paths(tarinfo):
    if any([fnmatch.fnmatch(tarinfo.name, f) for f in config['path_filters']]):
        return None
    else:
        return tarinfo


def read_config():
    global config
    cp = ConfigParser.SafeConfigParser()
    cp.read(CONFIG_FILE)
    config = {
        'path_filters': [],
        'volume': None,
    }
    if cp.has_option('filters', 'paths'):
        config['path_filters'] = cp.get('filters', 'paths').split()
    if cp.has_option('general', 'volume'):
        config['volume'] = cp.get('general', 'volume').strip()


class SaveFailedTreeTask(tasks.BaseTaskHandler):
    Methods = ['saveFailedTree']
    _taskWeight = 3.0

    def handler(self, buildrootID, full=False):
        self.logger.debug("Saving buildroot %d [full=%s]", buildrootID, full)
        read_config()

        brinfo = self.session.getBuildroot(buildrootID)
        if brinfo is None:
            raise koji.GenericError("Nonexistent buildroot: %s" % buildrootID)
        host_id = self.session.host.getHost()['id']
        if brinfo['host_id'] != host_id:
            raise koji.GenericError("Task is run on wrong builder")
        broot = BuildRoot(self.session, self.options, brinfo['id'])
        path = broot.rootdir()

        if full:
            self.logger.debug("Adding buildroot (full): %s" % path)
        else:
            path = os.path.join(path, 'builddir')
            self.logger.debug("Adding buildroot: %s" % path)
        if not os.path.exists(path):
            raise koji.GenericError("Buildroot directory is missing: %s" % path)

        tar_path = os.path.join(self.workdir, 'broot-%s.tar.gz' % buildrootID)
        self.logger.debug("Creating buildroot archive %s", tar_path)
        f = tarfile.open(tar_path, "w:gz")
        f.add(path, filter=omit_paths)
        f.close()

        self.logger.debug("Uploading %s to hub", tar_path)
        self.uploadFile(tar_path, volume=config['volume'])
        os.unlink(tar_path)
        self.logger.debug("Finished saving buildroot %s", buildrootID)
