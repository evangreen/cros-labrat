#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Set up a tmux window the way I like it.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: ${CONFIG:=default}

USAGE="$0 [options] <dut_name>
Set up a tmux window with servod, EC console, CPU console, and some chroots.
dut_name specifies a DUT with the corresponding 'name' in the selected
config.json.
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
    if [ -n "${DEVICE_NAME}" ]; then
      echo "Expected only one argument: the device name."
      exit 1
    fi

    DEVICE_NAME="${arg}"
    ;;
  esac
done

if [ -z "${DEVICE_NAME}" ]; then
  echo "Error: Please specify a device name from ${CONFIG}".
  exit 1
fi

load_config "$CONFIG"
DUT_name=
DUT_kernel=5.4
get_dut_config "--by=name=${DEVICE_NAME}"
if [ -z "${DUT_name}" ]; then
  echo "Found no DUT named: ${DEVICE_NAME}"
  exit 1
fi

if [ -z "${DUT_servo_serial}" -o -z "${DUT_servo_port}" ]; then
  echo "Please set servo_serial and servo_port config entries for ${DUT=name}."
  exit 1
fi

# For servo v2, if ccd_serial is unset, use servo_serial.
[ -z "${DUT_ccd_serial}" ] && DUT_ccd_serial="${DUT_servo_serial}"

# I guess this should come from a global config.
CROS_DIRECTORY=~/cros
kerneldir="${HOME}/trunk/src/third_party/kernel/v${DUT_kernel}"

# Horrible hack: let me sudo without hassle so I can enter the chroot.
# This gets reverted by corp, but works for the moment I need it.
# Use at your own peril!
sudo su -c "echo '$USER ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"

# Clean up any old session
tmux kill-session -t "${DEVICE_NAME}" || true

# Fire up a new tmux session.
tmux new-session -t "${DEVICE_NAME}" -s "${DEVICE_NAME}" -d
tmux send-keys -t "${DEVICE_NAME}:1" "export k=${kerneldir}" C-m

# Create and set up the split window with servod and EC
tmux new-window -t "${DEVICE_NAME}:2" -e k="${kerneldir}"
tmux send-keys -t "${DEVICE_NAME}:2" "cros_sdk --nouse-image --no-ns-pid" C-m \
  "sudo servod --board=${DUT_board} --port=${DUT_servo_port} \
   --serial=${DUT_servo_serial}" C-m

tmux split-window -v -t "${DEVICE_NAME}:2" -e k="${kerneldir}"
tmux send-keys -t "${DEVICE_NAME}:2.1" \
  "while true; do \
  ~/trunk/src/platform/dev/contrib/dut-console -c ec --port=${DUT_servo_port}; \
  sleep 5; done" C-m

tmux split-window -h -t "${DEVICE_NAME}:2.1" -e SERVO_PORT="-p${DUT_servo_port}"

# Create and set up the AP UART window
tmux new-window -t "${DEVICE_NAME}:3" -e k="${kerneldir}"
tmux send-keys -t "${DEVICE_NAME}:3" \
  "while true; do \
  ~/trunk/src/platform/dev/contrib/dut-console -c cpu --port=${DUT_servo_port}; \
  sleep 5; done" C-m

# Set up a couple shells inside the chroot
for window in "${DEVICE_NAME}:4" "${DEVICE_NAME}:5"; do
  tmux new-window -t "${window}" -c "${CROS_DIRECTORY}"
  tmux send-keys -t "${window}" "cros_sdk --nouse-image --no-ns-pid" C-m
  tmux send-keys -t "${window}" \
    "export SERVO_PORT=-p${DUT_servo_port} PORT_SERVO=-p${DUT_servo_port} \
     SERVO_SERIAL=,serial=${DUT_ccd_serial} SERIAL_SERVO=,serial=${DUT_ccd_serial} \
     k=${kerneldir} BOARD=${DUT_board} IP=${DUT_ip}" C-m

done

if [ "${ATTACH}" = "yes" ]; then
  tmux a -t "${DEVICE_NAME}"
fi
