; Negative fixture: an unknown scripts/dev subcommand exits 2.
; Run: `scripts/dev definitely-not-a-subcommand` from the repo root.
; Expected: stderr "scripts/dev: unknown subcommand: ...", exit 2.

; This file is a placeholder. The actual check is in
; `tests/unit/test-scripts-dev.sh`. It exists so the
; `scripts-dev-smoke-ok` obligation has a positive +
; negative fixture pair on disk.
