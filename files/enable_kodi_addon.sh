#!/usr/bin/env bash
# enable Kodi addon
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

if [[ -z "$addon_id" ]] || [[ -z "$kodi_version" ]]
then
  printf 1>&2 -- 'Error: addon ID and Kodi version cannot be empty.\n'
  usage
  exit 1
fi

for db in ~/.kodi/userdata/Database/Addons*.db
do
  if [[ -f "$db" ]]
  then
    break
  else
    unset db
  fi
done

if [[ -z "${db:-}" ]]
then
  case "$kodi_version" in
    16) db=~/.kodi/userdata/Database/Addons20.db
        ;;
    17|18|19) db=~/.kodi/userdata/Database/Addons27.db
        ;;
    20) db=~/.kodi/userdata/Database/Addons33.db
        ;;
    *)
      printf 1>&2 -- '%s: unsupported Kodi version: %s\n' "${0##*/}" "$kodi_version"
      exit
        ;;
  esac
fi

# init empty db
if ! [[ ! -f "$db" ]]
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
