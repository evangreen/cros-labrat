#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Update the OS on a single running DUT via cros flash.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: "${CHANNEL:=dev-channel}"

USAGE="$0 [options]
Print the OS and firmware version of the given device.
Options are:
  --remote=111.222.33.44 -- Specify the remote IP.
"

for arg in "$@"; do
  case $arg in
  --remote=*)
    REMOTE="${arg#*=}"
    ;;

  --help)
    echo "$USAGE"
    exit 1
    ;;

  *)
    echo "Unknown argument: $arg"
    ;;
  esac
done

FW_VERSION="$(detect_fw_version)"
OS_VERSION="$(detect_os_version)"

printf "Remote: %s\n" "${REMOTE}"
printf "\tOS: %s\n" "${OS_VERSION}"
printf "\tFirmware: %s\n" "${FW_VERSION}"
exit 0