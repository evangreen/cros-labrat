#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Update the results index, and upload it.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Updates the results index based on previous results and new uploaded
tests in the GS bucket. This script downloads the latest index, downloads
any missing test results from the GS bucket, processes all results into
a master index, and then uploads the result.
Options are:
  --config=path_or_name -- Specify either absolute path to the .json config
    containing GS bucket, or just the name, in which case it will be
    loaded from configs/<name>.json. If unspecified, configs/default.json will
    be loaded if it exists.
  --no-rebuild -- Just download the latest index, but don't update it.
Example:
./update_index.sh --config=sample
"
rebuild=yes

while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
  --config=*)
    CONFIG="${arg#*=}"
    shift
    ;;

  --no-rebuild)
    rebuild=no
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
  echo "Error: Expected no arguments."
  exit 1
fi

load_config "$CONFIG"
download_latest_index
if [ "${rebuild}" = "no" ]; then
  echo "Latest index: ${LABRAT_INDEX_BEFORE}"
  exit 0
fi

download_unindexed_results
if [ -n "${LABRAT_UNINDEXED_LIST}" ]; then
  build_and_upload_index
fi
