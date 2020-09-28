#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Run all the tests in a given config on a single DUT.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Run all the tests specified in a config on a single DUT:
  --remote=111.222.33.44 -- Specify the remote IP.
  --config=path_or_name -- Specify either absolute path to the .json config,
    or just the name, in which case it will be loaded from
    configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
  --update-firmware -- Update the firmware on the device first.
  --update-os -- Update the OS on the device first.
  --force -- Don't ping the device for connectivity first.
For example, to run all tests specified in configs/sample.json:
./test_one_dut.sh --remote=192.168.1.120 --config=sample
"

update_firmware=no
update_os=no
force=no

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

  --update-firmware)
    update_firmware=yes
    shift
    ;;

  --update-os)
    update_os=yes
    shift
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

if [ "$#" -ne 0 ]; then
  echo "Error: Unexpected arguments."
  exit 1
fi

load_config "$CONFIG"

"${_labrat_top}/device_status.sh" --remote="${REMOTE}"

# Update the firmware and/or OS first to make sure things are fresh.
if [ "${update_firmware}" = yes ]; then
  "${_labrat_top}/update_firmware.sh" --remote="${REMOTE}" --cold-reboot
fi

if [ "${update_os}" = yes ]; then
  "${_labrat_top}/update_os.sh" --remote="${REMOTE}"
fi

# Run all the tast tests.
tests="$(get_tasts)"
for t in ${tests}; do
  "${_labrat_top}/tast_run.sh" --remote="${REMOTE}" --config="${CONFIG}" "${t}"
done

# Run all the autotest tests.
tests="$(get_autotests)"
for t in ${tests}; do
  "${_labrat_top}/test_that.sh" --remote="${REMOTE}" --config="${CONFIG}" "${t}"
done
