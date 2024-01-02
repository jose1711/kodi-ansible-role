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
    while read -r __xmllint_filter_attr_values_attrdef; do
      __xmllint_filter_attr_values_attrval="${__xmllint_filter_attr_values_attrdef#*"${1?}=\""}"
      printf -- '%s\n' "${__xmllint_filter_attr_values_attrval%'"'}"
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
  for __cache_repositories_repo_data in ${REPOSITORIES?}; do
    __cache_repositories_name="${__cache_repositories_repo_data%=*}"
    __cache_repositories_url="${__cache_repositories_repo_data#*=}"

    __cache_repositories_data_path="${TMPDIR:-/tmp}/${__cache_repositories_name}.xml"

    # only download if the file is missing
    if [ -f "$__cache_repositories_data_path" ]; then
      printf 1>&2 -- 'Already cached name: %s, url: %s\n' "$__cache_repositories_name" "$__cache_repositories_url"
      continue
    fi

    printf 1>&2 -- 'Caching name: %s, url: %s\n' "$__cache_repositories_name" "$__cache_repositories_url"

    __cache_repositories_fetch_path="${__cache_repositories_data_path}.out"

    _curl -fsLS -o "$__cache_repositories_fetch_path" "$__cache_repositories_url" || {
      __cache_repositories_rc="$?"
      rm -f "$__cache_repositories_fetch_path"
      continue
    }

    {
      gunzip -c "$__cache_repositories_fetch_path" >"$__cache_repositories_data_path"  \
        || mv -f "$__cache_repositories_fetch_path" "$__cache_repositories_data_path"
    } || {
      __cache_repositories_rc="$?"
      rm -f "$__cache_repositories_data_path"
    }

    rm -f "$__cache_repositories_fetch_path"
  done

  return "${__cache_repositories_rc:-0}"
}

repo_data() {
  cat "${TMPDIR:-/tmp}/${1?}.xml"
}

repo_url() {
  for __repo_url_repo_data in ${REPOSITORIES?}; do
    __repo_url_name=${__repo_url_repo_data%=*}
    __repo_url_url=${__repo_url_repo_data#*=}

    if [ "$__repo_url_name" = "${1?}" ]; then
      dirname "$__repo_url_url"
      return
    fi
  done

  return 1
}

path_for_zip_url() {
  printf -- '%s/%s' "${TMPDIR:-/tmp}" "$(printf -- '%s' "${1?}" | sed -e 's/[^[:alnum:]_.]/-/g')"
}

fetch_zip_atomic() {
  __fetch_zip_dirname="$(dirname "${2?}")"
  __fetch_zip_basename="$(basename "$2")"

  __fetch_zip_tmp="$(mktemp "${__fetch_zip_dirname}/.${__fetch_zip_basename}.XXXXXXXX")" || return

  if ! _curl -Lo "$__fetch_zip_tmp" "${1?}"; then
    printf 1>&2 -- 'Unable to fetch "%s" from "%s"\n' "$2" "$1"
    rm -f "$__fetch_zip_tmp"
    return 1
  fi

  if ! unzip -lq "$__fetch_zip_tmp" >/dev/null 2>&1; then
    printf 1>&2 -- '"%s" from "%s" does not look like a zip archive\n' "$2" "$1"
    rm -f "$__fetch_zip_tmp"
    return 1
  fi

  mv -f "$__fetch_zip_tmp" "$2"
}

fetch_zip() {
  if [ -f "${2?}" ]; then
    return
  else
    fetch_zip_atomic "$@"
  fi
}

install_zip() {
  unzip -q -o -d "${KODI_DATA_DIR?}/addons" "${1?}"
}

resolve_addon() {
  __resolve_addon_addon_id="${1?}"
  shift

  __resolve_addon_url="${1:-}"

  if [ -z "$__resolve_addon_addon_id" ]; then
    echo 1>&2 'Error: "" is not a valid addon ID'
    return 1
  fi

  # no need to resolve this core dependency
  if [ "$__resolve_addon_addon_id" = xbmc.python ]; then
    echo 0 - -
    return
  fi

  printf 1>&2 -- 'Resolving %s...\n' "$__resolve_addon_addon_id"

  search_addon() { :;  }

  if addon_installed "$__resolve_addon_addon_id"; then
    printf 1>&2 -- 'Skipping - %s already installed\n' "$__resolve_addon_addon_id"
    echo 0 - -
  elif [ -n "${__resolve_addon_url:-}" ]; then
    printf 1>&2 -- 'Fetching addon %s from %s...\n' "$__resolve_addon_addon_id" "$__resolve_addon_url"

    __resolve_addon_path="$(path_for_zip_url "$__resolve_addon_url")"

    # output addon download info
    if fetch_zip "$__resolve_addon_url" "$__resolve_addon_path" && install_zip "$__resolve_addon_path" && enable_addon "$__resolve_addon_addon_id" "${kodi_version?}"; then
      printf 1>&2 -- 'Installed addon %s from %s...\n' "$__resolve_addon_addon_id" "$__resolve_addon_url"
      echo "0 ${__resolve_addon_addon_id} -"
    fi
  else
    search_addon() {
      __search_addon_repo="${1?}"
      shift

      __search_addon_addon_id="${__resolve_addon_addon_id?}"

      printf 1>&2 -- 'Checking for addon %s in %s...\n' "$__search_addon_addon_id" "$__search_addon_repo"

      if ! __search_addon_version="$(repo_data "$__search_addon_repo" | addon_version "$__search_addon_addon_id")" || [ -z "$__search_addon_version" ]; then
        printf 1>&2 -- 'Unable to find addon %s in %s repository\n' "$__search_addon_addon_id" "$__search_addon_repo"
        return 1
      fi

      __search_addon_datadir_count=0

      while read -r __search_addon_datadir; do
        if [ -z "$__search_addon_datadir" ]; then
          continue
        fi

        __search_addon_datadir_count="$((__search_addon_datadir_count + 1))"

        __search_addon_url="${__search_addon_datadir}/${__search_addon_addon_id}/${__search_addon_addon_id}-${__search_addon_version}.zip"
        __search_addon_path="$(path_for_zip_url "$__search_addon_url")"

        if fetch_zip "$__search_addon_url" "$__search_addon_path"; then
          printf 1>&2 -- 'Fetched addon from %s to %s...\n' "$__search_addon_url" "$__search_addon_path"
          echo "${__search_addon_version} ${__search_addon_addon_id} ${__search_addon_path}"
        fi
      done <<REPO_DATA
$(repo_data "$__search_addon_repo" | addon_datadirs 2>/dev/null)
REPO_DATA

      if [ "$__search_addon_datadir_count" -eq 0 ]; then
        __search_addon_datadir="$(repo_url "$__search_addon_repo")"
        printf 1>&2 -- 'Unable to find datadir in %s repository data; using default datadir "%s"\n' "$__search_addon_repo" "$__search_addon_datadir"

        __search_addon_url="${__search_addon_datadir}/${__search_addon_addon_id}/${__search_addon_addon_id}-${__search_addon_version}.zip"
        __search_addon_path="$(path_for_zip_url "$__search_addon_url")"

        # output addon download info
        if fetch_zip "$__search_addon_url" "$__search_addon_path"; then
          printf 1>&2 -- 'Fetched addon from %s (default) to %s...\n' "$__search_addon_url" "$__search_addon_path"
          echo "${__search_addon_version} ${__search_addon_addon_id} ${__search_addon_path}"
        fi
      fi
    }
  fi

  __resolve_addon_rc=0

  # search addon_id in all enabled repositories
  for __resolve_addon_repo in ${ENABLED_REPOSITORIES?}; do
    search_addon "$__resolve_addon_repo" || __resolve_addon_rc="$?"

    # search requisite addons in all repositories
    while read -r __resolve_addon_dependency; do
      if [ -n "$__resolve_addon_dependency" ]; then
        printf 1>&2 -- 'Found addon %s in %s repository data\n' "$__resolve_addon_addon_id" "$__resolve_addon_repo"
        (resolve_addon "$__resolve_addon_dependency") || __resolve_addon_rc="$?"
      else
        printf 1>&2 -- 'Could not find addon %s in %s repository data\n' "$__resolve_addon_addon_id" "$__resolve_addon_repo"
      fi
    done <<REPO_DATA
$(repo_data "$__resolve_addon_repo" | addon_imports "$__resolve_addon_addon_id" 2>/dev/null)
REPO_DATA
  done

  if addon_installed "$__resolve_addon_addon_id"; then
    while read -r __resolve_addon_dependency; do
      if [ -n "$__resolve_addon_dependency" ]; then
        printf 1>&2 -- 'Found addon %s in %s addon data\n' "$__resolve_addon_addon_id" "$__resolve_addon_addon_id"
        (resolve_addon "$__resolve_addon_dependency") || __resolve_addon_rc="$?"
      else
        printf 1>&2 -- 'Could not find addon %s in %s addon data\n' "$__resolve_addon_addon_id" "$__resolve_addon_addon_id"
      fi
    done <<ADDON_DATA
$(addon_data "$__resolve_addon_addon_id" | addon_imports_singleton 2>/dev/null)
ADDON_DATA
  fi

  return "$__resolve_addon_rc"
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

  __enable_addon_addon_id="$1"
  shift

  __enable_addon_kodi_version="${1:-${kodi_version?}}"
  shift

  if [ -z "$__enable_addon_addon_id" ] || [ -z "$__enable_addon_kodi_version" ]; then
    printf 1>&2 -- 'Error: addon ID and Kodi version cannot be empty.\n'
    enable_addon_usage
    return 1
  fi

  for __enable_addon_db in "${KODI_DATA_DIR}/userdata/Database/Addons"*.db; do
    if [ -f "$__enable_addon_db" ]; then
      break
    else
      unset __enable_addon_db
    fi
  done

  if [ -z "${__enable_addon_db:-}" ]; then
    case "${__enable_addon_kodi_version%%.*}" in
      16)
          __enable_addon_db="${KODI_DATA_DIR?}/userdata/Database/Addons20.db"
          ;;
      17 | 18 | 19)
          __enable_addon_db="${KODI_DATA_DIR?}/userdata/Database/Addons27.db"
          ;;
      20)
          __enable_addon_db="${KODI_DATA_DIR?}/userdata/Database/Addons33.db"
          ;;
      *)
          printf 1>&2 -- 'enable_addon: unsupported Kodi version: %s\n' "$__enable_addon_kodi_version"
          return 1
          ;;
    esac
  fi

  # init empty db
  if ! [ -f "$__enable_addon_db" ]; then
    mkdir -p "${__enable_addon_db%/*}"
    sqlite3 "$__enable_addon_db" <<"HERE"
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

  if ! sqlite3 "$__enable_addon_db" 'SELECT * from installed where addonID="'"$__enable_addon_addon_id"'"' | grep -Fq "$__enable_addon_addon_id"; then
    if [ -n "${ENABLE_ADDON_STRICT:-}" ]; then
      printf 1>&2 -- 'Addon %s is not currently installed...\n' "$__enable_addon_addon_id"
      return 1
    else
      printf 1>&2 -- 'Adding %s to list of installed addons and enabling it...\n' "$__enable_addon_addon_id"
      sqlite3 "$__enable_addon_db" 'INSERT INTO installed (addonId, enabled, installDate) VALUES ("'"$__enable_addon_addon_id"'", 1, "1970-01-01 00:00:01");'
    fi
  else
    printf 1>&2 -- 'Making sure %s is enabled...\n' "$__enable_addon_addon_id"
    sqlite3 "$__enable_addon_db" 'UPDATE installed SET enabled=1 WHERE addonId="'"$__enable_addon_addon_id"'"'
  fi
}

# Like `enable_addon`, but fails if the addon is not currently in the
# `installed` table.
enable_addon_strict() {
  ENABLE_ADDON_STRICT=yes enable_addon "$@"
}

set -eu

# Try to enable Bash's `pipefail` mode (pipeline exits with the status
# of the first command to exit with non-zero status, else exits with zero).
# shellcheck disable=SC3040
if (set -o pipefail) 2>/dev/null; then
  set -o pipefail
fi

if [ "$#" -ne 2 ]; then
  usage
  exit 1
fi

target_addon_id="$1"
shift

kodi_version="$1"
shift

case "$target_addon_id" in
  *=*)
    target_url="${target_addon_id#*=}"
    target_addon_id="${target_addon_id%%=*}"
    ;;
esac

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
$(yield_addons "$target_addon_id" "${target_url:-}")
RESOLVE_ADDON

if [ "$found_addons" -eq 0 ]; then
  printf 1>&2 -- 'No such addon (%s) found (or already installed)\n' "$target_addon_id"
  enable_addon_strict "$target_addon_id" "$kodi_version" || exit
  printf 1>&2 -- 'Looks like addon %s is a core addon\n' "$target_addon_id"
fi
