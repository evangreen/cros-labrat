#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Update the OS on a single running DUT via cros flash.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: "${CHANNEL:=dev-channel}"

autologin=no
print_only=no
download_only=no

USAGE="$0 [options]
Download and update OS on a single running DUT via SSH.
Options are:
  --board=$BOARD -- Specify the (general) board name. Can be auto-detected.
  --buildnum=12345.0.0 -- Specify the build number. Uses the second latest
    build by default.
  --channel=$CHANNEL -- Specify the channel to use.
  --remote=111.222.33.44 -- Specify the remote IP.
  --print -- Just print the (second) latest number.
  --download-only -- Just download the image, don't flash anywhere.
  --autologin -- Run the autologin script after updating.
"

for arg in "$@"; do
  case $arg in
  --autologin)
    autologin=yes
    ;;

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

  --download-only)
    download_only=yes
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

if [ -z "${REMOTE}" -a "${download_only}" = "no" ]; then
  echo "Error: --remote must be specified."
  exit 1
fi

[ -z "${BOARD}" ] && BOARD="$(detect_board ${REMOTE})"
[ -z "${BUILDNUM}" ] && BUILDNUM="$(get_almost_latest_build_num "${CHANNEL}" "${BOARD}")"

download_test_image "${CHANNEL}" "${BOARD}" "${BUILDNUM}"
if [ -z "${DOWNLOADED_IMAGE_FILE}" ]; then
  echo "Error downloading image"
  exit 1
fi

if [ "${download_only}" = "yes" ]; then
  exit 0
fi

update_os "${REMOTE}" "${DOWNLOADED_IMAGE_FILE}"

if [ "${autologin}" = "yes" ]; then
  "${_labrat_top}/autologin.sh" --remote="${REMOTE}" --no-creds
fi
