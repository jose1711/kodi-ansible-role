kodi_ansible_role
=================

![CI Status](https://github.com/jose1711/kodi-ansible-role/actions/workflows/ci.yml/badge.svg?event=push)

Ansible role that installs and configures Kodi on:
 - ArchLinux
 - Debian and derivates
 - LibreElec
 - OSMC
 - Ubuntu

Intended use is for desktop/HTPC systems with many Kodi addons as one of the features
of this role is the ability to pull the latest addons (and their dependencies) from
configured Kodi repositories.

Configuration using `kodi_config` makes this role very flexible (thanks to most
configuration files being XML files with fixed structure).

Requirements
------------

You may put repository addon assets (`addon.xml`, etc.) into `{{ playbook_dir }}/files/addons/`.
This directory hierarchy will be copied to the target machine's Kodi addons directory (`{{ kodi_data_dir }}/addons`), and should mirror the addons directory's structure.

You may also put addon settings (`settings.xml`, etc.) into `{{ playbook_dir }}/files/addon_settings`.
This directory hierarchy will be copied to the target machine's addon settings directory (`{{ kodi_data_dir }}/userdata/addon_settings`), and should mirror the addon settings directory's structure.

For instance, given this `files` hierarchy on your Ansible control machine:

```
.
├── files
│   ├── addon_data
│   │   └── plugin.video.bazquux
│   │       └── settings.xml
│   └── addons
│       ├── plugin.video.bazquux
│       │   ├── addon.xml
│       │   ├── default.py
│       │   └── service.py
│       ├── repository.foo.bar
│       │   └── addon.xml
│       └── script.module.corgegrault
│           ├── addon.xml
│           └── lib
│               └── corgegrault
│                   └── __init__.py
└── kodi-playbook.yml
```

The target machine will end up with this (partial) addons and addon settings structure:

```
~mykodiuser/.kodi
├── addons
│   ├── plugin.video.bazquux
│   │   ├── addon.xml
│   │   ├── default.py
│   │   └── service.py
│   ├── repository.foo.bar
│   │   └── addon.xml
│   └── script.module.corgegrault
│       ├── addon.xml
│       └── lib
│           └── corgegrault
│               └── __init__.py
└── userdata
    └── addon_data
            └── plugin.video.bazquux
                        └── settings.xml
```

See ["Installing Addons"](#installing-addons) and ["Configuring Addon Settings"](#configuring-addon-settings) for alternate methods of installing and configuring addons.

Role Variables
--------------

[`vars/default.yml`]: vars/default.yml

- `kodi_user`: the user account used for running the Kodi service on the target machine.  Default: `"kodi"`.
- `kodi_groups`: if `kodi_user` is created by this role, it will be added to these groups.  Default: `["audio", "video", "input"]`.
- `kodi_shell`: if `kodi_user` is created by this role, it will use this value as its login shell.  Default: `"/bin/bash"`.
- `kodi_user_create`: whether to create the user account specified in `kodi_user`.  Default: `True` (except on LibreELEC and OSMC, where it is set to `False`).
- `kodi_data_dir`: path to the directory storing Kodi data (addons, user data, etc.). Default: `~{{ kodi_user }}/.kodi` (the `.kodi` subdirectory of the home directory of the `kodi_user` user).
- `kodi_master_installation`: the name of Ansible inventory host whose `favourites.xml` and RSS feeds will be made available for copying to other inventory hosts.  Default: `"master_install"`.
- `kodi_master_kodi_user`: the Kodi user on the `kodi_master_installation` host.  Default: the value of `kodi_user`.
- `kodi_master_data_dir`: path to the directory storing Kodi data (addons, user data, etc.) on the `kodi_master_installation` host. Default: `~{{ kodi_master_kodi_user }}/.kodi` (the `.kodi` subdirectory of the home directory of the `kodi_user` user).
- `kodi_copy_favourites`: copy `favourites.xml` from the `kodi_master_installation` host to the target host.  Default: `False`.
- `kodi_copy_feeds`: copy RSS feeds from the `kodi_master_installation` host to the target host.  Default: `False`.
- `kodi_repositories`: a list of strings of the form `<repository-name>=<repository-url>`, where `repository-name` is an arbitrary identifier and `repository-url` is the URL to a Kodi repository `addons.xml` file.  Default: `[]`.
- `kodi_enabled_repositories`: a list of repository name strings.  Each element should correspond to the `repository-name` part of the `<repository-name>=<repository-url>` entries in `kodi_repositories`.  Addons in this repository will be available for installation via specifying their names in `kodi_addons`.  Default: all repository names in `kodi_repositories`.
- `kodi_addons`: a list of addons to install (if necessary) and enable.  Each entry can be an addon name (e.g. `plugin.video.beepboop`) or an `<repository-addon-name>=<addon-url>` pair, `<repository-addon-name>` is the name of a repository addon (`repository.foo.bar`) and `<addon-url>` is the URL of the ZIP archive defining the addon.  In the latter case, the addon ZIP will be fetched and extracted to the named path under `{{ kodi_data_dir }}/addons`.  Default: `[]`.
- `kodi_config`: a list of dictionaries specifying configuration data for core Kodi and for addons (see [`vars/default.yml`][] for an example definition).  Default: `[]`.  Each entry must define the following attributes:
    - `file`: the path to the file (relative to `{{ kodi_data_dir }}`) that should contain this setting.
    - `key`: an XPath expression matching the target setting (a suitable XML node will be created if a matching node does not already exist).
    - `value`: the value of the setting.
    - `type`: the data type of the setting (for instance, `"string"` or `"bool"`).
- `kodi_setting_level`: an integer representing the setting level (Basic, Standard, Advanced, Expert).  Default: not defined.
- `kodi_webserver_enabled`: whether or not to enable the Kodi webserver.  Default: not defined.
- `kodi_webserver_port`: listening port for the Kodi webserver.  Default: not defined.
- `kodi_webserver_user`: user name for authenticating with the Kodi webserver.  Default: not defined.
- `kodi_webserver_password`: password for authenticating with the Kodi webserver.  Default: not defined.
- `kodi_language`: Default: not defined.
- `kodi_locale_country`: Default: not defined.
- `kodi_locale_timezone_country`: Default: not defined.
- `kodi_subtitles_languages`: Comma-separated list of subtitle languages.  Default: not defined.
- `kodi_weather_provider`: Hostname of the weather data provider.  Default: not defined.
- `kodi_include_default_config`: a boolean indicating whether or not to include the variable definitions from [`vars/default.yml`][].yml).  Default: `False`.
- `kodi_systemd_service`: the name of the systemd service running Kodi.  Default: not defined.  **This variable is deprecated**; please use `kodi_service` instead.
- `kodi_service`: the name of the service running Kodi.  Default: not defined, except on Alpine and LibreELEC where it is set to `kodi` and on OSMC where it is set to `mediacenter`.
- `kodi_check_process_cmd`: the command to use for checking whether Kodi is currently running (Kodi must be shut off before changing its configuration).  See [the platform-specific variables files](/vars) for the values of this variable.
- `kodi_check_process_executable`: the executable to use for running `kodi_check_process_cmd`.  See [the platform-specific variables files](/vars) for the values of this variable.
- `kodi_query_version_cmd`: the command to use for determining the version of Kodi in use.  This command only runs if `kodi_version` is undefined.  See [the platform-specific variables files](/vars) for the values of this variable.
- `kodi_query_version_executable`: the executable to use for running `kodi_query_version_cmd`.  See [the platform-specific variables files](/vars) for the values of this variable.
- `kodi_executable`: the name or path of the executable used for starting Kodi.  See [the platform-specific variables files](/vars) for the values of this variable; the lowest-precedence default is `kodi`.
- `kodi_send_executable`: the name or path of the `kodi-send` executable.  This role uses `kodi-send` for attempting to stop the Kodi daemon, and for triggering a Kodi refresh after updating Kodi repositories and addons.  Default: `kodi-send`.
- `kodi_send_host`: the host `kodi-send` should use for communicating with Kodi.  Default: `localhost`.
- `kodi_send_port`: the port `kodi-send` should use for communicating with Kodi.  Default: `9777`.
- `kodi_attempt_start`: whether to attempt to start Kodi (via `kodi_systemd_service`, if defined, or via `kodi_executable` if not) when it is not already running.  If this is `False` and this is a fresh Kodi installation (e.g. Kodi has never run on the target system), plugin installation may fail, as Kodi will not yet have performed required addon and repository initialization.  Default: `False`.
- `kodi_start_seconds`: number of seconds to wait before attempting to stop the Kodi process started when `kodi_attempt_start` is enabled.  Default: `10`.
- `kodi_attempt_stop`: whether to attempt to stop the Kodi if it is running.  If this is false, and Kodi is running, then this role will exit with an error. Only applies when `kodi_systemd_service` is not defined.  Default: the value of `kodi_attempt_start`.
- `kodi_stop_seconds`: number of seconds to wait before attempting to stop an active Kodi process when `kodi_attempt_stop` is enabled.  Default: `30`.
- `kodi_version`: the version of Kodi in use.  Default: determined by running `kodi_query_version_cmd`.

Installing Addons
-----------------

In addition to vendoring addons as described in [the requirements section](#requirements), you can also specify addons in the `kodi_addons` variable.
Plugins specified here will be installed from the repositories specified in `kodi_repositories`/`kodi_enabled_repositories`, or simply enabled if they are "core" plugins (e.g. `plugin.video.youtube`).
An error will be raised if a plugin is neither available in the enabled repositories nor a "core" plugin.

Configuring Addon Settings
--------------------------

There are two options for configuring addon settings:
  1. copy `addon_id/settings.xml` (from `.kodi/userdata/addon_data`) into `files/addon_data`, as described in [the requirements section](#requirements), or
  2. define selected configuration options and values via `kodi_config` variable (note that the `type` field is mandatory)

Option #2 is preferred when you don't want to have your configuration overwritten everytime the playbook is executed.

Please note that Kodi 18 changed the way how settings are stored in `guisettings.xml` (https://github.com/xbmc/xbmc/pull/12277). It is suggested you're using Kodi 18+ as the defaults are using this new settings format (version=2). Since last version of Kodi 17 was in 2017 it's probably a good idea to upgrade anyway.

Dependencies
------------

None

Example Playbook
----------------

```
- name: Kodi configuration
  hosts: myhtpc
  become: yes
  roles:
    - { role: jose1711.kodi_ansible_role, kodi_language: en_US }
```

License
-------

MIT
