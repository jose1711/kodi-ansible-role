#!/bin/sh
# find, download and enable Kodi addon if not already present,
# also requisites are pulled
#
# uses hardcoded repository list
#
# $1 = addon_id
# $2 = major kodi version

set -eu

usage() {
  printf 1>&2 -- 'Usage: %s <addon-id> <kodi-version>\n' "${0##*/}"
}

if [ "$#" -ne 2 ]
then
  usage
  exit 1
fi

target_addon_id="$1"
shift

kodi_version="$1"
shift

if command -v xmllint 1>/dev/null 2>&1
then
  addon_versions() {
    xmllint --xpath 'string(//addon[@id="'"${1?}"'"]/@version)' -
  }

  addon_datadirs() {
    xmllint --xpath '//datadir/text()'
  }

  addon_imports() {
    xmllint --xpath '//addon[@id="'"${1?}"'"]/requires/import/@addon' - 2>/dev/null | tr ' ' '\n' | awk -F= '{print $2}' | tr -d '"'
  }
elif command -v python 1>/dev/null 2>&1
then
  python_xpath() {
    python -c '
import os
import sys

import xml.etree.ElementTree as ET

root = ET.parse(sys.stdin)
if len(sys.argv) > 2:
    gettext = lambda e: e.attrib.get(sys.argv[2], '')
else:
    gettext = lambda e: e.text

for res in root.findall(sys.argv[1]):
    print(gettext(res))
' "$@"
  }

  addon_versions() {
    python_xpath './/addon[@id="'"${1?}"'"]' version
  }

  addon_datadirs() {
    python_xpath './/datadir'
  }

  addon_imports() {
    python_xpath './/addon[@id="'"${1?}"'"]/requires/import' addon
  }
else
  printf -- '%s: XML parsing prerequisites are missing (have neither xmllint nor python); cannot proceed.\n' "${0##*/}"
  exit 127
fi

addon_version() {
  addon_versions "$@" | sort -Vr | head -n 1
}

cache_repositories() {
  for repo_data in ${REPOSITORIES?}
  do
    name="${repo_data%=*}"
    url="${repo_data#*=}"

    data_path="${TMPDIR:-/tmp}/${name}.xml"

    # only download if the file is missing
    if [ -f "$data_path" ]
    then
      printf 1>&2 -- 'Already cached name: %s, url: %s\n' "$name" "$url"
      continue
    fi

    printf 1>&2 -- 'Caching name: %s, url: %s\n' "$name" "$url"

    fetch_path="${data_path}.out"

    curl -fsLS -o "$fetch_path" "$url" || {
      rc="$?"
      rm -f "$fetch_path"
      continue
    }

    {
      gunzip -c "$fetch_path" > "$data_path" || mv -f "$fetch_path" "$data_path"
    } || {
      rc="$?"
      rm -f "$fetch_path" "$data_path"
    }
  done

  return "${rc:-0}"
}

repo_data() {
  cat "${TMPDIR:-/tmp}/${1?}.xml"
}

repo_url() {
  for repo_data in ${REPOSITORIES?}
  do
    name=${repo_data%=*}
    url=${repo_data#*=}
    if [ "$name" = "${1?}" ]
    then
      dirname "$url"
      return
    fi
  done
}

path_for_zip_url() {
  printf -- '%s/%s' "${TMPDIR:-/tmp}" "$(printf -- '%s' "$1" | sed -e 's/[^[:alnum:]_.]/-/g')"
}

fetch_zip() {
  if ! curl -Lo "${2?}" "${1?}"
  then
    printf 1>&2 -- 'Unable to fetch "%s" from "%s"\n' "$2" "$1"
    return 1
  fi

  if ! unzip -lq "$2" >/dev/null 2>&1
  then
    printf 1>&2 -- '"%s" from "%s" does not look like a zip archive\n' "$2" "$1"
    rm -f "$2"
    return 1
  fi
}

resolve_addon() {
  addon_id="$1"
  shift

  # no need to resolve this core dependency
  if [ "${addon_id}" = xbmc.python ]
  then
    echo 0 - -
    return
  fi

  printf 1>&2 -- 'Resolving %s...\n' "$addon_id"

  if [ -d ~/.kodi/addons/"$addon_id" ]
  then
    printf 1>&2 -- 'Skipping - %s already installed\n' "$addon_id"
    echo 0 - -
    return
  fi

  # search addon_id in all enabled repositories
  for repo in ${ENABLED_REPOSITORIES?}
  do
    printf 1>&2 -- 'Checking for addon %s in %s...\n' "$addon_id" "$repo"

    if ! version="$(repo_data "$repo" | addon_version "$addon_id")" || [ -z "$version" ]
    then
      printf 1>&2 -- 'Unable to find addon %s in %s repository\n' "$addon_id" "$repo"
      continue
    fi

    datadir_count=0

    while read -r datadir
    do
      if [ -z "$datadir" ]
      then
        continue
      fi

      datadir_count="$(( datadir_count + 1 ))"

      url="${datadir}/${addon_id}/${addon_id}-${version}.zip"
      path="$(path_for_zip_url "$url")"

      if fetch_zip "$url" "$path"
      then
        echo "${version} ${addon_id} ${path}"
      fi
    done <<REPO_DATA
$(repo_data "$repo" | addon_datadirs 2>/dev/null)
REPO_DATA

    if [ "$datadir_count" -eq 0 ]
    then
      datadir="$(repo_url "$repo")"
      printf 1>&2 -- 'Unable to find datadir in %s repository data; using default datadir "%s"\n' "$repo" "$datadir"

      url="${datadir}/${addon_id}/${addon_id}-${version}.zip"
      path="$(path_for_zip_url "$url")"

      # output addon download info
      if fetch_zip "$url" "$path"
      then
        echo "${version} ${addon_id} ${path}"
      fi
    fi

    # search requisite addons in all repositories
    while read -r dependency
    do
      if [ -n "$dependency" ]
      then
        resolve_addon "$dependency" || return
      else
        printf 1>&2 -- 'Could not find addon %s in %s repository data\n' "$addon_id" "$repo"
      fi
    done <<REPO_DATA
$(repo_data "$repo" | addon_imports "$addon_id" 2>/dev/null)
REPO_DATA
  done
}

yield_addons() {
  resolve_addon "$@" | sort -Vrk 2,1 | awk '!a[$2]++{print $2,$3,1; exit} {print $2,$3,0}'
}

enable_addon() {
  enable_addon_usage() {
    printf 1>&2 -- 'Usage: enable_addon <addon-id> <kodi-version>\n'
  }

  if [ "$#" -ne 2 ]
  then
    enable_addon_usage
    return 1
  fi

  addon_id="$1"
  shift

  kodi_version="$1"
  shift

  if [ -z "$addon_id" ] || [ -z "$kodi_version" ]
  then
    printf 1>&2 -- 'Error: addon ID and Kodi version cannot be empty.\n'
    enable_addon_usage
    return 1
  fi

  for db in ~/.kodi/userdata/Database/Addons*.db
  do
    if [ -f "$db" ]
    then
      break
    else
      unset db
    fi
  done

  if [ -z "${db:-}" ]
  then
    case "$kodi_version" in
      16) db=~/.kodi/userdata/Database/Addons20.db
          ;;
      17|18|19) db=~/.kodi/userdata/Database/Addons27.db
          ;;
      20) db=~/.kodi/userdata/Database/Addons33.db
          ;;
      *)
        printf 1>&2 -- 'enable_addon: unsupported Kodi version: %s\n' "$kodi_version"
        return 1
          ;;
    esac
  fi

  # init empty db
  if ! [ -f "$db" ]
  then
    mkdir -p "${db%/*}"
    sqlite3 "$db" <<"HERE"
CREATE TABLE version (idVersion integer, iCompressCount integer);
CREATE TABLE repo (id integer primary key, addonID text,checksum text, lastcheck text, version text);
CREATE TABLE addonlinkrepo (idRepo integer, idAddon integer);
CREATE TABLE broken (id integer primary key, addonID text, reason text);
CREATE TABLE blacklist (id integer primary key, addonID text);
CREATE TABLE package (id integer primary key, addonID text, filename text, hash text);
CREATE TABLE installed (id INTEGER PRIMARY KEY, addonID TEXT UNIQUE, enabled BOOLEAN, installDate TEXT, lastUpdated TEXT, lastUsed TEXT, origin TEXT NOT NULL DEFAULT '');
CREATE TABLE addons (id INTEGER PRIMARY KEY,metadata BLOB,addonID TEXT NOT NULL,version TEXT NOT NULL,name TEXT NOT NULL,summary TEXT NOT NULL,description TEXT NOT NULL, news TEXT NOT NULL DEFAULT '');
CREATE INDEX idxAddons ON addons(addonID);
CREATE UNIQUE INDEX ix_addonlinkrepo_1 ON addonlinkrepo ( idAddon, idRepo )
;
CREATE UNIQUE INDEX ix_addonlinkrepo_2 ON addonlinkrepo ( idRepo, idAddon )
;
CREATE UNIQUE INDEX idxBroken ON broken(addonID);
CREATE UNIQUE INDEX idxBlack ON blacklist(addonID);
CREATE UNIQUE INDEX idxPackage ON package(filename);

INSERT INTO version (idVersion, iCompressCount) VALUES (27, 0);
HERE
  fi

  if ! sqlite3 "$db" 'SELECT * from installed where addonID="'"$addon_id"'"' | grep -Fq "$addon_id"
  then
    printf 1>&2 -- 'Adding %s to list of installed addons and enabling it...\n' "$addon_id"
    sqlite3 "$db" 'INSERT INTO installed (addonId, enabled, installDate) VALUES ("'"$addon_id"'", 1, "1970-01-01 00:00:01");'
  else
    printf 1>&2 -- 'Making sure %s is enabled...\n' "$addon_id"
    sqlite3 "$db" 'UPDATE installed SET enabled=1 WHERE addonId="'"$addon_id"'"'
  fi
}

cache_repositories

found_addons=0

while read -r addon_id path use
do
  # Not selected version of addon
  if [ "${use:-0}" != 1 ]
  then
    continue
  fi

  if [ "$addon_id" = "$target_addon_id" ] || [ "$path" = - ]
  then
    found_addons="$(( found_addons + 1 ))"
  fi

  # No addon found, or addon already installed
  if [ -z "$addon_id" ] || [ "$path" = - ]
  then
    continue
  fi

  unzip -q -d ~/.kodi/addons "$path"

  enable_addon "$addon_id" "$kodi_version"
done <<RESOLVE_ADDON
$(yield_addons "$target_addon_id")
RESOLVE_ADDON

if [ "$found_addons" -eq 0 ]
then
  printf 1>&2 -- 'No such addon (%s) found (or already installed)\n' "$target_addon_id"
  exit 1
fi
