#!/usr/bin/env bash
set -euo pipefail

cargo fmt --check
cargo build
cargo test
cargo clippy --all-targets -- -D warnings

test -f Cargo.toml
test -f Cargo.lock
test -f rust-toolchain.toml
test -f src/main.rs
test -f src/app/mod.rs
test -f src/domain/mod.rs
test -f src/infra/mod.rs
test -f src/ui/mod.rs
test -f tests/.gitkeep

grep -q "mod app;" src/main.rs
grep -q "mod domain;" src/main.rs
grep -q "mod infra;" src/main.rs
grep -q "mod ui;" src/main.rs

echo "S0-1 verification passed"
