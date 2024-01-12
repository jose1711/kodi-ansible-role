#!/usr/bin/env python3

import abc
import argparse
import contextlib
import copy
import functools
import glob
import hashlib
import logging
import os
import pwd
import re
import shlex
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse
import xml.etree.ElementTree as ET

try:
    from packaging.version import Version as V
except ImportError:
    from distutils.version import LooseVersion

    @functools.total_ordering
    class V:
        def __init__(self, vstring):
            self.loose_version = vstring

        def __str__(self):
            return self.loose_version.vstring

        def _component(self, idx):
            try:
                return self.loose_version.version[idx]
            except (AttributeError, IndexError):
                return None

        @property
        def loose_version(self):
            return self._loose_version

        @loose_version.setter
        def loose_version(self, new_loose_version):
            self._loose_version = LooseVersion(new_loose_version)

        @property
        def major(self):
            return self._component(0)

        @property
        def minor(self):
            return self._component(1)

        @property
        def micro(self):
            return self._component(2)

        @property
        def release(self):
            return tuple(
                c for c in [self.major, self.minor, self.micro] if c is not None
            )

        def __lt__(self, other):
            return self._loose_version < other

        def __eq__(self, other):
            return self._loose_version == other


if sys.maxsize > 2**32:
    blake2 = hashlib.blake2b
else:
    blake2 = hashlib.blake2s


# Some distributions (looking at you, Debian...) put all sorts of junk in
# version strings.  Since (for the purposes of talking to addon repositories)
# we only need the dot-separated numeric part of the Kodi version string, try
# to yank that out of whatever melange `kodi --version` gave us.
def extract_kodi_version(vstring_plus):
    vstring_match = re.match("^([\d.]+\d)", vstring_plus)
    if vstring_match is None:
        raise TypeError("'{0}' does not contain a valid version string".format(vstring_plus))
    return V(vstring_match[0])


# `scara2` variant from https://giannitedesco.github.io/2020/12/14/a-faster-partition-function.html
def partition(predicate, iterable):
    satisfied = []
    unsatisfied = []
    satisfied_op = satisfied.append
    unsatisfied_op = unsatisfied.append
    for elt in iterable:
        (satisfied_op if predicate(elt) else unsatisfied_op)(elt)
    return satisfied, unsatisfied


def unzip(*args, **kwargs):
    return subprocess.run(["unzip", *args], **kwargs)


def unzip_to_dir(output, source, *args, **kwargs):
    with contextlib.suppress(FileExistsError):
        os.makedirs(output)
    return unzip("-qq", "-o", "-d", output, source, **kwargs)


def looks_like_zip(source, **kwargs):
    # Even with `-qq`, `unzip -l` writes an archive file listing to stdout.
    # Send it to the bit bucket.
    return unzip("-qq", "-l", source, stdout=subprocess.DEVNULL, **kwargs)


def curl(*args, **kwargs):
    return subprocess.run(["curl", *args], **kwargs)


def gunzip(*args, **kwargs):
    return subprocess.run(["gunzip", *args], **kwargs)


def gunzip_into(target, *args, **kwargs):
    # `delete_on_close` introduced in 3.12; don't rely on it.
    with tempfile.NamedTemporaryFile(dir=os.path.dirname(target), delete=False) as out:
        kwargs.update(stdout=out)
        try:
            gunzip("-c", *args, **kwargs).check_returncode()
            os.rename(out.name, target)
        except Exception as e:
            with contextlib.suppress(FileNotFoundError):
                os.remove(out.name)
            raise e

    return target


def kodi_send(*args, host="localhost", port=9777, **kwargs):
    return subprocess.run(
        ["kodi-send", *args, "--host={0}".format(host), "--port={0}".format(port)],
        **kwargs,
    )


# https://docs.python.org/3/library/shutil.html#rmtree-example
def rmtree(path):
    def remove_readonly(func, path, _):
        os.chmod(path, stat.S_IWRITE)
        func(path)

    return shutil.rmtree(path, onexc=remove_readonly)


class Propagatable:
    # Has to be here in order to satisfy the multiple-inheritance scheme
    def __init__(self, **kwargs):
        pass

    @classmethod
    def all_propagated_attributes(cls):
        attrs = set()
        for resolved in cls.mro():
            if hasattr(resolved, "__propagated_attributes__"):
                attrs.update(getattr(resolved, "__propagated_attributes__"))

        return attrs

    @classmethod
    def resolve_propagated_attributes(cls, other):
        return {
            attr: getattr(other, attr)
            for attr in cls.all_propagated_attributes()
            if hasattr(other, attr)
        }

    @classmethod
    def propagated(cls, f):
        class Propagated(type(f)):
            @property
            def __propagated__(self):
                return True

        return Propagated


class FilesystemMixin(Propagatable):
    __propagated_attributes__ = set(["data_dir", "cache_dir"])

    def __init__(self, data_dir=None, cache_dir=None, **kwargs):
        super().__init__(**kwargs)
        self.data_dir = data_dir
        self.cache_dir = cache_dir

    @property
    def data_dir(self):
        with contextlib.suppress(AttributeError):
            if self._data_dir is not None:
                return self._data_dir

        self._data_dir = os.path.join(pwd.getpwuid(os.geteuid()).pw_dir, ".kodi")
        return self._data_dir

    @data_dir.setter
    def data_dir(self, new_data_dir):
        if new_data_dir is not None:
            self._data_dir = os.path.expanduser(new_data_dir)

    @property
    def addons_dir(self):
        return os.path.join(self.data_dir, "addons")

    @property
    def packages_dir(self):
        return os.path.join(self.addons_dir, "packages")

    @property
    def cache_dir(self):
        with contextlib.suppress(AttributeError):
            if self._cache_dir is not None:
                return self._cache_dir

        self._cache_dir = os.path.join(self.packages_dir, "kodi-ansible-role")
        return self._cache_dir

    @cache_dir.setter
    def cache_dir(self, new_cache_dir):
        if new_cache_dir is not None:
            self._cache_dir = os.path.expanduser(new_cache_dir)


class KodiConfigMixin(Propagatable):
    KODI_USER_DEFAULT = "kodi"

    __propagated_attributes__ = set(
        ["kodi_version", "kodi_user", "kodi_send_host", "kodi_send_port"]
    )

    def __init__(
        self,
        kodi_version=None,
        kodi_user=None,
        kodi_send_host=None,
        kodi_send_port=None,
        **kwargs,
    ):
        super().__init__(**kwargs)
        self.kodi_version = kodi_version
        self.kodi_user = kodi_user
        self.kodi_send_host = kodi_send_host
        self.kodi_send_port = kodi_send_port

    @property
    def kodi_version(self):
        return self._kodi_version

    @kodi_version.setter
    def kodi_version(self, new_kodi_version):
        if new_kodi_version is not None:
            if isinstance(new_kodi_version, V):
                self._kodi_version = new_kodi_version
            else:
                self._kodi_version = extract_kodi_version(new_kodi_version)

    @property
    def kodi_user(self):
        with contextlib.suppress(AttributeError):
            if self._kodi_user is not None:
                return self._kodi_user

        try:
            self._kodi_user = pwd.getpwuid(os.geteuid()).pw_name
            return self._kodi_user
        except Exception:
            self._kodi_user = self.KODI_USER_DEFAULT
            return self._kodi_user

    @kodi_user.setter
    def kodi_user(self, new_kodi_user):
        if new_kodi_user is not None:
            self._kodi_user = new_kodi_user

    @property
    def kodi_send_host(self):
        return self._kodi_send_host

    @kodi_send_host.setter
    def kodi_send_host(self, new_kodi_send_host):
        self._kodi_send_host = new_kodi_send_host

    @property
    def kodi_send_port(self):
        return self._kodi_send_port

    @kodi_send_port.setter
    def kodi_send_port(self, new_kodi_send_port):
        self._kodi_send_port = new_kodi_send_port


class PackageMixin(FilesystemMixin, KodiConfigMixin, abc.ABC):
    def __init__(self, url=None, **kwargs):
        super().__init__(**kwargs)
        self.url = url

    @abc.abstractmethod
    def extract(self):
        pass

    @property
    def cache_file(self):
        with contextlib.suppress(AttributeError):
            if self._cache_file is not None:
                return self._cache_file

        self._cache_file = self.fetch()
        return self._cache_file

    @property
    def url(self):
        return self._url

    @url.setter
    def url(self, new_url):
        self._url = new_url

    @property
    def user_agent(self):
        return "Kodi/{0}".format(self.kodi_version)

    # Output to a file that contains a hash of, among other things, the addon
    # or repository URL, plus other argument to `curl`.
    def curl_into_cmd(self, url, destdir, *args):
        full = [*args, "--user-agent", self.user_agent, url]

        h = blake2()
        for arg in full:
            h.update(arg.encode())

        basename = url.rsplit("/", 1)[-1]
        ext = os.path.splitext(basename)[-1]
        output = os.path.join(destdir, "{0}{1}".format(h.hexdigest(), ext))

        return (output, full + ["-o", output])

    def get(self):
        logging.info(
            "Fetching '{0}' into directory '{1}'".format(self.url, self.cache_dir)
        )

        target, cmd = self.curl_into_cmd(
            self.url,
            self.cache_dir,
            "-f",
            "-s",
            "-L",
            "-S",
            "--retry",
            "5",
            "--retry-all-errors",
        )

        try:
            mtime = os.path.getmtime(target)
        except Exception:
            mtime = 0

        # Redownload if older than an hour
        if not os.path.isfile(target) or ((time.time() - mtime) > 3600):
            with contextlib.suppress(Exception):
                rmtree(target)
            curl(*cmd).check_returncode()

        assert os.path.isfile(
            target
        ), "command '{0}' failed to produce file '{1}'".format(shlex.join(cmd), target)

        return target

    def fetch(self):
        with contextlib.suppress(FileExistsError):
            os.makedirs(self.cache_dir)

        target = self.get()

        return self.extract(target)


class DocumentMixin(abc.ABC):
    def __init__(self, data=None, **kwargs):
        super().__init__(**kwargs)
        self.data = data

    @property
    @abc.abstractmethod
    def file(self):
        pass

    @property
    def data(self):
        with contextlib.suppress(AttributeError):
            if self._data is not None:
                return self._data

        self.data = self.file
        return self._data

    @data.setter
    def data(self, new_data):
        if new_data is not None:
            self._data = ET.parse(new_data)

    @property
    def root(self):
        return self.data.getroot()

    def findall(self, selector):
        return self.root.findall(selector)

    def matching_text(self, selector):
        for result in self.findall(selector):
            yield result.text

    def matching_attribute(self, selector, attrib):
        for result in self.findall(selector):
            yield result.attrib.get(attrib, "")


class SpecifierMixin(abc.ABC):
    @classmethod
    def parse(cls, thing, **kwargs):
        if isinstance(thing, cls):
            if kwargs == {}:
                return thing
            else:
                clone = copy.deepcopy(thing)
                for attr, value in kwargs.items():
                    # TODO does this effectively call `obj.${attr} = value`?
                    setattr(clone, attr, value)
                return clone
        elif isinstance(thing, str):
            parsed_args, parsed_kwargs = cls.str2args(thing)
            kwargs.update(parsed_kwargs)
            return cls(*parsed_args, **kwargs)
        else:
            raise TypeError(
                "argument must be an instance of {0} or str".format(cls.__name__)
            )

    @classmethod
    @abc.abstractmethod
    def str2args(cls, s):
        pass


class Addon(PackageMixin, DocumentMixin, SpecifierMixin):
    def __init__(self, id, version=None, **kwargs):
        super().__init__(**kwargs)
        self.id = id
        self.version = version

    @classmethod
    def str2args(cls, s):
        try:
            id, url = s.split("=", 1)
        except ValueError:
            id = s
            url = None
        return ([id], {"url": url})

    @property
    def id(self):
        return self._id

    @id.setter
    def id(self, new_id):
        self._id = new_id

    @property
    def version(self):
        with contextlib.suppress(AttributeError):
            return self._version

    @version.setter
    def version(self, new_version):
        if new_version is not None:
            self._version = V(new_version)

    def imports(self):
        return self.findall(".//requires/import")

    @property
    def baseurl(self):
        with contextlib.suppress(AttributeError):
            return self._baseurl

    @baseurl.setter
    def baseurl(self, new_baseurl):
        self._baseurl = new_baseurl

    @property
    def url(self):
        with contextlib.suppress(AttributeError):
            if self._url is not None:
                return self._url

        if self.baseurl is None:
            logging.warning(
                "No base URL for '{0}'; cannot infer full addon package URL".format(
                    self.id
                )
            )
            return None

        if self.version is None:
            basename = self.id
        else:
            basename = "{0}-{1}".format(self.id, self.version)

        self._url = urllib.parse.urljoin(
            "{0}/".format(self.baseurl), "{0}/{1}.zip".format(self.id, basename)
        )

        return self._url

    @url.setter
    def url(self, new_url):
        self._url = new_url

    @property
    def dir(self):
        return os.path.join(self.addons_dir, self.id)

    @property
    def file(self):
        return os.path.join(self.dir, "addon.xml")

    def installed(self):
        return os.path.isdir(self.dir) and os.path.isfile(self.file)

    def each_dependency(self, **kwargs):
        all_kwargs = self.resolve_propagated_attributes(self)
        all_kwargs.update(kwargs)
        for dependency in self.imports():
            yield Addon(
                dependency.attrib["addon"],
                version=dependency.attrib.get("version", None),
                **all_kwargs,
            )

    def extract(self, source):
        logging.info("Checking that '{0}' is a zip file".format(source))
        looks_like_zip(source).check_returncode()

        logging.info(
            "Unzipping '{0}' into the parent of '{1}'".format(source, self.dir)
        )
        unzip_to_dir(os.path.dirname(self.dir), source)

        assert (
            self.installed()
        ), "Addon '{0}' is not installed to '{1}' after extracting '{2}'".format(
            self.id, self.dir, source
        )

        return source


class Repository(PackageMixin, DocumentMixin, SpecifierMixin):
    def __init__(self, name, **kwargs):
        super().__init__(**kwargs)
        self.name = name

    @classmethod
    def str2args(cls, s):
        try:
            name, url = s.split("=", 1)
        except ValueError:
            name = s
            url = None
        return ([name], {"url": url})

    @property
    def name(self):
        return self._name

    @name.setter
    def name(self, new_name):
        self._name = new_name

    @property
    def url(self):
        return self._url

    @url.setter
    def url(self, new_url):
        self._url = new_url

    @property
    def file(self):
        return self.cache_file

    def extract(self, source):
        with contextlib.suppress(subprocess.CalledProcessError):
            noext, ext = os.path.splitext(source)
            output = (source if ext == "" else noext) + os.path.extsep + "xml"
            return gunzip_into(output, source)

        return source

    def addons_for_id(self, addon_id):
        return self.findall(".//addon[@id='{0}']".format(addon_id))

    def addon_for_id(self, addon_id):
        def _addon_version(elt):
            return V(elt.attrib.get("version", "0.0.0"))

        with contextlib.suppress(IndexError):
            return sorted(
                self.addons_for_id(addon_id), key=_addon_version, reverse=True
            )[0]

    def addon_imports(self, addon_id):
        return self.matching_attribute(
            ".//addon[@id='{0}']/requires/import".format(addon_id), "addon"
        )

    def each_datadir(self):
        for datadir in self.matching_text(".//datadir"):
            yield datadir

        # Try parent directory of repository URL.
        url = urllib.parse.urlsplit(self.url)
        datadir = url._replace(path=url.path.rsplit("/", 1)[0])

        logging.info(
            "Trying default datadir '{0}' for repository '{1}'".format(
                datadir.geturl(), self.name
            )
        )

        yield datadir.geturl()


class Database:
    def __init__(self, path):
        self.path = path

    @property
    def path(self):
        return self._path

    @path.setter
    def path(self, new_path):
        self._path = new_path

    def connect(self):
        with contextlib.suppress(FileExistsError):
            os.makedirs(os.path.dirname(self.path))
        return sqlite3.connect(self.path)

    @property
    def connection(self):
        try:
            return self._connection
        except AttributeError:
            self._connection = self.connect()
            return self._connection

    @property
    def cursor(self):
        try:
            return self._cursor
        except AttributeError:
            self._cursor = self.connection.cursor()
            return self._cursor

    def populate(self, database_version):
        self.cursor.executescript(
            """
            BEGIN;

            CREATE TABLE IF NOT EXISTS version (idVersion integer, iCompressCount integer);
            CREATE TABLE IF NOT EXISTS repo (id integer primary key, addonID text,checksum text, lastcheck text, version text);
            CREATE TABLE IF NOT EXISTS addonlinkrepo (idRepo integer, idAddon integer);
            CREATE TABLE IF NOT EXISTS broken (id integer primary key, addonID text, reason text);
            CREATE TABLE IF NOT EXISTS blacklist (id integer primary key, addonID text);
            CREATE TABLE IF NOT EXISTS package (id integer primary key, addonID text, filename text, hash text);
            CREATE TABLE IF NOT EXISTS installed (id INTEGER PRIMARY KEY, addonID TEXT UNIQUE, enabled BOOLEAN, installDate TEXT, lastUpdated TEXT, lastUsed TEXT, origin TEXT NOT NULL DEFAULT ''); CREATE TABLE IF NOT EXISTS addons (id INTEGER PRIMARY KEY,metadata BLOB,addonID TEXT NOT NULL,version TEXT NOT NULL,name TEXT NOT NULL,summary TEXT NOT NULL,description TEXT NOT NULL, news TEXT NOT NULL DEFAULT '');

            CREATE INDEX IF NOT EXISTS idxAddons ON addons(addonID);

            CREATE UNIQUE INDEX IF NOT EXISTS ix_addonlinkrepo_1 ON addonlinkrepo ( idAddon, idRepo );
            CREATE UNIQUE INDEX IF NOT EXISTS ix_addonlinkrepo_2 ON addonlinkrepo ( idRepo, idAddon );
            CREATE UNIQUE INDEX IF NOT EXISTS idxBroken ON broken(addonID);
            CREATE UNIQUE INDEX IF NOT EXISTS idxBlack ON blacklist(addonID);
            CREATE UNIQUE INDEX IF NOT EXISTS idxPackage ON package(filename);

            COMMIT;
        """
        )

        try:
            self.cursor.execute("BEGIN TRANSACTION")
            self.cursor.execute(
                """
                INSERT INTO version (idVersion, iCompressCount) SELECT ?, 0 WHERE (SELECT COUNT(*) FROM version) = 0
                """,
                (database_version,),
            )
            self.cursor.execute("UPDATE version SET idVersion = 33")
            self.connection.commit()
        except sqlite3.Error as e:
            self.connection.rollback()
            raise (e)

    def upsert_installed(self, addon):
        self.cursor.execute(
            """
            INSERT INTO installed (addonID, enabled, installDate)
                VALUES (?, 1, datetime(0, "unixepoch"))
                ON CONFLICT(addonID) DO UPDATE SET enabled=1
            """,
            (addon.id,),
        )

        self.connection.commit()

    def update_installed(self, addon):
        self.cursor.execute(
            """
            UPDATE installed
                SET enabled=1
                WHERE addonID = ?
            """,
            (addon.id,),
        )

        self.connection.commit()

    def addon_installed(self, addon):
        res = self.cursor.execute(
            """
            SELECT 1 FROM installed WHERE addonID = ?
            """,
            (addon.id,),
        )

        return res.fetchone() is not None

    def addon_enabled(self, addon):
        res = self.cursor.execute(
            """
            SELECT 1 FROM installed WHERE addonID = ? AND enabled = 1
            """,
            (addon.id,),
        )

        return res.fetchone() is not None


class Manager(FilesystemMixin, KodiConfigMixin):
    KODI_CORE_ADDONS = set(("xbmc.addon", "xbmc.python"))

    def __init__(
        self,
        repositories=[],
        enabled_repositories=[],
        addons=[],
        **kwargs,
    ):
        super().__init__(**kwargs)
        self.repositories = repositories
        self.enabled_repositories = enabled_repositories
        self.addons = addons

    @property
    def addons(self):
        if self._addons is None:
            self._addons = []

        return self._addons

    def parse_addon(self, new_addon, **kwargs):
        all_kwargs = Addon.resolve_propagated_attributes(self)
        all_kwargs.update(kwargs)
        return Addon.parse(new_addon, **all_kwargs)

    @addons.setter
    def addons(self, new_addons):
        self._addons = [self.parse_addon(new_addon) for new_addon in new_addons]

    @property
    def repositories(self):
        try:
            return self._repositories
        except AttributeError:
            self._repositories = {}
            return self._repositories

    def parse_repository(self, new_repository, **kwargs):
        all_kwargs = Repository.resolve_propagated_attributes(self)
        all_kwargs.update(kwargs)

        return Repository.parse(
            new_repository,
            **all_kwargs,
        )

    @repositories.setter
    def repositories(self, new_repositories):
        repos = {}

        for new_repository in new_repositories:
            repo = self.parse_repository(new_repository)
            repos[repo.name] = repo

        self._repositories = repos

    @property
    def enabled_repositories(self):
        if self._enabled_repositories is None:
            self._enabled_repositories = []

        return self._enabled_repositories

    @enabled_repositories.setter
    def enabled_repositories(self, new_enabled_repositories):
        self._enabled_repositories = list(new_enabled_repositories)

    @property
    def addon_database(self):
        return self._addon_database

    def database_candidates(self):
        for database in glob.glob(
            os.path.join(self.data_dir, "userdata/Database/Addons*.db")
        ):
            yield database

    def database_default(self):
        return os.path.join(
            self.data_dir,
            "userdata/Database/Addons{0}.db".format(self.database_version),
        )

    @property
    def database_version(self):
        try:
            return self._database_version
        except AttributeError:
            database_version_map = {
                16: "20",
                17: "27",
                18: "27",
                19: "33",
                20: "33",
            }

            if self.kodi_version.major not in database_version_map:
                raise Exception(
                    "unsupported Kodi version: {0}".format(self.kodi_version.major)
                )

            self._database_version = database_version_map[self.kodi_version.major]

            return self._database_version

    @property
    def database(self):
        try:
            return self._database
        except AttributeError:
            for database in self.database_candidates():
                if os.path.exists(database):
                    self._database = database
                    return self._database

            self._database = self.database_default()
            return self._database

    @property
    def handle(self):
        try:
            return self._handle
        except AttributeError:
            logging.info("Opening database at '{0}'".format(self.database))
            self._handle = Database(self.database)
            return self._handle

    def each_repository(self):
        for name in self.enabled_repositories:
            if name in self.repositories:
                yield self.repositories[name]

    def each_addon_candidate(self, addon):
        if addon.url is not None:
            logging.info(
                "Using provided URL '{0}' for addon '{1}'".format(addon.url, addon.id)
            )
            yield None, addon
        else:
            for repository in self.each_repository():
                logging.info(
                    "Searching for '{0}' in '{1}'".format(addon.id, repository.name)
                )
                match = repository.addon_for_id(addon.id)
                if match is not None:
                    logging.info(
                        "Found match for '{0}' in '{1}'".format(
                            addon.id, repository.name
                        )
                    )
                    for datadir in repository.each_datadir():
                        candidate = copy.deepcopy(addon)
                        candidate.version = match.attrib["version"]
                        candidate.baseurl = datadir
                        yield repository, candidate
                else:
                    logging.info(
                        "No match for '{0}' in '{1}'".format(addon.id, repository.name)
                    )

    def addon_is_core(self, addon):
        return addon.id in self.KODI_CORE_ADDONS

    def install_addon(self, addon, seen={}):
        # Might get a plain old string
        addon = self.parse_addon(addon)

        if addon.id in seen:
            logging.info("Already handled addon '{0}'".format(addon.id))
            return

        logging.info("Handling addon '{0}'".format(addon.id))

        seen[addon.id] = True

        if self.addon_is_core(addon):
            logging.info("Skipping core addon '{0}'".format(addon.id))
            return
        else:
            logging.info("'{0}' is not a core addon".format(addon.id))

        for repository, candidate in self.each_addon_candidate(addon):
            try:
                if self.handle.addon_installed(candidate) and False:
                    if not candidate.installed():
                        logging.warning(
                            "'{0}' is marked as installed, but addon directory is absent".format(
                                candidate.id
                            )
                        )

                logging.info(
                    "Installing '{0}' from '{1}' into '{2}'".format(
                        candidate.id, candidate.url, candidate.dir
                    )
                )
                candidate.fetch()
                logging.info(
                    "Installed '{0}' from '{1}' into '{2}'".format(
                        candidate.id, candidate.url, candidate.dir
                    )
                )

                if repository is not None:
                    logging.info(
                        "Installing dependencies for '{0}' as specified in repository '{1}' file '{2}'".format(
                            candidate.id, repository.name, repository.file
                        )
                    )
                    for dependency in repository.addon_imports(candidate.id):
                        self.install_addon(dependency, seen=seen)

                logging.info(
                    "Installing dependencies for '{0}' as specified in file '{1}'".format(
                        candidate.id, candidate.file
                    )
                )
                for dependency in candidate.each_dependency():
                    self.install_addon(dependency, seen=seen)

                logging.info(
                    "Marking '{0}' as installed in '{1}'".format(
                        candidate.id, self.database
                    )
                )
                self.handle.upsert_installed(candidate)

                # Escape the outer `else` clause.
                break
            except Exception as e:
                logging.warning(
                    "Failed to install '{0}' from '{1}': '{2}'".format(
                        candidate.id, candidate.url, str(e)
                    )
                )
                logging.warning("Trying next candidate")
        else:
            if self.handle.addon_enabled(addon):
                logging.warning(
                    "Could not download and install '{0}', but it appears to be enabled already".format(
                        addon.id
                    )
                )
            else:
                raise Exception("Failed to install '{0}'".format(addon.id))

    def install(self):
        self.handle.populate(self.database_version)

        seen = {}
        failed = {}

        # Install repository addons first to make running the
        # `UpdateAddonRepos` feature work properly.
        repos, other = partition(
            lambda addon: addon.id.startswith("repository."), self.addons
        )

        def _install_addon(addon):
            try:
                self.install_addon(addon, seen=seen)
            except Exception as e:
                failed[addon.id] = e

        for addon in repos:
            _install_addon(addon)

        # Let this fail; Kodi might not be running or might not have the
        # webserver enabled.
        try:
            kodi_send("--action=UpdateAddonRepos", "--action=UpdateLocalAddons")
        except Exception as e:
            logging.warning(
                "Error updating addon repos with 'kodi-send': {0}".format(e)
            )

        for addon in other:
            _install_addon(addon)

        try:
            kodi_send("--action=UpdateLocalAddons")
        except Exception as e:
            logging.warning(
                "Error updating local addons with 'kodi-send': {0}".format(e)
            )

        if failed != {}:
            msg = "Failed to install the following addon(s): {0}".format(
                ", ".join(
                    [
                        "{0} ({1})".format(addon_id, str(e))
                        for addon_id, e in failed.items()
                    ]
                )
            )

            missing_core = [
                addon
                for addon in self.KODI_CORE_ADDONS
                if not self.handle.addon_installed(self.parse_addon(addon))
            ]

            if missing_core != []:
                msg += " -- missing core addon(s) {0}; you may need to start and stop Kodi before attempting to install addons".format(
                    ", ".join(missing_core)
                )

            raise Exception(msg)

    def clean(self):
        rmtree(self.cache_dir)

    def __repr__(self):
        return "<{0}.Manager data_dir={1} kodi_user={2} kodi_version={3}>".format(
            self.__module__, self.data_dir, self.kodi_user, self.kodi_version
        )


class CLI:
    def __init__(self):
        self.parser = argparse.ArgumentParser(
            description="Download and enable a Kodi addon and its dependencies"
        )
        self.parser.add_argument(
            "-c",
            "--cache-dir",
            help="The directory where this script stores downloaded repository and addon data",
        )
        self.parser.add_argument(
            "-d",
            "--data-dir",
            help="The directory where Kodi data is stored",
        )
        self.parser.add_argument(
            "-u",
            "--kodi-user",
            help="The name of the user used for running Kodi",
        )
        self.parser.add_argument(
            "-V",
            "--kodi-version",
            help="The version of the targeted Kodi instance",
            required=True,
        )
        self.parser.add_argument(
            "-H",
            "--kodi-send-host",
            help="The host for `kodi-send` to use",
            default=os.environ.get("KODI_SEND_HOST", "localhost"),
        )
        self.parser.add_argument(
            "-P",
            "--kodi-send-port",
            type=int,
            help="The port for `kodi-send` to use",
            default=os.environ.get("KODI_SEND_PORT", "9777"),
        )
        self.parser.add_argument(
            "-r",
            "--repository",
            dest="repositories",
            help="A repository name and XML data URL",
            action="append",
            default=shlex.split(os.environ.get("REPOSITORIES", "")),
        )
        self.parser.add_argument(
            "-e",
            "--enable",
            dest="enabled_repositories",
            help="Enable the named repository",
            action="append",
            default=shlex.split(os.environ.get("ENABLED_REPOSITORIES", "")),
        )

        subparsers = self.parser.add_subparsers(
            title="subcommands", description="modes of operation"
        )

        install = subparsers.add_parser("install", help="Install a Kodi addon")
        install.add_argument(
            "addons",
            help="Addons to install",
            nargs="+",
        )
        install.set_defaults(func=self.install)

        clean = subparsers.add_parser(
            "clean", help="Clean up cached Kodi addon and repository data"
        )
        clean.set_defaults(func=self.clean)

        self.parser.set_defaults(func=self.install)

    def manager_from(self, args):
        return Manager(**vars(args))

    def run(self, args):
        parsed = self.parser.parse_args(args)
        parsed.func(parsed)

    def install(self, args):
        manager = self.manager_from(args)
        manager.install()

    def clean(self, args):
        manager = self.manager_from(args)
        manager.clean()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    CLI().run(sys.argv[1:])
