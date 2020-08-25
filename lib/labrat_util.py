#!/usr/bin/env python3

import argparse
import json
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

import pprint

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

class LabratUtilityLibrary:
  def __init__(self):
    parser = argparse.ArgumentParser(
        description='Plumbing utilities for labrat',
        usage='''labrat_util.py <command> ...

Commands are:
  lock - Acquire a lock file.
  unlock - Release a lock file.
  get-dut-count -- Returns the number of machines in the config.
  get-dut-sh -- Returns shell code describing attributes of a machine.
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

if __name__ == '__main__':
    LabratUtilityLibrary()
