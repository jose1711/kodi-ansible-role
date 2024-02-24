#!/bin/sh

PS4='+ ${BASH_SOURCE:-${0}}@${LINENO:-0}${FUNCNAME:+#${FUNCNAME}()}: '

set -eu

"${KODI_EXECUTABLE:-kodi}" 1>/dev/null &

pid="$!"
echo "$pid"

# Try to disown the process, but do not exit with nonzero status if this fails.
# shellcheck disable=SC3044
disown "$pid" 1>/dev/null 2>&1 || :
