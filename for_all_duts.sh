#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Run the specified command on all devices.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: ${CONFIG:=default}

USAGE="$0 [options] <command> <args>
Run a labrat command for each DUT specified in the config. This script will
pass --remote=<REMOTE> to the specified command for each DUT.
Options are:
  --config=path_or_name -- Specify either absolute path to the .json config
    containing the DUTs to run on, or just the name, in which case it will be
    loaded from configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
  --remote=111.222.33.44 -- Manually specify a remote to run on. Can be
    specified more than once. If specified, no config is used.

Example: ./for_all_duts.sh --config=sample ./update_firmware.sh

Runs the update_firmware.sh script on all DUTs specified in
configs/sample.json.
"

while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
  --config=*)
    CONFIG="${arg#*=}"
    shift
    ;;

  --remote=*)
    REMOTE="$REMOTE ${arg#*=}"
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

if [ "$#" -eq 0 ]; then
  echo "Error: Expected a command to run on each DUT."
  exit 1
fi

command="$1"
shift

count=0
pids=

# Load the DUT addresses from the config.
if [ -z "$REMOTE" ]; then
  load_config "$CONFIG"
  dut_count="$(get_dut_count)"
  while [ "${count}" -lt "${dut_count}" ]; do
    get_dut_config "${count}"
    "$command" --remote="${DUT_ip}" "$@" &
    pids="${pids} $!"
    : $((count+=1))
  done

# Do the manually specified remote way.
else
  for r in $REMOTE; do
    "$command" --remote="$r" "$@" &
    pids="${pids} $!"
    : $((count+=1))
  done
fi

# Wait for everything to finish.
failures=0
for job in $pids; do
  wait "$job" || : $((failures+=1))
done

if [ "$failures" -eq 0 ]; then
  echo "Successfully ran on $count DUTs"
else
  echo "ERROR: $failures failures out of $count DUTs"
fi
