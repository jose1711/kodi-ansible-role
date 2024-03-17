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

# Try to run Kodi under an X server; this may prevent early bailout due to
# failure creating the Kodi GUI.
#
# NOTE that xvfb-run appears to be Debian/Ubuntu specific.
#
# NOTE also that the word-splitting of `KODI_OPTIONS` is deliberate, so tell
# shellcheck to pipe down.
#
# shellcheck disable=SC2086
if xvfb_run="$(resolve_command xvfb-run)" && [ -n "${xvfb_run:-}" ]; then
  exec "$xvfb_run" -e /tmp/xvfb.out "$KODI_EXECUTABLE" $KODI_OPTIONS 1>/dev/null
else
  exec "$KODI_EXECUTABLE" $KODI_OPTIONS
fi
