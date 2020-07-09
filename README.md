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

kodi_webserver_enabled: 'false'
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

# whether to copy favourites.xml and rss from a dedicated host
kodi_copy_favourites: False
kodi_copy_feeds: False
kodi_master_installation: master_install
kodi_master_kodi_user: kodi_user

kodi_config:
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"locale.language\"]", value: "resource.language.{{ kodi_language }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"locale.country\"]", value: "{{ kodi_locale_country }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"locale.timezonecountry\"]", value: "{{ kodi_locale_timezone_country }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"subtitles.languages\"]", value: "{{ kodi_subtitles_languages }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"weather.addon\"]", value: "{{ kodi_weather_provider }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"addons.unknownsources\"]", value: "true", type: "bool"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"services.webserver\"]", value: "{{ kodi_webserver_enabled }}", type: "bool"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"services.webserverport\"]", value: "{{ kodi_webserver_port }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"services.webserverusername\"]", value: "{{ kodi_webserver_user }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "setting[@id=\"services.webserverpassword\"]", value: "{{ kodi_webserver_password }}", type: "string"}
  - {file: 'userdata/guisettings.xml', key: "general/settinglevel", value: "3", type: "string"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoTVButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoRadioButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoFavButton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoWeatherButton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoMusicButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoVideosButton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoTVShowButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoProgramsButton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoPicturesButton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoMovieButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoMusicVideoButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunogamesbutton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"HomeMenuNoTVButton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunoradiobutton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunofavbutton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunoweatherbutton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunomusicbutton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunovideosbutton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunotvshowbutton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunoprogramsbutton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunopicturesbutton\"]", value: "false", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunomoviebutton\"]", value: "true", type: "bool"}
  - {file: 'userdata/addon_data/skin.estuary/settings.xml', key: "setting[@id=\"homemenunomusicvideobutton\"]", value: "true", type: "bool"}


```

There are two options for configuring addon setting:
  1. copy `addon_id/settings.xml` (from `.kodi/userdata/addon_data`) into `files/addon_data`
  2. define selected configuration options and values via `kodi_config` variable (note that type is mandatory)

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
