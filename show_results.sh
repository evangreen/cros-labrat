#!/bin/bash
# Copyright 2020 The Chromium OS Authors
# Show results.

set -e

_labrat_top="$(dirname "$0")"
. "${_labrat_top}/lib/helper_functions.sh"

USAGE="$0 [options]
Print out and potentially filter results collected in the latest local
index.
Options are:
  --filter=key=value -- Only show results whose result <key> matches the
    given <value>.
  --name=test_name -- Filter by test name, equivalent to
    --filter=name=<test_name>.
  --result=PASS|FAIL|SKIP -- Filter by result status, equivalent to
    --filter=result=value
  --latest -- Show only the latest run for a given test per-device.
  --json -- Show the results as JSON.
  --columns=starttime,name,result,os,fw,... -- Display only the given columns.
    If not supplied, defaults will be used.
  --index=/path/to/index.json -- Use the specified index file, rather than the
    latest downloaded one.
  --count -- Print only the count of results, not the results themselves.
For example, to show any tests whose most recent run per-board has failed:
./show_results.sh --latest --result=FAIL

To show all video.Capability results on a given machine:
./show_results.sh --name=video.Capability --filter="hwid=98:af:65:60:bb:70"
"
util_args=
index_path=

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
  --index=*)
    index_path="${arg#*=}"
    ;;

  --name=*|--result=*)
    util_args="${util_args} --filter=${arg%%=*}=${arg#*=}"
    ;;

  --help)
    echo "$USAGE"
    exit 1
    ;;

  *)
    util_args="${util_args} ${arg}"
    ;;
  esac
done

if [ -z "${index_path}" ]; then
  index_path="$(get_latest_local_index)"
  if [ -z "${index_path}" ]; then
    download_latest_index
    index_path="${LABRAT_INDEX_BEFORE}"
  fi
fi

"${_labrat_top}"/lib/labrat_util.py show-results "${index_path}" ${util_args}
