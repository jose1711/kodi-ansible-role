#!/bin/sh

PS4='+ ${BASH_SOURCE:-${0}}@${LINENO:-0}${FUNCNAME:+#${FUNCNAME}()}: '

set -eu

resolve_command() {
  command -v "${1?}" 2>/dev/null || command -v -p "${1?}" 2>/dev/null
}

if [ -z "${KODI_EXECUTABLE:-}" ]; then
  if ! KODI_EXECUTABLE="$(resolve_command kodi-standalone)" || [ -z "${KODI_EXECUTABLE:-}" ]; then
    if ! KODI_EXECUTABLE="$(resolve_command kodi)" || [ -z "${KODI_EXECUTABLE:-}" ]; then
      KODI_EXECUTABLE=kodi
    fi
  else
    KODI_OPTIONS="${KODI_OPTIONS:-'--debug'}"
  fi
fi

KODI_OPTIONS="${KODI_OPTIONS:-'--standalone --debug'}"

# Write our PID to standard output for Ansible to collect.
echo "$$"

# NOTE that the word-splitting of `KODI_OPTIONS` is deliberate, so tell
# shellcheck to pipe down.
# shellcheck disable=SC2086
exec "$KODI_EXECUTABLE" $KODI_OPTIONS
