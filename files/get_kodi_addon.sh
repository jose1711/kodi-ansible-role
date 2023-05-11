#!/usr/bin/env bash
# find, download and enable Kodi addon if not already present,
# also requisites are pulled
#
# uses hardcoded repository list
#
# $1 = addon_id
# $2 = major kodi version

set -euo pipefail

usage() {
  printf 1>&2 -- 'Usage: %s <addon-id> <kodi-version>\n' "${0##*/}"
}

if (( "$#" != 2 ))
then
  usage
  exit 1
fi

addon_id="$1"
shift

kodi_version="$1"
shift

cd "$(dirname "$0")" || exit

source repositories.sh || exit

cache_repositories() {
  for repo_data in "${repositories[@]?}"
  do
    name="${repo_data%=*}"
    url="${repo_data#*=}"

    # only download if the file is missing
    if ! [[ -f "/tmp/${name}.xml" ]]; then
      printf 1>&2 -- 'Already cached name: %s, url: %s\n' "$name" "$url"
      continue
    fi

    local -a filter=(cat)

    case "$url" in
      *.gz) filter=(gunzip -c -)
        ;;
    esac

    # only download if the file is missing
    if ! [[ -f "/tmp/${name}.xml" ]]
    then
      printf 1>&2 -- 'Caching name: %s, url: %s\n' "$name" "$url"
      curl -s "$url" | "${filter[@]}" > "/tmp/${name}.xml"
    fi
  done
}

repo_data() {
  cat "/tmp/${1?}.xml"
}

repo_url() {
  for repo_data in "${repositories[@]?}"
  do
    name=${repo_data%=*}
    url=${repo_data#*=}
    if [[ "$name" = "${1?}" ]]
    then
      dirname "$url"
      return
    fi
  done
}

resolve_addon() {
  local addon_id="$1"
  shift

  local version

  # no need to resolve this core dependency
  if [[ "${addon_id}" = xbmc.python ]]
  then
    return
  fi

  printf 1>&2 -- 'Resolving %s...\n' "$addon_id"

  if [[ -d ~/.kodi/addons/"$addon_id" ]]
  then
    printf 1>&2 -- 'Skipping - %s already installed\n' "$addon_id"
    return
  fi

  # search addon_id in all enabled repositories
  for repo in "${enabled_repos[@]?}"
  do
    printf 1>&2 -- 'Checking in %s...\n' "$repo"

    if ! version="$(repo_data "$repo" | xmllint --xpath 'string(//addon[@id="'"$addon_id"'"]/@version)' -)" || [[ -z "$version" ]]
    then
      printf 1>&2 -- 'Not found in %s repository\n' "$repo"
      continue
    fi

    local datadir_count=0

    while read -r datadir
    do
      (( datadir_count++ ))

      # unzip -t "/tmp/tmp_${addon_id}-$version.zip" >/dev/null 2>&1
      if {
            curl -Lo "/tmp/tmp_${addon_id}-$version.zip" "${datadir}/${addon_id}/${addon_id}-${version}.zip" \
        &&  file "/tmp/tmp_${addon_id}-$version.zip" | grep -q 'Zip archive'
      }
      then
        echo "${version} ${addon_id} ${datadir}/${addon_id}/${addon_id}-${version}.zip"
      fi

      rm -f "/tmp/tmp_${addon_id}-$version.zip"

    # found no way how to separate text nodes than.. well.. this
    done < <(repo_data "$repo" | xmllint --xpath '//datadir' - | sed 's/<[^>]*>/ /g' - 2>/dev/null)

    if (( datadir_count == 0 ))
    then
      # output addon download info
      echo "${version} ${addon_id} $(repo_url "$repo")/${addon_id}/${addon_id}-${version}.zip"
    fi

    # search requisite addons in all repositories
    while read -r dependency
    do
      resolve_addon "$dependency" || return
    done < <(repo_data "$repo" | xmllint --xpath '//addon[@id="'"$addon_id"'"]/requires/import/@addon' - 2>/dev/null | tr ' ' '\n' | awk -F= '{print $2}' | tr -d '"')
  done
}

cache_repositories

found_addons=0

while read -r addon_id url
do
  (( found_addons++ ))

  if [[ -d ~/.kodi/addons/"$addon_id" ]]
  then
    printf 1>&2 -- 'Skipping download of %s - already installed\n' "$addon_id"
  else
    printf 1>&2 -- 'Downloading %s from %s...\n' "$addon_id" "$url"

    curl -L "$url" | unzip -d ~/.kodi/addons -c
  fi

  cd ~/.kodi

  ./enable_kodi_addon.sh "$addon_id" "$kodi_version"
done < <(resolve_addon "$addon_id" | sort -nrk 2,1 | awk '!a[$2]++{print $2,$3}')

if (( found_addons == 0 ))
then
  printf 1>&2 -- 'No such addon (%s) found (or already installed)\n' "$addon_id"
fi
