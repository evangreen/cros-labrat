#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Run all the tests on all the DUTs in a specified config.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Run all the tests on all the DUTs specified in a given config:
  --config=path_or_name -- Specify either absolute path to the .json config,
    or just the name, in which case it will be loaded from
    configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
  --update-firmware -- Update the firmware on the device first.
  --update-os -- Update the OS on the device first.
  --force -- Do it even if some devices can't be reached.

For example, to update to the latest OS/firmware and run all tests on
all DUTs specified in configs/sample.json:
./test_all_duts.sh --config=sample --update-firmware --update-os --force
"

force=no
CONFIG=default
for arg in "$@"; do
  case "$arg" in
  --config=*)
    CONFIG="${arg#*=}"
    ;;

  --force)
    force=yes
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

load_config "$CONFIG"

if [ "${force}" != "yes" ]; then
  "${_labrat_top}/for_all_duts.sh" --config="${CONFIG}" "${_labrat_top}/device_status.sh"
fi

"${_labrat_top}/for_all_duts.sh" --config="${CONFIG}" "${_labrat_top}/test_one_dut.sh" "$@"
