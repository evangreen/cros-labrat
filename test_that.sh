#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Wrap test_that.sh, generate metadata, and upload results.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Run test_that on a single remote, generate metadata, and upload results.
Options are:
  --remote=111.222.33.44 -- Specify the remote IP. This script will pass the
    remote onto test_that, you don't need to specify it twice.
  --config=path_or_name -- Specify either absolute path to the .json config
    containing GS bucket, or just the name, in which case it will be
    loaded from configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
Example:
./test_that.sh --remote=192.168.1.120 suite:bvt-inline
"

while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
  --config=*)
    CONFIG="${arg#*=}"
    shift
    ;;

  --remote=*)
    REMOTE="${arg#*=}"
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
  echo "Error: Expected a test to run for test_that."
  exit 1
fi

load_config "$CONFIG"
run_test_that "${REMOTE}" "$@"
sweep_results
