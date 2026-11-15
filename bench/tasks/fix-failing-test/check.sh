#!/usr/bin/env bash
# check.sh - the ERT test of the project is the judge.
set -u

emacs_bin="${EMACS:-emacs}"
"$emacs_bin" -Q --batch -L . -l calc-test.el -f ert-run-tests-batch-and-exit
