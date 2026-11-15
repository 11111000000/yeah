#!/usr/bin/env bash
# check.sh - the ERT test is the judge, and the built-in must be the one used.
set -u

emacs_bin="${EMACS:-emacs}"
"$emacs_bin" -Q --batch -L . -l text-test.el -f ert-run-tests-batch-and-exit || exit 1

if ! grep -q "string-trim" text.el; then
  echo "check: text.el does not use the built-in string-trim" >&2
  exit 1
fi

exit 0
