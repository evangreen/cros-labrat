#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Reboot a DUT over and over again, watching for crashes.

set -e

_labrat_top="$(dirname "$0")/.."
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Reboot over and over again, watching for crashes in console-ramoops:
  --remote=111.222.33.44 -- Specify the remote IP.
  --count -- How many iterations to do. Default is 1000.
  --delay -- Delay between iterations. Default 3 seconds.
"

COUNT=1000
DELAY=3

while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
  --remote=*)
    REMOTE="${arg#*=}"
    shift
    ;;

  --count=*)
    COUNT="${arg#*=}"
    shift
    ;;

  --delay=*)
    DELAY="${arg#*=}"
    shift
    ;;

  --help)
    echo "$USAGE"
    exit 1
    ;;

  *)
    break
    ;;
  esac
done

if [ "$#" -ne 0 ]; then
  echo "Error: Unexpected arguments."
  exit 1
fi

load_config "$CONFIG"

"${_labrat_top}/device_status.sh" --remote="${REMOTE}"

index=0
failures=0
while [ "${index}" -lt "${COUNT}" ]; do
  echo
  echo "$(date): Iteration ${index}"
  reboot_dut "${REMOTE}"

  # Get warnings or errors.
  if do_ssh "${REMOTE}" \
     "grep -q 'Modules linked in:' /sys/fs/pstore/console-ramoops-0"; then

    failures="$((failures+1))"
    do_ssh "${REMOTE}" "cat -n /sys/fs/pstore/console-ramoops-0"
  fi

  sleep "${DELAY}"

  # Add any additional checks here.
  index="$((index+1))"
done

echo "$(date): Finished ${COUNT} iterations with ${failures} failures"
[ "${failures}" -eq 0 ]