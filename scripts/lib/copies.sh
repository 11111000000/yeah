#!/usr/bin/env bash
# scripts/lib/copies.sh — the copies of the runs of the method.
#
# The method works in a temporary directory of its own: `mathc-v5-<pid>-<n>'
# in the temporary directory of the machine.  The method removes that
# directory when it ends, and a killed process does not end: it leaves the
# directory and everything in it.  The measurement of 2026-11-18: forty-eight
# copies, about a gigabyte, left by the runs that were killed.
#
# The name of a copy holds the pid of the run that made it.  A copy whose
# run is gone is garbage, and a copy whose run is alive is the work of a
# run that is still going, and it must not be touched.  The sweep removes
# the first kind and leaves the second kind alone.
#
# The functions:
#   sweep_method_copies — remove the copies of the runs that are gone

sweep_method_copies() {
  local base="${TMPDIR:-/tmp}" dir name pid
  for dir in "$base"/mathc-v5-*; do
    [ -d "$dir" ] || continue
    name="${dir##*/}"
    pid="${name#mathc-v5-}"
    pid="${pid%%-*}"
    case "$pid" in
      ''|*[!0-9]*) continue ;;
    esac
    # The run is alive when its process is alive.  A pid that the kernel
    # gave to another process keeps the copy: the sweep is not the owner
    # of the copy, and a wrong guess would take the work of a live run.
    if [ ! -d "/proc/$pid" ]; then
      rm -rf "$dir"
    fi
  done
}
