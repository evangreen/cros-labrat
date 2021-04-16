#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Reboot a DUT over and over again, watching for crashes.

set -e

_labrat_top="$(dirname "$0")/.."
. "${_labrat_top}/lib/helper_functions.sh"

COUNT=20
DELAY=60
OLD=
NEW=

USAGE="$0 [options]
Ping pong between two firmwares. The old is flashed via CCD, then
the new is updated via update_firmware.sh:
  --remote=111.222.33.44 -- Specify the remote IP.
  --count -- How many iterations to do. Default is $COUNT.
  --delay -- Delay between iterations. Default $DELAY seconds.
  --old=/path/to/fw.bin -- Reset the FW to this via CCD.
  --new-args=args -- Args to pass to update_firmware.sh for the new.

Example: tests/fw_update_stress.sh --remote=10.0.8.164 \\
  --old=\$HOME/.labrat/firmware/canary-channel-dedede-13606.83.0/image-metaknight.bin \\
  --new-args=\"--buildnum=13606.131.0 --channel=canary-channel --fw-name=image-metaknight.bin\"
"

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

  --new-args=*)
    NEW="${arg#*=}"
    shift
    ;;

  --old=*)
    OLD="${arg#*=}"
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

index=0
failures=0
while [ "${index}" -lt "${COUNT}" ]; do
  echo
  echo "$(date): Iteration ${index}. Resetting firmware"
  sudo futility update --servo_port="${SERVO_PORT#-p}" -i "${OLD}" \
    -p raiden_debug_spi:target=AP${SERIAL_SERVO} --force

  sleep "${DELAY}"
  echo "Connecting after old firmware..."

  "${_labrat_top}/device_status.sh" --remote="${REMOTE}"

  echo "Updating to new firmware..."
  "${_labrat_top}/update_firmware.sh" --remote="${REMOTE}" --reboot $NEW

  # Get warnings or errors.
  echo "Connecting after new firmware..."
  "${_labrat_top}/device_status.sh" --remote="${REMOTE}"

  # Add any additional checks here.
  index="$((index+1))"
done

echo "$(date): Finished ${COUNT} iterations with ${failures} failures"
[ "${failures}" -eq 0 ]