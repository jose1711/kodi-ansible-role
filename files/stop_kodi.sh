#!/bin/sh

PS4='+ ${BASH_SOURCE:-${0}}@${LINENO:-0}${FUNCNAME:+#${FUNCNAME}()}: '

set -eu

kill_kodi() {
  kill "$@" "$KODI_PID"
}

pkill_kodi() {
  pkill "$@" -n "${KODI_EXECUTABLE:-kodi}" -u "${KODI_USER:-kodi}"
}

"${KODI_SEND_EXECUTABLE:-kodi-send}" \
  ${KODI_SEND_HOST:+--host="${KODI_SEND_HOST}"} \
  ${KODI_SEND_PORT:+--port="${KODI_SEND_PORT}"} \
  --action=Quit || :

sigarg="-${KODI_KILL_SIGNAL:-TERM}"

if [ -n "${KODI_PID:-}" ]; then
  if kill_kodi -0; then
    # Kill any children of the started process
    pkill -P "$KODI_PID" "$sigarg" || :

    # Kill the process itself
    kill_kodi "$sigarg" || :
  else
    # Fall back to `pkill` in case the process that we started launched
    # something else that got reparented to `init`.
    pkill_kodi -P 1 "$sigarg" || :
  fi
else
  pkill_kodi "$sigarg" || :
fi
