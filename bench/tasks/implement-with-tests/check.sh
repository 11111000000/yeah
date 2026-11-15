#!/usr/bin/env bash
# check.sh - both ERT files of the project are the judge.
set -u

emacs_bin="${EMACS:-emacs}"
"$emacs_bin" -Q --batch -L . -l stack-test.el -f ert-run-tests-batch-and-exit || exit 1
"$emacs_bin" -Q --batch -L . -l stack-depth-test.el -f ert-run-tests-batch-and-exit || exit 1

exit 0
