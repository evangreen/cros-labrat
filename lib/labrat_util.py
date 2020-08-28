#!/usr/bin/env python3

import argparse
import json
import re
import os
import shlex
import sys
import time

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
  create-metadata -- Create a labrat test result summary.
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

  def create_metadata(self):
    parser = argparse.ArgumentParser(
      description='Create a labrat test metadata file. \
 Attributes are gathered from the results directory and LABRAT_TEST_* environment variables.')

    parser.add_argument("results", help="Path to the test results")
    parser.add_argument("output", help="Output path for the resulting json file.")
    args = parser.parse_args(sys.argv[2:])
    return create_metadata(args.results, args.output)

if __name__ == '__main__':
    LabratUtilityLibrary()
