#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Set up a tmux window the way I like it.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: ${CONFIG:=default}

USAGE="$0 [options]
Set up a tmux window
Options are:
  --config=path_or_name -- Specify either absolute path to the .json config
    containing the DUTs to run on, or just the name, in which case it will be
    loaded from configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
  --no-attach -- Don't attach to the tmux session that's created.
"

ATTACH=yes

for arg in "$@"; do
  case $arg in
  --config=*)
    CONFIG="${arg#*=}"
    shift
    ;;

  --no-attach)
    ATTACH=no
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

load_config "$CONFIG"

DEVICE_NAME="desktest"
export CROS_DIRECTORY=~/cros
kerneldir="${CROS_DIRECTORY}/src/third_party/kernel/v5.4"
export SERVO_PORT="9998"
export SERVO_SERIAL="C1903140033"
CCD_SERIAL="05823034-95984203"
export BOARD="dedede"

# Horrible hack: let me sudo without hassle so I can enter the chroot.
# This gets reverted by corp, but works for the moment I need it.
sudo su -c "echo '$USER ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"

# Clean up any old session
tmux kill-session -t desktest || true

# Fire up a new tmux session.
tmux new-session -t "${DEVICE_NAME}" -s "${DEVICE_NAME}" -d
tmux send-keys -t "${DEVICE_NAME}:1" "export k=${kerneldir}" C-m

# Create and set up the split window with servod and EC
tmux new-window -t "${DEVICE_NAME}:2" -e k="${kerneldir}"
tmux send-keys -t "${DEVICE_NAME}:2" "cros_sdk --nouse-image --no-ns-pid" C-m \
  "sudo servod --board=${BOARD} --port=${SERVO_PORT} \
   --serial=${SERVO_SERIAL}" C-m

tmux split-window -v -t "${DEVICE_NAME}:2" -e k="${kerneldir}"
tmux send-keys -t "${DEVICE_NAME}:2.1" \
  "while true; do \
  ~/trunk/src/platform/dev/contrib/dut-console -c ec --port=${SERVO_PORT}; \
  sleep 5; done" C-m

# Create and set up the AP UART window
tmux new-window -t "${DEVICE_NAME}:3" -e k="${kerneldir}"
tmux send-keys -t "${DEVICE_NAME}:3" \
  "while true; do \
  ~/trunk/src/platform/dev/contrib/dut-console -c cpu --port=${SERVO_PORT}; \
  sleep 5; done" C-m

# Set up a couple shells inside the chroot
for window in "${DEVICE_NAME}:4" "${DEVICE_NAME}:5"; do
  tmux new-window -t "${window}" -c "${CROS_DIRECTORY}"
  tmux send-keys -t "${window}" "cros_sdk --nouse-image --no-ns-pid" C-m
  tmux send-keys -t "${window}" \
    "export SERVO_PORT=-p${SERVO_PORT} PORT_SERVO=-p${SERVO_PORT} \
     SERVO_SERIAL=,serial=${CCD_SERIAL} SERIAL_SERVO=,serial=${CCD_SERIAL} \
     k=${kerneldir}" C-m

done

if [ "${ATTACH}" = "yes" ]; then
  tmux a -t "${DEVICE_NAME}"
fi
