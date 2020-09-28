#!/usr/bin/env python3

import argparse
import json
import re
import os
import shlex
import sys
import time
import zipfile

def lock_file(path, pid):
  if pid is None:
    pid = os.getppid()

  count = 0
  while True:
    try:
      with open(path, 'x') as f:
        f.write(str(pid))

      break

    except FileExistsError:
      count += 1
      # Let the user know after about a minute in case it's stale.
      if (count % 120) == 0:
        owner = "unknown"
        try:
          with open(path, 'r') as f:
            owner = f.readline()
        except FileNotFoundError:
          pass

        print("Waiting for lock %s: owned by %s" % (path, owner))
    time.sleep(0.5)
  return

def unlock_file(path):
  os.remove(path)
  return

def load_config(config_path):
  with open(config_path, 'r') as f:
    return json.load(f)

  return None

def get_gs_bucket(config_path):
  config = load_config(config_path)
  bucket = config['gs_bucket']
  if bucket.endswith('/'):
    bucket = bucket.rstrip('/')
  print("%s" % bucket)
  return 0

def get_dut_count(config_path):
  config = load_config(config_path)
  print("%d" % len(config['machines']))
  return 0

def get_dut_sh(config_path, index):
  config = load_config(config_path)
  result = ''
  if index > len(config['machines']):
    return 1

  machine = config['machines'][index]
  for key in machine.keys():
    # Never run this over a config file you didn't write yourself.
    result += 'DUT_%s="%s"\n' % \
              (shlex.quote(key), shlex.quote(machine[key]))

  print(result)
  return 0

def list_tests(config_path, name):
  config = load_config(config_path)
  try:
    tests = config[name]
    for element in tests:
      print(element)

  except KeyError:
    pass

  return 0

def list_tasts(config_path):
  return list_tests(config_path, 'tast')

def list_autotests(config_path):
  return list_tests(config_path, 'autotest')

def parse_autotest_results(resultfile, results):
  tests = []
  t = None
  for l in resultfile:

    # Skip anything that's not a result line.
    if not l.startswith('/tmp/test_that_results_'):
      print("SKIPPING %s" % l)
      continue

    # Split the test path out from the rest.
    testpath, content = l.strip().split(None, 1)
    testname = \
        re.sub(r'/tmp/test_that_results_[^/]*/results-\d-','', testpath)

    content = content.strip()
    if content == '[  PASSED  ]' or content == '[  FAILED  ]':
      t = {
        "name": testname
      }

      if content == '[  PASSED  ]':
        t["result"] = "PASS"
      else:
        t["result"] = "FAIL"

      tests.append(t)

    else:
      if testname != t["name"]:
        print("Warning appending notes for '%s' to test '%s'" % \
              [testname, t["name"]])

      try:
        t["notes"].append(content)
      except KeyError:
        t["notes"] = [content]

  for t in tests:
    try:
      t["notes"] = "\n".join(t["notes"])
    except KeyError:
      pass

  results["tests"] = tests
  return

def parse_tast_results(resultfile, results):
  resultjson = json.load(resultfile)
  tests = []
  for tast in resultjson:
    # TODO: Use the start/end times in this dict, as they're a lot
    # more accurate than our overall timestamps.
    t = {
      "name": tast["name"]
    }

    if tast["skipReason"] != "":
      t["result"] = "SKIP"
      t["notes"] = tast["skipReason"]

    elif tast["errors"] is None:
      t["result"] = "PASS"

    else:
      t["result"] = "FAIL"
      errlist = []
      for error in tast["errors"]:
        errlist.append(error["reason"])
      t["notes"] = "\n".join(errlist)

    tests.append(t)

  results["tests"] = tests
  return

def parse_test_results(results_dir, results):
  autotestreport = '%s/test_report.log' % results_dir
  tastresults = '%s/results.json' % results_dir
  if os.path.exists(autotestreport):
    with open(autotestreport, 'r') as f:
      parse_autotest_results(f, results)

  elif os.path.exists(tastresults):
    with open(tastresults, 'r') as f:
      parse_tast_results(f, results)

  else:
    print("No test results were found in directory: %s" % results_dir)
    return 1

  return 0

# Create the metadata that goes in each uploaded test run.
# Gather the dict from environment keys that start with LABRAT_TEST_*
def create_metadata(results_dir, output_path):
  results = {}

  parse_test_results(results_dir, results)

  # Gather up the labrat keys from the environment.
  # Any environment variable that starts with LABRAT_TEST_
  # gets converted into a dictionary entry. Go bananas!
  for key in os.environ.keys():
    if key.startswith("LABRAT_TEST_"):
      jskey = key[12:].lower()
      results[jskey] = os.environ[key]
      if key.endswith("TIME"):
        results[jskey] = int(os.environ[key])

  # Save the results.
  with open(output_path, 'w') as f:
    f.write(json.dumps(results, indent=2))

  return

empty_index = {
  "version": 1,
  "files": [],
  "results": []
}

# Helper: List all the files covered in an index.
def print_index_files(index_path):
  index = empty_index
  if index_path is None or index_path == "":
    return 0

  with open(index_path, 'r') as f:
    index = json.load(f)

  for f in index['files']:
    print(f)

  return 0

copy_keys = ["user", "board", "hwid", "variant",
             "os", "fw", "command", "remote",
             "starttime", "endtime"]

# Grab a metadata file from a previous test run and add
# it to the rubber band ball.
def add_result_to_index(index, path, file_name):
  try:
    metadata = {}
    with zipfile.ZipFile(path, 'r') as z:
      for member in z.namelist():
        if member.endswith('labrat.json'):
          with z.open(member) as f:
            metadata = json.load(f)

          break

    new_results = []
    for r in metadata["tests"]:
      for key in copy_keys:
        r[key] = metadata[key]

      r['file'] = file_name
      new_results.append(r)

    index['files'].append(os.path.basename(path))
    index['results'] += new_results

  except Exception as e:
    print("Got exception with file %s: %s" % (path, e))

  return

# Rebuild a new index file.
def build_new_index(old_path, list_path, out_path, results_dir):
  index = empty_index
  if old_path is not None and old_path != "":
    with open(old_path, 'r') as f:
      index = json.load(f)

  with open(list_path, 'r') as f:
    for line in f:
      line = line.strip()
      if results_dir is not None:
        path = "%s/%s" % (results_dir, line)

      else:
        path = line

      add_result_to_index(index, path, line)

  with open(out_path, 'w') as f:
    json.dump(index, f, indent=1)

  return 0

# Convert the argparse filter list like ["result=PASS"] into a filter dict
# like {'result': 'PASS'}
def create_filter(filter):
  filter_dict = {}
  if filter is None:
    return filter

  for element in filter:
    keyvalue = element.split('=', 1)
    filter_dict[keyvalue[0]] = keyvalue[1]

  return filter_dict

# Filter the index to contain elements that match the filter.
def filter_results(index, filter):
  results = []

  if filter is None:
    return index

  for result in index:
    match = True
    for key in filter:
      if result[key] != filter[key]:
        match = False
        break

    if match:
      results.append(result)

  return results

# Squash results such that only the latest run per-test is shown.
def squash_by_name(index):
  sorted_index = sorted(index, key = lambda i: i['endtime'])
  squashed_index = []
  latest_name = {}

  sorted_index.reverse()
  for r in sorted_index:
    key = '%s+%s' % (r['name'], r['hwid'])
    latest = latest_name.get(key)
    if latest is None:
      squashed_index.append(r)
      latest_name[key] = r

  squashed_index.reverse()
  return squashed_index

default_columns = ['starttime', 'result', 'name', 'variant', 'os']

def print_results_table(index, columns):
  lengths = {}
  istty = os.isatty(1)

  for column in columns:
    lengths[column] = len(column)

  index = sorted(index, key = lambda i: i['endtime'])
  for result in index:
    for column in columns:
      try:
        value = result[column]
        if column == 'starttime' or column == 'endtime':
          value = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(value))

        value = str(value)

        # Expand the column size if needed. Don't do it for notes,
        # It just looks ridiculous.
        if column != 'notes' and len(value) > lengths[column]:
          lengths[column] = len(value)

        if istty and column == 'result':
          color = '37'
          if value == 'PASS':
            color = '32'

          elif value == 'FAIL':
            color = '31'

          value = "\x1b[%sm%s\x1b[0m" % (color, value)

      except (KeyError, ValueError):
        value = '-'

      result[column] = value

  # Now print the table.
  line = []
  for column in columns:
    line.append(column.ljust(lengths[column]))

  # Account for all the escape characters we use to color the result
  try:
    if istty:
      lengths['result'] += 9

  except KeyError:
    pass

  line = " ".join(line)
  print(line)
  print("-" * len(line))
  for result in index:
    line = []
    for column in columns:
      line.append(result[column].ljust(lengths[column]))

    print(" ".join(line))

  return 0

# Process an index and print it.
def show_index_results(index_path, args):
  index = None
  with open(index_path, 'r') as f:
    index = json.load(f)

  # Filter the results
  results = filter_results(index['results'], create_filter(args.filter))

  # Squash into latest for each test name if desired
  if args.latest:
    results = squash_by_name(results)

  if args.count:
    print(len(results))
    return 0

  if args.json:
    # Columns don't currently apply to JSON, you probably wanted everything.
    print(json.dumps(results, indent=1))

  else:
    columns = args.columns
    if columns is None:
      columns = default_columns

    else:
      columns = columns.split(",")

    print_results_table(results, columns)

  return 0

class LabratUtilityLibrary:
  def __init__(self):
    parser = argparse.ArgumentParser(
        description='Plumbing utilities for labrat',
        usage='''labrat_util.py <command> ...

Commands are:
  lock - Acquire a lock file.
  unlock - Release a lock file.
  get-gs-bucket -- Returns the gs:// path labrat should use.
  get-dut-count -- Returns the number of machines in the config.
  get-dut-sh -- Returns shell code describing attributes of a machine.
  get-tasts -- Return a list of tast tests in the given config
  get-autotests -- Return a list of autotests in the given config.
  create-metadata -- Create a labrat test result summary.
  list-index-files -- Show the files covered by an index.
  build-index -- Build a new index file.
  show-results -- Print out results.
''')
    parser.add_argument("command", help="The subcommand to run")
    args = parser.parse_args(sys.argv[1:2])
    command = args.command.replace("-", "_")
    if not hasattr(self, command):
      print('Unrecognized command')
      parser.print_help()
      exit(1)

    # Dispatch out to the method named the same as the command.
    getattr(self, command)()
    return

  def lock(self):
    parser = argparse.ArgumentParser(description='Acquire a lock file')
    parser.add_argument("path", help="path of the lock file to acquire")
    parser.add_argument("--pid",
      help="Owning pid of the lock file (defaults to parent PID)")

    args = parser.parse_args(sys.argv[2:])
    return lock_file(args.path, args.pid)

  def unlock(self):
    parser = argparse.ArgumentParser(description='Release a lock file')
    parser.add_argument("path", help="path of the lock file to acquire")

    args = parser.parse_args(sys.argv[2:])
    return unlock_file(args.path)

  def get_gs_bucket(self):
    parser = argparse.ArgumentParser(
      description='Print the labrat Google Storage bucket location')

    parser.add_argument("--config", help="Path to the config.json")
    args = parser.parse_args(sys.argv[2:])
    return get_gs_bucket(args.config)

  def get_dut_count(self):
    parser = argparse.ArgumentParser(
      description='Print the number of DUTs in the config')

    parser.add_argument("--config", help="Path to the config.json")
    args = parser.parse_args(sys.argv[2:])
    return get_dut_count(args.config)

  def get_dut_sh(self):
    parser = argparse.ArgumentParser(
      description='Get DUT attributes by index in the form of DUT_<var>=<value> shell vars.')

    parser.add_argument("--config", help="Path to the config.json")
    parser.add_argument("index", help="index into the list of machines to get", type=int)
    args = parser.parse_args(sys.argv[2:])
    return get_dut_sh(args.config, args.index)

  def get_tasts(self):
    parser = argparse.ArgumentParser(
      description='Print the set of tast tests in a config')

    parser.add_argument("--config", help="Path to the config.json")
    args = parser.parse_args(sys.argv[2:])
    return list_tasts(args.config)

  def get_autotests(self):
    parser = argparse.ArgumentParser(
      description='Print the set of autotest tests in a config')

    parser.add_argument("--config", help="Path to the config.json")
    args = parser.parse_args(sys.argv[2:])
    return list_autotests(args.config)

  def create_metadata(self):
    parser = argparse.ArgumentParser(
      description='Create a labrat test metadata file. \
 Attributes are gathered from the results directory and LABRAT_TEST_* environment variables.')

    parser.add_argument("results", help="Path to the test results")
    parser.add_argument("output", help="Output path for the resulting json file.")
    args = parser.parse_args(sys.argv[2:])
    return create_metadata(args.results, args.output)

  def list_index_files(self):
    parser = argparse.ArgumentParser(
      description='List all the result files covered by a given index')

    parser.add_argument("index_file", help="Path to the index file")
    args = parser.parse_args(sys.argv[2:])
    return print_index_files(args.index_file)

  def build_index(self):
    parser = argparse.ArgumentParser(
      description='Build a new index file by reading results')

    parser.add_argument("existing_index",
                        help="Path to an existing index to start with")

    parser.add_argument("file_list",
        help="Path to a file containing the set of results to index")

    parser.add_argument("output", help="Output path to create")
    parser.add_argument("--results-dir",
                        help="Path to prefix to each element in the file list")

    args = parser.parse_args(sys.argv[2:])
    return build_new_index(args.existing_index,
                           args.file_list,
                           args.output,
                           args.results_dir)

  def show_results(self):
    parser = argparse.ArgumentParser(
      description='Print out formatted or filtered results from an index file')

    parser.add_argument("index_path",
                        help="Path to the index file to load")

    parser.add_argument("--filter",
              help="Filter to only include results that match the given key.",
              action='append')

    parser.add_argument("--json",
                        help="Print the results in JSON form",
                        action='store_true')

    parser.add_argument("--latest",
                        help="Print only the latest instance of each test per-board",
                        action='store_true')

    parser.add_argument("--count",
                        help="Print only the count of matching results",
                        action='store_true')

    parser.add_argument("--columns", help="Define which columns to display")
    args = parser.parse_args(sys.argv[2:])
    return show_index_results(args.index_path, args)

if __name__ == '__main__':
    LabratUtilityLibrary()
