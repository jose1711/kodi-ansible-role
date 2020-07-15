#!/bin/bash
# find, download and enable Kodi addon if not already present,
# also requisites are pulled
#
# uses hardcoded repository list
#
# $1 = addon_id
# $2 = major kodi version

addon_id=$1
kodi_version=$2

if [ -z "${addon_id}" -o -z "${kodi_version}" ]
then
  echo "Both addon_id and kodi_version must be provided as arguments"
  exit 1
fi

case "${kodi_version}" in
  16) codename=jarvis
      ;;
  17) codename=krypton
      ;;
  18) codename=leia
      ;;
  19) codename=matrix
      ;;
esac

cd $(dirname $0)
source repositories.sh


function cache_repositories() {
  for repo_data in ${repositories[@]}
  do
    name=${repo_data%=*}
    url=${repo_data#*=}
    echo "$url" | grep -q "\.gz"
    if [ $? -eq 0 ]
    then
      filter='gunzip -c -'
    else
      filter='cat'
    fi
    # only download if the file is missing
    if [ ! -f "/tmp/${name}.xml" ]
    then
      echo "Caching name: ${name}, url: ${url}" >&2
      curl -s "${url}" | ${filter} >/tmp/${name}.xml
    fi
  done
}

function repo_data() {
  repo=$1
  cat /tmp/${repo}.xml
}

function repo_url() {
  repo=$1
  for repo_data in ${repositories[@]}
  do
    name=${repo_data%=*}
    url=${repo_data#*=}
    if [ "${name}" = "${repo}" ]
    then
      dirname ${url}
      return
    fi
  done
}

cache_repositories


function resolve_addon() {
  local addon_id=$1
  local version
  # no need to resolve this core dependency
  if [ "${addon_id}" = "xbmc.python" ]
  then
    return
  fi

  echo "Resolving ${addon_id}.." >&2

  if [ -d ~/.kodi/addons/${addon_id} ]
  then
    echo "Skipping - already installed" >&2
    return
  fi

  # search addon_id in all enabled repositories
  for repo in ${enabled_repos[@]}
  do
    echo "Checking in ${repo}.." >&2
    version=$(repo_data ${repo} | xmllint --xpath 'string(//addon[@id="'"${addon_id}"'"]/@version)' -)
    if [ -z "${version}" ]
    then
      echo "Not found in ${repo} repository" >&2
      continue
    fi
    dependencies=$(repo_data ${repo} | xmllint --xpath '//addon[@id="'"${addon_id}"'"]/requires/import/@addon' - 2>/dev/null | tr ' ' '\n' | awk -F= '{print $2}' | tr -d '"')

    # found no way how to separate text nodes than.. well.. this
    datadirs=$(repo_data ${repo} | xmllint --xpath '//datadir' - | sed 's/<[^>]*>/ /g' - 2>/dev/null)
    if [ -z "${datadirs}" ]
    then
      # output addon download info
      echo "${version} ${addon_id} $(repo_url ${repo})/${addon_id}/${addon_id}-${version}.zip"
    else
      for datadir in ${datadirs}
      do
        curl -Lo "/tmp/tmp_${addon_id}-$version.zip" "${datadir}/${addon_id}/${addon_id}-${version}.zip"
        unzip -t "/tmp/tmp_${addon_id}-$version.zip" >/dev/null 2>&1
        if [ $? -eq 0 ]
        then
          echo "${version} ${addon_id} ${datadir}/${addon_id}/${addon_id}-${version}.zip"
        fi
        rm "/tmp/tmp_${addon_id}-$version.zip"
      done
    fi

    # search requisite addons in all repositories
    for dependency in ${dependencies}
    do
      resolve_addon ${dependency}
    done
  done
}

latest_addon_urls=$(resolve_addon "${addon_id}" | sort -nrk 2,1 | awk '!a[$2]++{print $2,$3}')

if [ -z "${latest_addon_urls}" ]
then
  echo "No such addon (${addon_id}) found (or already installed)"
  exit
fi

echo "${latest_addon_urls}" | while read -r addon_id url
do
  if [ -d ~/.kodi/addons/${addon_id} ]
  then
    echo "Skipping download of ${addon_id} - already installed" >&2
  else
    echo "Downloading ${addon_id} from ${url}.." >&2
    curl -Lo "/tmp/${addon_id}.zip" "${url}"
    cd ~/.kodi/addons
    unzip "/tmp/${addon_id}.zip"
    rm "/tmp/${addon_id}.zip"
  fi
  cd $(dirname $0)
  ./enable_kodi_addon.sh "${addon_id}" "${kodi_version}"
done
