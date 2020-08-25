#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Update the AP firmware on a single running DUT via SSH.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: "${CHANNEL:=dev-channel}"

print_only=no

USAGE="$0 [options]
Download and update the AP firmware on a single running DUT via SSH.
Options are:
  --board=$BOARD -- Specify the (general) board name. Can be auto-detected.
  --fw-name=$FW_NAME -- Specify the name of the firmware file to flash. Can be
      auto-detected sometimes.
  --buildnum=12345.0.0 -- Specify the build number. Uses the second latest
    build by default.
  --channel=$CHANNEL -- Specify the channel to use.
  --remote=111.222.33.44 -- Specify the remote IP.
  --print -- Just print the (second) latest number.
"

for arg in "$@"; do
  case $arg in
  --board=*)
    BOARD="${arg#*=}"
    ;;

  --fw-name=*)
    FW_NAME="${arg#*=}"
    ;;

  --buildnum=*)
    BUILDNUM="${arg#*=}"
    ;;

  --channel=*)
    CHANNEL="${arg#*=}"
    ;;

  --remote=*)
    REMOTE="${arg#*=}"
    ;;

  --print)
    print_only=yes
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

if [ "${print_only}" = yes ]; then
  get_almost_latest_build_num "${CHANNEL}" "${BOARD}"
  exit 0
fi

if [ -z "${REMOTE}" ]; then
  echo "Error: --remote must be specified."
  exit 1
fi

[ -z "${BOARD}" ] && BOARD="$(detect_board ${REMOTE})"
[ -z "${FW_NAME}" ] && FW_NAME="image-$(detect_variant ${REMOTE}).dev.bin"
[ -z "${BUILDNUM}" ] && BUILDNUM="$(get_almost_latest_build_num "${CHANNEL}" "${BOARD}")"

download_firmware "${CHANNEL}" "${BOARD}" "${BUILDNUM}"
if [ -z "${DOWNLOADED_FIRMWARE_DIR}" ]; then
  echo "Error downloading firmware"
  exit 1
fi

update_firmware "${REMOTE}" "${DOWNLOADED_FIRMWARE_DIR}/${FW_NAME}"
