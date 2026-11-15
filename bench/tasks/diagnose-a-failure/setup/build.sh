#!/usr/bin/env bash
# build.sh - fails on purpose: the settings file is missing.
if [ ! -f settings.toml ]; then
  echo "build: error: cannot read settings.toml" >&2
  exit 3
fi
echo "build: ok"
