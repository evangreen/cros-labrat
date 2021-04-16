#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Update the AP firmware on a single running DUT via SSH.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

: "${CHANNEL:=dev-channel}"

USAGE="$0 [options]
Download and update the AP firmware on a single running DUT via SSH.
Options are:
  --remote=111.222.33.44 -- Specify the remote IP.
  --config=path_or_name -- Specify either absolute path to the .json config,
    or just the name, in which case it will be loaded from
    configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
  --email=someone@example.com -- Specify an optional autologin user.
    Will use autologin_email from the config if it exists.
  --password=S3cr3t -- Specify an optional autologin password. Don't use
    with accounts you care about, since this is usually saved in your
    shell history! Will use autologin_password from the config if it
    exists.
  --deverity -- Disable rootfs verification and reboot if necessary first.
  --no-creds -- Login without credentials.
"

deverity=no
use_creds=yes

for arg in "$@"; do
  case $arg in
  --config=*)
    CONFIG="${arg#*=}"
    shift
    ;;

  --remote=*)
    REMOTE="${arg#*=}"
    shift
    ;;

  --deverity)
    deverity=yes
    ;;

  --email=*)
    supplied_email="${arg#*=}"
    shift
    ;;

  --password=*)
    supplied_password="${arg#*=}"
    shift
    ;;

  --no-creds)
    use_creds=no
    shift
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
get_autologin_creds
[ -n "${supplied_email}" ] && autologin_email="${supplied_email}"
[ -n "${supplied_password}" ] && autologin_email="${supplied_password}"

if [ "${deverity}" = "yes" ]; then
  if do_ssh "${REMOTE}" "mount / -o remount,rw >/dev/null 2>&1"; then
    echo "Verity already disabled"

  else
    do_ssh "${REMOTE}" /usr/share/vboot/bin/make_dev_ssd.sh \
      --remove_rootfs_verification

    reboot_dut "${REMOTE}"
  fi
fi

creds_arg=
if [ -n "${autologin_email}" -a -n "${autologin_password}" ]; then
  if [ "${use_creds}" = yes ]; then
    creds_arg="-u ${autologin_email} -p ${autologin_password} "
  fi
fi

do_ssh "${REMOTE}" /usr/local/autotest/bin/autologin.py \
  -a --enable_default_apps ${creds_arg}
