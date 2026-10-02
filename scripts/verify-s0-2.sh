#!/usr/bin/env bash
# S0-2 门禁：依赖清单落地 + 可复现构建。
# 供应链扫描（cargo audit）不在此脚本内：tech-plan §11.1 的 CI 三阶段没有它，且它依赖机器全局的
# cargo-audit 二进制与本地公告库路径，放进本脚本会让首次 clone 的开发者直接跑不过。移交 S0-4。
set -euo pipefail

cargo fmt --check
cargo build --locked
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings

# cargo tree -d 不以退出码表态，按输出长度断言
if [ -n "$(cargo tree -d --locked)" ]; then
    echo "发现重复依赖版本："
    cargo tree -d --locked
    exit 1
fi

grep -Eq '^serde = '               Cargo.toml
grep -Eq '^noyalib = \{ version = "0\.0\.51", features = \["compat-serde-yaml"\] \}' Cargo.toml
grep -Eq '^dirs = '                Cargo.toml
grep -Eq '^rust-version = '        Cargo.toml
grep -Eq '^pretty_assertions = '   Cargo.toml
grep -Eq '^\[dev-dependencies\]'   Cargo.toml

test -f Cargo.lock
grep -q '^name = "noyalib"'        Cargo.lock

# 已归档的 serde_yaml 不得回流。
# 注意：`set -e` 不因 `!` 前缀命令失败而退出（POSIX），必须写成显式 if 块，否则这条禁令是假绿。
if grep -Eq '^(serde_yaml|serde_yml) =' Cargo.toml; then
    echo "禁止依赖已归档的 serde_yaml / serde_yml"
    exit 1
fi

# YAML 能力必须真的被 import，否则构建通过也证明不了 API 可用。
# 只 grep 'noyalib' 会被 src/*/mod.rs 的头注释满足（注释里在列举禁用名），那是假绿。
if ! grep -rqE '^[[:space:]]*(pub[[:space:]]*)?use[[:space:]]+noyalib' src tests; then
    echo "noyalib 未被任何 import 行引用（注释不算）"
    exit 1
fi

echo "S0-2 verification passed"
