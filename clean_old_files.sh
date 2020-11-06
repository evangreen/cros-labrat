#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Wrap tast run, generate metadata, and upload results.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Clean up old image and firmware downloads.
Run tast run on a single remote, generate metadata, and upload results.
Options are:
  --days=n -- Delete labrat files older than n days. Default 14.
  --dry-run -- List the files that would be deleted, but don't delete.
  --delete-results -- Also delete old test results.
Example (deletes firmware download more than a week ago):
./clean_old_files.sh --days=7
"

DAYS=14
DELETE_IMAGES=yes
DELETE_FIRMWARE=yes
DELETE_INDICES=no
DELETE_RESULTS=no
DRY_RUN=no

while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
  --days=*)
    DAYS="${arg#*=}"
    shift
    ;;

  --dry-run)
    DRY_RUN=yes
    shift
    ;;

  --delete-results)
    DELETE_RESULTS=yes
    DELETE_INDICES=yes
    shift
    ;;

  --help)
    echo "$USAGE"
    exit 1
    ;;

  *)
    echo "Error: Unknown argument ${arg}"
    exit 1
    ;;
  esac
done

if [ "$#" -ne 0 ]; then
  echo "Error: Expected no arguments."
  exit 1
fi

# Delete files older than $DAYS days in the directory
# passed in.
delete_old_files() {
  local dest="$1"
  local action="-print"

  [ "${DRY_RUN}" = "no" ] && action="-delete"
  if ! [ -d "${dest}" ]; then
    echo "Skipping ${dest}: Not a directory"
    exit
  fi

  find "${dest}" -mtime "+${DAYS}" $action
}

if [ "${DELETE_IMAGES}" = "yes" ]; then
  delete_old_files "${LABRAT_IMAGE_CACHE}"
fi

if [ "${DELETE_FIRMWARE}" = "yes" ]; then
  delete_old_files "${LABRAT_FIRMWARE_CACHE}"
fi

if [ "${DELETE_INDICES}" = "yes" ]; then
  delete_old_files "${LABRAT_INDEX_CACHE}"
fi

if [ "${DELETE_RESULTS}" = "yes" ]; then
  delete_old_files "${LABRAT_RESULTS_CACHE}"
fi
