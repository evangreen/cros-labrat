# Copyright 2020 The Chromium OS Authors
#
# Labrat common library functions.
# This script is meant to be sourced into the environment, not run directly.

PS4='+($LINENO) '
# Define the root directory where labrat stores things
: "${LABRAT_ROOT:=$HOME/.labrat}"
: "${LABRAT_FIRMWARE_CACHE:=$LABRAT_ROOT/firmware}"
: "${LABRAT_IMAGE_CACHE:=$LABRAT_ROOT/images}"
if [ ! -d "${_labrat_top}" ]; then
  echo "Error: _labrat_top should be set"
  exit 2
fi

# Print the second to latest Chrome OS release build number, (since the
# latest one might be in-progress).
get_almost_latest_build_num () {
  local channel="$1"
  local board="$2"

  gsutil ls gs://chromeos-releases/${channel}/${board} | tail -n2 | \
    head -n1 | sed 's|[^[0-9]*/\([0-9.]*\)/|\1|'
}

# Print the remote firmware build path.
get_firmware_path () {
  local channel="$1"
  local board="$2"
  local build_number="$3"

  gsutil ls gs://chromeos-releases/${channel}/${board}/${build_number}/ChromeOS-firmware*
}

# Print the remote test image path.
get_test_image_path () {
  local channel="$1"
  local board="$2"
  local build_number="$3"

  gsutil ls gs://chromeos-releases/${channel}/${board}/${build_number}/ChromeOS-test-*
}

# Go download firmware from Goldeneye (or not if we've already done it).
# Saves the downloaded firmware path in DOWNLOADED_FIRMWARE_DIR
download_firmware () {
  local channel="$1"
  local board="$2"
  local build_number="$3"

  local firmware_dir="${LABRAT_FIRMWARE_CACHE}/${channel}-${board}-${build_number}"
  local firmware_archive="${firmware_dir}/firmware.tar.bz2"
  DOWNLOADED_FIRMWARE_DIR=
  if [ -f "${firmware_archive}" ]; then
    DOWNLOADED_FIRMWARE_DIR="${firmware_dir}"
    echo "Skipping download: ${firmware_archive} exists"
    return 0
  fi

  local remote_path="$(get_firmware_path "${channel}" "${board}" "${build_number}")"

  mkdir -p "${firmware_dir}"
  "${_labrat_top}/lib/labrat_util.py" lock "${firmware_archive}.lock"
  gsutil cp "${remote_path}" "${firmware_archive}.tmp"
  tar -C "${firmware_dir}" -xjf "${firmware_archive}.tmp"
  mv "${firmware_archive}.tmp" "${firmware_archive}"

  "${_labrat_top}"/lib/labrat_util.py unlock "${firmware_archive}.lock"
  DOWNLOADED_FIRMWARE_DIR="${firmware_dir}"
}

# Go download the test image from Goldeneye (or not if we've already done it).
# Saves the downloaded firmware path in DOWNLOADED_IMAGE_DIR
download_test_image () {
  local channel="$1"
  local board="$2"
  local build_number="$3"

  local dest_dir="${LABRAT_IMAGE_CACHE}/${channel}-${board}-${build_number}"
  local dest_archive="${dest_dir}/image.tar.xz"
  local dest_file="${dest_dir}/chromiumos_test_image.bin"
  DOWNLOADED_IMAGE_FILE=
  if [ -f "${dest_file}" ]; then
    DOWNLOADED_IMAGE_FILE="${dest_file}"
    echo "Skipping download: ${dest_file} exists"
    return 0
  fi

  local remote_path="$(get_test_image_path "${channel}" "${board}" "${build_number}")"

  mkdir -p "${dest_dir}"
  "${_labrat_top}/lib/labrat_util.py" lock "${dest_archive}.lock"
  gsutil cp "${remote_path}" "${dest_archive}"
  tar -C "${dest_dir}" -xJf "${dest_archive}"
  [ -f "${dest_file}" ] && rm "${dest_archive}"

  "${_labrat_top}"/lib/labrat_util.py unlock "${dest_archive}.lock"
  DOWNLOADED_IMAGE_FILE="${dest_file}"
}

# Run an SSH command on the DUT.
# Takes the remote as an argument, then passes the rest to SSH after --.
# Example: do_ssh 192.168.1.100 ls -la
do_ssh () {
  local remote="$1"

  shift
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" \
    -i ~/trunk/src/scripts/mod_for_test_scripts/ssh_keys/testing_rsa \
    -o LogLevel=error "root@${remote}" -- "$@"
}

# Helper function to run a general scp command.
# Adds the boilerplate arguments and passes everything else down.
do_scp () {
  scp -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" \
    -i ~/trunk/src/scripts/mod_for_test_scripts/ssh_keys/testing_rsa \
    -o LogLevel=error -- "$@"
}

# Copies a file to the DUT.
# Takes the remote, localpath, remotepath.
# Example: scp_to_dut 192.168.1.100 ./my_local_file.bin /tmp/file_on_dut.bin
scp_to_dut () {
  local remote="$1"
  local localpath="$2"
  local remotepath="$3"

  shift
  do_scp "${localpath}" "root@${remote}:${remotepath}"
}

# Copies a file from the DUT.
# Takes the remote, remotepath, localpath.
# Example: scp_to_dut 192.168.1.100 /tmp/file_on_dut.bin ./my_local_file.bin
scp_from_dut () {
  local remote="$1"
  local remotepath="$2"
  local localpath="$3"

  shift
  do_scp "root@${remote}:${remotepath}" "${localpath}"
}

# Detect the board name and print it.
detect_board () {
  local remote="$1"

  do_ssh "${remote}" "sed -n 's/CHROMEOS_RELEASE_BOARD=\(.*\)/\1/p' /etc/lsb-release"
}

# Detect the variant name and print it.
detect_variant () {
  local remote="$1"

  do_ssh "${remote}" mosys platform model
}

# Update the firmware on the DUT using SSH.
# Takes the remote, and local path to the firmware.
update_firmware () {
  local remote="$1"
  local fw_path="$2"

  scp_to_dut "${remote}" "${fw_path}" "/tmp/fw.bin"
  do_ssh "${remote}" futility update -i /tmp/fw.bin
}

# Update the OS image on the DUT using cros flash.
# Takes the remote and the path to the image.
update_os () {
  local remote="$1"
  local image_path="$2"

  cros flash "${remote}" "${image_path}"
}

# Load the config file by name or path. Sets LABRAT_CONFIG
# to the path of the config file.
load_config () {
  local config_name="$1"

  [ -z "${config_name}" ] && config_name=default

  # If it contains a slash, it's an absolute path.
  if echo "${config_name}" | grep -q / ; then
    LABRAT_CONFIG="${config_name}"
    return 0
  fi

  # Look for it in the configs directory.
  local config_path="${_labrat_top}/configs/${config_name}.json"
  if [ -f "${config_path}" ]; then
    LABRAT_CONFIG="${config_path}"
    return 0
  fi

  # Finally, just see if it exists, as a low priority.
  if [ -f "${config_name}" ]; then
    LABRAT_CONFIG="${config_name}"
    return 0
  fi

  echo "Error: Could not load config: ${config_name}"
  echo "Copy ${_labrat_top}/configs/sample.json to \
 ${_labrat_top}/configs/default.json, edit for your devices, and try again."

  LABRAT_CONFIG=
  return 1
}

# Run a labrat_util.py that takes a config.
do_labrat_config () {
  local command="$1"

  shift
  "${_labrat_top}"/lib/labrat_util.py "${command}" \
    --config="${LABRAT_CONFIG}" "$@"
}

# Returns the number of DUTs in the config.
get_dut_count () {
  do_labrat_config get-dut-count
}

# Load dict keys from a DUT at the given index into variables like
# DUT_<key>=<value>
get_dut_config () {
  index="$1"
  eval "$(do_labrat_config get-dut-sh $1)"
}
