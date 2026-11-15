#!/usr/bin/env bash
# check.sh - the report must name the exit code and the error of the command.
set -u

if [ ! -f report.txt ]; then
  echo "check: report.txt does not exist" >&2
  exit 1
fi

if ! grep -q "^exit-code:[[:space:]]*3[[:space:]]*$" report.txt; then
  echo "check: report.txt does not name the exit code 3" >&2
  exit 1
fi

if ! grep -q "cannot read settings.toml" report.txt; then
  echo "check: report.txt does not carry the error message of the command" >&2
  exit 1
fi

exit 0
