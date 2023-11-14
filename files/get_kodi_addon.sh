#!/bin/sh
# find, download and enable Kodi addon if not already present,
# also requisites are pulled
#
# uses hardcoded repository list
#
# $1 = addon_id
# $2 = major kodi version

usage() {
  printf 1>&2 -- 'Usage: %s <addon-id> <kodi-version>\n' "${0##*/}"
}

_curl() {
  # Identify ourselves as Kodi.  Stuff may break if we do not.  See, e.g.,
  # https://github.com/jellyfin/jellyfin-kodi/issues/736.
  curl --user-agent "Kodi${kodi_version:+/${kodi_version}}" "$@"
}

if command -v homeof 1>/dev/null 2>&1; then
  home_of_user() {
    homeof "${1?}"
  }
elif command -v getent 1>/dev/null 2>&1; then
  home_of_user() {
    pwent="$(getend passwd "${1?}")" || return

    IFS=: read -r _ _ _ _ _ home _ <<PWENT
${pwent}
PWENT

    printf -- '%s' "$home"
  }
elif python_interpreter="$(command -v "${ANSIBLE_PYTHON_INTERPRETER:-python}" 2>/dev/null)"; then
  home_of_user() {
    "${python_interpreter:-python}" -c '
import pwd
import sys

sys.stdout.write(pwd.getpwuid(sys.argv[1]).pw_dir)
' "${1?}"
  }
fi

if python_interpreter="${python_interpreter:-$(command -v "${ANSIBLE_PYTHON_INTERPRETER:-python}" 2>/dev/null)}"; then
  expand_user() {
    "${python_interpreter:-python}" -c '
import os.path
import sys

sys.stdout.write(os.path.expanduser(sys.argv[1]))
' "${1?}"
  }
else
  # XXX unsafe!
  expand_user() {
    /bin/sh -c "printf -- '%s' ${1?}"
  }
fi

if command -v xmllint 1>/dev/null 2>&1; then
  xmllint_filter_attr_values() {
    while read -r attrdef; do
      attrval="${attrdef#*"${1?}=\""}"
      printf -- '%s\n' "${attrval%'"'}"
    done
  }

  xmllint_filter_addon() {
    xmllint_filter_attr_values addon
  }

  addon_versions() {
    xmllint --xpath 'string(//addon[@id="'"${1?}"'"]/@version)' -
  }

  addon_datadirs() {
    xmllint --xpath '//datadir/text()'
  }

  addon_imports() {
    xmllint --xpath '//addon[@id="'"${1?}"'"]/requires/import/@addon' - 2>/dev/null | xmllint_filter_addon
  }

  addon_imports_singleton() {
    xmllint --xpath '//requires/import/@addon' - 2>/dev/null | xmllint_filter_addon
  }
elif command -v xmlstarlet 1>/dev/null 2>&1; then
  xmlstarlet_select_value() {
    # -T == "text (not XML)"
    # -t == "template"
    # -v == "value (not element, etc.)"
    xmlstarlet sel -T -t -v "$@"
  }

  addon_versions() {
    xmlstarlet_select_value 'string(//addon[@id="'"${1?}"'"]/@version)'
  }

  addon_datadirs() {
    xmlstarlet_select_value '//datadir/text()'
  }

  addon_imports() {
    xmlstarlet_select_value '//addon[@id="'"${1?}"'"]/requires/import/@addon' 2>/dev/null
  }

  addon_imports_singleton() {
    xmlstarlet_select_value '//requires/import/@addon' 2>/dev/null
  }
elif python_interpreter="${python_interpreter:-$(command -v "${ANSIBLE_PYTHON_INTERPRETER:-python}" 2>/dev/null)}"; then
  python_xpath() {
    "${python_interpreter:-python}" -c '
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

  addon_imports_singleton() {
    python_xpath './/requires/import' addon
  }
else
  printf -- '%s: XML parsing prerequisites are missing (xmllint, xmlstarlet, and python are all unavailable); cannot proceed.\n' "${0##*/}"
  exit 127
fi

addon_data() {
  cat "${KODI_DATA_DIR?}/addons/${1?}/addon.xml"
}

addon_installed() {
  [ -d "${KODI_DATA_DIR?}/addons/${1?}" ]
}

addon_version() {
  addon_versions "$@" | sort -Vr | head -n 1
}

cache_repositories() {
  for repo_data in ${REPOSITORIES?}; do
    name="${repo_data%=*}"
    url="${repo_data#*=}"

    data_path="${TMPDIR:-/tmp}/${name}.xml"

    # only download if the file is missing
    if [ -f "$data_path" ]; then
      printf 1>&2 -- 'Already cached name: %s, url: %s\n' "$name" "$url"
      continue
    fi

    printf 1>&2 -- 'Caching name: %s, url: %s\n' "$name" "$url"

    fetch_path="${data_path}.out"

    _curl -fsLS -o "$fetch_path" "$url" || {
      rc="$?"
      rm -f "$fetch_path"
      continue
    }

    {
      gunzip -c "$fetch_path" >"$data_path"  || mv -f "$fetch_path" "$data_path"
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
  for repo_data in ${REPOSITORIES?}; do
    name=${repo_data%=*}
    url=${repo_data#*=}
    if [ "$name" = "${1?}" ]; then
      dirname "$url"
      return
    fi
  done
}

path_for_zip_url() {
  printf -- '%s/%s' "${TMPDIR:-/tmp}" "$(printf -- '%s' "$1" | sed -e 's/[^[:alnum:]_.]/-/g')"
}

fetch_zip() {
  if ! _curl -Lo "${2?}" "${1?}"; then
    printf 1>&2 -- 'Unable to fetch "%s" from "%s"\n' "$2" "$1"
    return 1
  fi

  if ! unzip -lq "$2" >/dev/null 2>&1; then
    printf 1>&2 -- '"%s" from "%s" does not look like a zip archive\n' "$2" "$1"
    rm -f "$2"
    return 1
  fi
}

install_zip() {
  unzip -q -o -d "${KODI_DATA_DIR?}/addons" "${1?}"
}

resolve_addon() {
  addon_id="${1?}"
  shift

  case "$addon_id" in
    '')
      echo 1>&2 'Error: "" is not a valid addon ID'
      return 1
      ;;
    *=*)
      url="${addon_id#*=}"
      addon_id="${addon_id%%=*}"
      ;;
  esac

  # no need to resolve this core dependency
  if [ "${addon_id}" = xbmc.python ]; then
    echo 0 - -
    return
  fi

  printf 1>&2 -- 'Resolving %s...\n' "$addon_id"

  search_addon() { :;  }

  if addon_installed "$addon_id"; then
    printf 1>&2 -- 'Skipping - %s already installed\n' "$addon_id"
    echo 0 - -
  elif [ -n "${url:-}" ]; then
    printf 1>&2 -- 'Fetching addon %s from %s...\n' "$addon_id" "$url"

    path="$(path_for_zip_url "$url")"

    # output addon download info
    if fetch_zip "$url" "$path" && install_zip "$path" && enable_addon "$addon_id" "$kodi_version"; then
      echo "0 ${addon_id} -"
    fi
  else
    search_addon() {
      repo="$1"
      shift

      printf 1>&2 -- 'Checking for addon %s in %s...\n' "$addon_id" "$repo"

      if ! version="$(repo_data "$repo" | addon_version "$addon_id")" || [ -z "$version" ]; then
        printf 1>&2 -- 'Unable to find addon %s in %s repository\n' "$addon_id" "$repo"
      fi

      datadir_count=0

      while read -r datadir; do
        if [ -z "$datadir" ]; then
          continue
        fi

        datadir_count="$((datadir_count + 1))"

        url="${datadir}/${addon_id}/${addon_id}-${version}.zip"
        path="$(path_for_zip_url "$url")"

        if fetch_zip "$url" "$path"; then
          echo "${version} ${addon_id} ${path}"
        fi
      done <<REPO_DATA
$(repo_data "$repo" | addon_datadirs 2>/dev/null)
REPO_DATA

      if [ "$datadir_count" -eq 0 ]; then
        datadir="$(repo_url "$repo")"
        printf 1>&2 -- 'Unable to find datadir in %s repository data; using default datadir "%s"\n' "$repo" "$datadir"

        url="${datadir}/${addon_id}/${addon_id}-${version}.zip"
        path="$(path_for_zip_url "$url")"

        # output addon download info
        if fetch_zip "$url" "$path"; then
          echo "${version} ${addon_id} ${path}"
        fi
      fi
    }
  fi

  rc=0

  # search addon_id in all enabled repositories
  for repo in ${ENABLED_REPOSITORIES?}; do
    search_addon "$repo" || rc="$?"

    # search requisite addons in all repositories
    while read -r dependency; do
      if [ -n "$dependency" ]; then
        resolve_addon "$dependency" || rc="$?"
      else
        printf 1>&2 -- 'Could not find addon %s in %s repository data\n' "$addon_id" "$repo"
      fi
    done <<REPO_DATA
$(repo_data "$repo" | addon_imports "$addon_id" 2>/dev/null)
REPO_DATA
  done

  if addon_installed "$addon_id"; then
    while read -r dependency; do
      if [ -n "$dependency" ]; then
        resolve_addon "$dependency" || rc="$?"
      else
        printf 1>&2 -- 'Could not find addon %s in %s addon data\n' "$addon_id" "$addon_id"
      fi
    done <<ADDON_DATA
$(addon_data "$addon_id" | addon_imports_singleton 2>/dev/null)
ADDON_DATA
  fi

  return "$rc"
}

yield_addons() {
  resolve_addon "$@" | sort -Vrk 2,1 | awk '!a[$2]++{print $2,$3,1; exit} {print $2,$3,0}'
}

enable_addon() {
  enable_addon_usage() {
    printf 1>&2 -- 'Usage: enable_addon <addon-id> <kodi-version>\n'
  }

  if [ "$#" -ne 2 ]; then
    enable_addon_usage
    return 1
  fi

  addon_id="$1"
  shift

  kodi_version="$1"
  shift

  if [ -z "$addon_id" ] || [ -z "$kodi_version" ]; then
    printf 1>&2 -- 'Error: addon ID and Kodi version cannot be empty.\n'
    enable_addon_usage
    return 1
  fi

  for db in "${KODI_DATA_DIR}/userdata/Database/Addons"*.db; do
    if [ -f "$db" ]; then
      break
    else
      unset db
    fi
  done

  if [ -z "${db:-}" ]; then
    case "${kodi_version%%.*}" in
      16)
          db="${KODI_DATA_DIR?}/userdata/Database/Addons20.db"
          ;;
      17 | 18 | 19)
          db="${KODI_DATA_DIR?}/userdata/Database/Addons27.db"
          ;;
      20)
          db="${KODI_DATA_DIR?}/userdata/Database/Addons33.db"
          ;;
      *)
          printf 1>&2 -- 'enable_addon: unsupported Kodi version: %s\n' "$kodi_version"
          return 1
          ;;
    esac
  fi

  # init empty db
  if ! [ -f "$db" ]; then
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

  if ! sqlite3 "$db" 'SELECT * from installed where addonID="'"$addon_id"'"' | grep -Fq "$addon_id"; then
    printf 1>&2 -- 'Adding %s to list of installed addons and enabling it...\n' "$addon_id"
    sqlite3 "$db" 'INSERT INTO installed (addonId, enabled, installDate) VALUES ("'"$addon_id"'", 1, "1970-01-01 00:00:01");'
  else
    printf 1>&2 -- 'Making sure %s is enabled...\n' "$addon_id"
    sqlite3 "$db" 'UPDATE installed SET enabled=1 WHERE addonId="'"$addon_id"'"'
  fi
}

set -eu

if [ "$#" -ne 2 ]; then
  usage
  exit 1
fi

target_addon_id="$1"
shift

kodi_version="$1"
shift

if ! KODI_USER="${KODI_USER:-$(id -u 2>/dev/null)}" || [ -z "${KODI_USER:-}" ]; then
  KODI_USER=kodi
fi

if [ -z "${KODI_DATA_DIR:-}" ]; then
  if KODI_HOME="$(home_of_user "$KODI_USER" 2>/dev/null)" && [ -n "$KODI_HOME" ]; then
    KODI_DATA_DIR="${KODI_HOME}/.kodi"
  else
    KODI_DATA_DIR=~/.kodi
  fi
fi

# KODI_DATA_DIR may contain an unexpanded tilde.
if data_dir="$(expand_user "$KODI_DATA_DIR")" && [ -n "$data_dir" ]; then
  KODI_DATA_DIR="$data_dir"
fi

cache_repositories

found_addons=0

while read -r addon_id path use; do
  # Not selected version of addon
  if [ "${use:-0}" != 1 ]; then
    continue
  fi

  if [ "$addon_id" = "$target_addon_id" ] || [ "$path" = - ]; then
    found_addons="$((found_addons + 1))"
  fi

  # No addon found, or addon already installed
  if [ "${addon_id:-}" = - ] || [ "$path" = - ]; then
    continue
  fi

  install_zip "$path"

  enable_addon "$addon_id" "$kodi_version"
done <<RESOLVE_ADDON
$(yield_addons "$target_addon_id")
RESOLVE_ADDON

if [ "$found_addons" -eq 0 ]; then
  printf 1>&2 -- 'No such addon (%s) found (or already installed)\n' "$target_addon_id"
  enable_addon "$target_addon_id" "$kodi_version" || exit
  printf 1>&2 -- 'Looks like addon %s is a core addon\n' "$target_addon_id"
fi
