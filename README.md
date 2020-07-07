kodi_ansible_role
=================

Ansible role that installs and configures Kodi on:
 - ArchLinux
 - LibreElec
 - Debian and derivates
 - Ubuntu

Intended use is for desktop/HTPC systems with many Kodi addons as one of the features
of this role is the ability to pull the latest addons (and their dependencies) from 
configured Kodi repositories.

Configuration using `kodi_config` makes this role very flexible (thanks to most
configuration files being XML files with fixed structure).

Requirements
------------

If you are executing on LibreElec host, make sure you copy repository addons
into `files/addons` first.

For all hosts: copy addon settings from `.kodi/userdata/addon_data/` into
`files/addon_data` (see below for alternate addon configuration).

Role Variables
--------------

Available variables with default values are listed below:

```
kodi_user: kodi
kodi_groups: [audio, video, input]
kodi_shell: /bin/bash

kodi_webserver_enabled: 'true'
kodi_webserver_port: 8080
kodi_webserver_user: kodi
kodi_webserver_password: strongpassword

kodi_addons:
  - plugin.video.joj.sk
  - plugin.video.ta3.com
  - plugin.video.tvba.sk
  - resource.language.sk_sk
  - service.xbmc.callbacks

kodi_repositories:
  - official_cached=https://ftp.fau.de/xbmc/addons/${codename}/addons.xml.gz
  - kodiczsk_cached=https://mirror.xbmc-kodi.cz/addons/addons.xml.gz
  - czsk_cached=http://kodi-czsk.github.io/repository/repo/addons.xml

kodi_enabled_repositories:
  - official_cached
  - kodiczsk_cached
  - czsk_cached

kodi_language: sk_sk
kodi_locale_country: Slovensko
kodi_locale_timezone_country: Slovakia
kodi_subtitles_languages: Slovak,Czech
kodi_weather_provider: weather.shmu.pocasie

kodi_config:
  - {file: 'userdata/guisettings.xml', key: "locale.language", value: "resource.language.{{ kodi_language }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "locale.country", value: "{{ kodi_locale_country }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "locale.timezonecountry", value: "{{ kodi_locale_timezone_country }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "subtitles.languages", value: "{{ kodi_subtitles_languages }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "weather.addon", value: "{{ kodi_weather_provider }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "addons.unknownsources", value: "true", type: "bool"}
  - {file: 'userdata/guisettings.xml', key: "services.webserver", value: "{{ kodi_webserver_enabled }}", type: "bool"}
  - {file: 'userdata/guisettings.xml', key: "services.webserverport", value: "{{ kodi_webserver_port }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "services.webserverusername", value: "{{ kodi_webserver_user }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "services.webserverpassword", value: "{{ kodi_webserver_password }}", type: "string"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoTVButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoRadioButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoFavButton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoWeatherButton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoMusicButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoVideosButton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoTVShowButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoProgramsButton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoPicturesButton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoMovieButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoMusicVideoButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunogamesbutton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "HomeMenuNoTVButton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunoradiobutton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunofavbutton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunoweatherbutton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunomusicbutton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunovideosbutton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunotvshowbutton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunoprogramsbutton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunopicturesbutton", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunomoviebutton", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "homemenunomusicvideobutton", value: "true", type: "bool"}

```

There are two options for configuring addon setting:
  1. copy `addon_id/settings.xml` (from `.kodi/userdata/addon_data`) into `files/addon_data`
  2. define selected configuration options and values via `kodi_config` variable (note that type is mandatory)

Option #2 is preferred when you don't want to have your configuration overwritten everytime
the playbook is executed.

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
