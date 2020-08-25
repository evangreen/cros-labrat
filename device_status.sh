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

FW_VERSION="$(do_ssh "${REMOTE}" crossystem fwid)"
OS_VERSION="$(do_ssh "${REMOTE}" \
 "sed -n 's/CHROMEOS_RELEASE_BUILDER_PATH=\(.*\)/\1/p' /etc/lsb-release")"

printf "Remote: %s\n" "${REMOTE}"
printf "\tOS: %s\n" "${OS_VERSION}"
printf "\tFirmware: %s\n" "${FW_VERSION}"
exit 0