# Copyright 2020 The Chromium OS Authors
#
# Labrat common library functions.
# This script is meant to be sourced into the environment, not run directly.

PS4='+($LINENO) '
# Define the root directory where labrat stores things
: "${LABRAT_ROOT:=$HOME/.labrat}"
: "${LABRAT_FIRMWARE_CACHE:=$LABRAT_ROOT/firmware}"
: "${LABRAT_IMAGE_CACHE:=$LABRAT_ROOT/images}"
: "${LABRAT_RESULTS_CACHE:=$LABRAT_ROOT/results}"
: "${LABRAT_INDEX_CACHE:=$LABRAT_ROOT/index}"

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
    # Touch the files so they're kept fresh and away from clean_old_files.sh.
    touch "${firmware_dir}"/*
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
    # Touch the file so it's kept fresh and away from clean_old_files.sh.
    touch "${dest_file}"
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

  do_ssh "${remote}" "crossystem | sed -n 's/^fwid[ ]*= Google_\([^.]*\).*/\1/p' | tr '[:upper:]' '[:lower:]'"
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

# Reboot the DUT and wait for it to come back.
# The first argument is the IP of the DUT. The second argument can be
# "yes" to perform a cold reboot rather than warm.
reboot_dut () {
  local remote="$1"
  local cold="$2"

  echo "Rebooting ${remote}"
  if [ "${cold}" = yes ]; then
    do_ssh "${remote}" "sync && ectool reboot_ec cold" &

  else
    do_ssh "${remote}" reboot
  fi

  sleep 15
  local try=0
  local trycount=10
  while [ "${try}" -lt "${trycount}" ]; do
    if detect_fw_version "${remote}"; then
      break
    fi

    sleep 10
    try="$((try+1))"
  done

  # Evaluate success or failure based on try count.
  [ "${try}" -lt "${trycount}" ]
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

# populates autologin_email and autologin_password with
# config values if supplied.
get_autologin_creds() {
  eval "$(do_labrat_config get-autologin-creds)"
}

# Returns the gs:// path to the shared bucket to use.
# You must have write access to this bucket.
get_gs_bucket () {
  do_labrat_config get-gs-bucket
}

# Load dict keys from a DUT at the given index into variables like
# DUT_<key>=<value>
get_dut_config () {
  eval "$(do_labrat_config get-dut-sh $1)"
}

# Get the list of tast tests in a config
get_tasts () {
  do_labrat_config get-tasts
}

# Get the list of autotest tests in a config
get_autotests () {
  do_labrat_config get-autotests
}

# Who is this person running the test.
whoisme () {
  [ -z "${LABRAT_TEST_USER}" ] &&
    export LABRAT_TEST_USER="$(git config --global user.email || whoami)"

  if [ "${LABRAT_TEST_USER}" = "root" -o \
       "${LABRAT_TEST_USER}" = "ubuntu" -o \
       -z "${LABRAT_TEST_USER}" ]; then

    LABRAT_TEST_USER="unknown"
  fi
}

# Returns the current time, in seconds since 1970.
get_timestamp () {
  date "+%s"
}

# Get the firmware version for the given remote.
detect_fw_version () {
  local remote="$1"

  do_ssh "${remote}" crossystem fwid
}

# Get the OS version for the given remote.
detect_os_version () {
  local remote="$1"

  do_ssh "${REMOTE}" \
    "sed -n 's/CHROMEOS_RELEASE_BUILDER_PATH=\(.*\)/\1/p' /etc/lsb-release"
}

# Get a hardware identifier for the machine (currently wlan0's MAC).
detect_hardware_id () {
  local remote="$1"

  do_ssh "${REMOTE}" "cat /sys/class/net/wlan0/address"
}

# Start metadata collection, save to some globals.
start_test () {
  local remote="$1"

  shift
  whoisme
  export LABRAT_TEST_REMOTE="${remote}"
  export LABRAT_TEST_COMMAND="$*"
  export LABRAT_TEST_BOARD="$(detect_board ${remote})"
  export LABRAT_TEST_VARIANT="$(detect_variant ${remote})"
  export LABRAT_TEST_OS="$(detect_os_version ${remote})"
  export LABRAT_TEST_FW="$(detect_fw_version ${remote})"
  export LABRAT_TEST_HWID="$(detect_hardware_id ${remote})"
  export LABRAT_TEST_STARTTIME="$(get_timestamp)"
  export LABRAT_TEST_ENDTIME=
}

# Finish collecting metadata.
end_test () {
  export LABRAT_TEST_ENDTIME="$(get_timestamp)"
}

# Run test_that, teeing the output to a file.
# Takes the remote as the first arg, then the extra args to pass to test_that.
run_test_that () {
  local remote="$1"

  shift

  # Save the output. Don't start it with LABRAT_TEST_ since we don't want it
  # saved in the results dict.
  LABRAT_OUTPUT="$(tempfile -p lbrat)"
  start_test "${remote}" test_that "${remote}" "$@"
  test_that "${remote}" "$@" 2>&1 | tee "${LABRAT_OUTPUT}" | \
    cat -n | sed "s/^/${remote} /" || true

  end_test
}

# Run tast run, teeing the output to a file.
# Takes the remote as the first arg, then the extra args to pass to test_that.
run_tast_run () {
  local remote="$1"

  shift

  # Save the output. Don't start it with LABRAT_TEST_ since we don't want it
  # saved in the results dict.
  LABRAT_OUTPUT="$(tempfile -p lbrat)"
  start_test "${remote}" tast run "${remote}" "$@"
  tast run "${remote}" "$@" 2>&1 | tee "${LABRAT_OUTPUT}" | \
    cat -n | sed "s/^/${remote} /" || true

  end_test
}

# Based on stdout from running test_that, find the results directory.
find_test_that_results () {
  local stdout_path="$1"

  sed -n \
    's/.*Finished running tests. Results can be found in \([^ ]*\) .*/\1/p' \
    "${stdout_path}"
}

# Based on stdout from running tast run, find the results directory.
find_tast_run_results () {
  local stdout_path="$1"

  sed -n \
    's/.*Results saved to \(.*\)/\1/p' \
    "${stdout_path}"
}

# Given a path to the /tmp/test_that_results_... directory, create a metadata
# file.
create_test_that_metadata () {
  results_dir="$1"
  metadata_file="$1/labrat.json"

  "${_labrat_top}"/lib/labrat_util.py create-metadata \
    "${results_dir}" "${metadata_file}"
}

# Given a path to the /tmp/tast/results/YYYYMMDD-HHmmss directory, create a metadata
# file.
create_tast_run_metadata () {
  results_dir="$1"
  metadata_file="$1/labrat.json"

  "${_labrat_top}"/lib/labrat_util.py create-metadata \
    "${results_dir}" "${metadata_file}"
}

# Archive the results directory, and upload it.
archive_results () {
  local results_dir="$1"

  local archive_name="$(date +%y%m%d%H%M%S)-${LABRAT_TEST_VARIANT}-$(whoami)-$(date +%N).zip"
  local archive_path="${LABRAT_RESULTS_CACHE}/${archive_name}"
  local bucket="$(get_gs_bucket)"

  mkdir -p "${LABRAT_RESULTS_CACHE}"
  zip -q -r "${archive_path}" "${results_dir}"
  gsutil cp "${archive_path}" "${bucket}/results/"
}

# Find the results, create the test metadata, upload the results.
sweep_test_that_results() {
  local results_dir="$(find_test_that_results "${LABRAT_OUTPUT}")"

  if [ ! -d "${results_dir}" ]; then
    echo "Error: Could not find test_that results. Check the output: ${LABRAT_OUTPUT}."
    return 1
  fi

  create_test_that_metadata "${results_dir}"
  archive_results "${results_dir}"
}

# Find the results, create the test metadata, upload the results.
sweep_tast_results() {
  local results_dir="$(find_tast_run_results "${LABRAT_OUTPUT}")"

  if [ ! -d "${results_dir}" ]; then
    echo "Error: Could not find tast results. Check the output: ${LABRAT_OUTPUT}."
    return 1
  fi

  create_tast_run_metadata "${results_dir}"
  archive_results "${results_dir}"
}

# Print the latest results file in the bucket.
get_latest_index() {
  local bucket="$(get_gs_bucket)"

  gsutil ls "${bucket}/index/*" | sort | tail -n1
}

# print the latest local index.
get_latest_local_index() {
  local latest="$(ls "${LABRAT_INDEX_CACHE}" | tail -n1)"

  [ -n "${latest}" ] && echo "${LABRAT_INDEX_CACHE}/${latest}"
}

# Downloads the latest index. Sets LABRAT_INDEX_BEFORE
# to the local path of the latest index on the server.
download_latest_index() {
  local latest_index="$(get_latest_index || true)"
  local latest_filename
  local latest_filepath

  LABRAT_INDEX_BEFORE=
  echo "LABRAT_INDEX_CACHE=$LABRAT_INDEX_CACHE"
  mkdir -p "${LABRAT_INDEX_CACHE}"
  [ -z "${latest_index}" ] && return
  latest_filename="$(basename "${latest_index}")"
  latest_filepath="${LABRAT_INDEX_CACHE}/${latest_filename}"
  if [ -f "${latest_filepath}" ]; then
    LABRAT_INDEX_BEFORE="${latest_filepath}"
    echo "Skipping download of ${latest_filepath}, already got it."
    return 0
  fi

  gsutil cp "${latest_index}" "${latest_filepath}"
  LABRAT_INDEX_BEFORE="${latest_filepath}"
}

# Download yet-to-be-indexed results from the server. Sets
# LABRAT_UNINDEXED_LIST to the path of a file containing all
# the results that need to be added to the index.
download_unindexed_results() {
  local bucket="$(get_gs_bucket)"
  local soupfile=$(mktemp)
  local unindexed

  LABRAT_UNINDEXED_LIST=
  if [ -f "${LABRAT_INDEX_BEFORE}" ]; then
    # Add the already indexed files twice so they never show up.
    "${_labrat_top}"/lib/labrat_util.py \
      list-index-files "${LABRAT_INDEX_BEFORE}" >>"${soupfile}"

    "${_labrat_top}"/lib/labrat_util.py \
      list-index-files "${LABRAT_INDEX_BEFORE}" >>"${soupfile}"
  fi

  # Add the available results.
  gsutil ls "${bucket}/results/*" | sed "s|${bucket}/results/||" >>"${soupfile}"

  sort "${soupfile}" | uniq -u > "${soupfile}.2"
  echo "ALL RESULTS:"
  cat "${soupfile}"
  echo
  echo "MISSING RESULTS:"
  cat "${soupfile}.2"
  mv "${soupfile}.2" "${soupfile}"
  unindexed="$(cat ${soupfile})"
  LABRAT_UNINDEXED_LIST="${soupfile}"

  if [ -z "${unindexed}" ]; then
    rm -f "${soupfile}"
    unset LABRAT_UNINDEXED_LIST
    echo "No new results were found, you're up to date!"
    return 0
  fi

  # Download the missing files.
  for f in ${unindexed}; do
    [ -f "${LABRAT_RESULTS_CACHE}/${f}" ] && continue
    echo "Downloading ${f}"
    gsutil cp "${bucket}/results/${f}" "${LABRAT_RESULTS_CACHE}/${f}"
  done
  return 0
}

# Build and upload a new index file.
build_and_upload_index() {
  local bucket="$(get_gs_bucket)"
  local newindex_name="$(date +%y%m%d-%H%M%S)-index.json"
  local newindex_path="${LABRAT_INDEX_CACHE}/${newindex_name}"

  "${_labrat_top}"/lib/labrat_util.py \
    build-index "${LABRAT_INDEX_BEFORE}" \
                "${LABRAT_UNINDEXED_LIST}" "${newindex_path}" \
                --results-dir="${LABRAT_RESULTS_CACHE}"

  gsutil cp "${newindex_path}" "${bucket}/index/${newindex_name}"

  # Delete the temporary unindexed file set.
  rm -f "${LABRAT_UNINDEXED_LIST}"
}