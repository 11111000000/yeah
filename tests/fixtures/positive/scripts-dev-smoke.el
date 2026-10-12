; Positive fixture: scripts/dev smoke returns 0.
; Run: `bash tests/unit/test-scripts-dev.sh` from the repo root.
; Expected: stdout "scripts/dev: smoke ok", exit 0.

; This file exists to anchor the fixture-pair obligation for
; the `scripts-dev-smoke-ok` obligation. The actual test is
; the bash script in `tests/unit/test-scripts-dev.sh`; this
; `.el` file is a placeholder for the future ERT harness.
