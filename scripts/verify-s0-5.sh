#!/usr/bin/env bash
# S0-5 契约门禁：infra::paths 模块与 F-70 集成（实施计划 v2 第 7 节的规则原文）。
# 惯例与 verify-s0-4 / check-layering 一致：
#   - rules 与 expected_rule_pairs 互校，删规则即失败；
#   - --self-test 用变异体证明每条规则可证伪（该红的必红），诱饵样例证明不误报（该绿的必绿），
#     结构缺失 fail-closed。
set -uo pipefail

rules=(
  "R1|paths.rs 定义 config_dir / ensure_config_dir / ensure_dir_at 三件套"
  "R2|main.rs 实际调用 infra::paths::ensure_config_dir()（注释行不算）"
  "R3|paths.rs 的 #[cfg(test)] 区块使用 tempfile 注入（TempDir 或 tempdir()）"
  "R4|paths.rs 禁止对 config_dir() 返回值调用 remove_dir_all（防删真实用户数据目录）"
  "R5|分层子门禁 check-layering.sh 通过（委托既有脚本，不自行 grep fltk）"
)
expected_rule_pairs='R1 R2 R3 R4 R5'

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------- 规则一致性自检
declare -a RULE_IDS=()
for entry in "${rules[@]}"; do RULE_IDS+=("${entry%%|*}"); done
actual_sorted="$(printf '%s\n' "${RULE_IDS[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
expected_sorted="$(printf '%s\n' ${expected_rule_pairs} | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$actual_sorted" != "$expected_sorted" ]]; then
  echo "GATE-BROKEN: rules 与 expected_rule_pairs 不一致（改门禁必须两处同步）"
  echo "  rules 展开:   $actual_sorted"
  echo "  expected:     $expected_sorted"
  exit 1
fi

# ---------------------------------------------------------------- 工具函数
# 去掉整行 // 注释后的文本（已知代价与 check-layering 相同：行中注释不处理，
# 只可能少报不可能多报；R2/R4 的诱饵样例钉住行为）。
strip_comments() { sed 's|^[[:space:]]*//.*||' "$1"; }

FAILED=()
fail() { # $1=规则号 $2=原因
  FAILED+=("$1")
  echo "FAIL $1: $2"
}
pass() { echo "PASS $1"; }

# ---------------------------------------------------------------- 主检查
run_checks() {
  local root="$1"
  local paths_rs="$root/src/infra/paths.rs"
  local main_rs="$root/src/main.rs"

  # R1 三件套定义存在（文件缺失 fail-closed）
  if [[ ! -f "$paths_rs" ]]; then
    fail R1 "src/infra/paths.rs 不存在"
  elif ! grep -Eq 'pub[[:space:]]+fn[[:space:]]+config_dir[[:space:]]*\(' "$paths_rs" \
    || ! grep -Eq 'pub[[:space:]]+fn[[:space:]]+ensure_config_dir[[:space:]]*\(' "$paths_rs" \
    || ! grep -Eq '(^|[^[:alnum:]_])fn[[:space:]]+ensure_dir_at[[:space:]]*\(' "$paths_rs"; then
    fail R1 "paths.rs 缺 config_dir/ensure_config_dir/ensure_dir_at 定义之一"
  else
    pass R1
  fi

  # R2 组合根实际接线（注释里的调用不算）
  if [[ ! -f "$main_rs" ]]; then
    fail R2 "src/main.rs 不存在"
  elif strip_comments "$main_rs" | grep -q 'infra::paths::ensure_config_dir[[:space:]]*([[:space:]]*)'; then
    pass R2
  else
    fail R2 "main.rs 没有对 ensure_config_dir() 的实际调用（F-70 未接线或仅存在于注释）"
  fi

  # R3 测试注入真实生效：只看 #[cfg(test)] 之后的区块，且去注释（与 R2/R4 对称，
  # 否则残留注释里的 TempDir 字样会让"删掉注入"的变异体假装还是绿的——self-test M4 实测踩过）。
  if [[ ! -f "$paths_rs" ]]; then
    fail R3 "无法检查测试区块（paths.rs 不存在）"
  elif ! awk '/#\[cfg\(test\)\]/{found=1} found' "$paths_rs" | strip_comments /dev/stdin | grep -Eq 'TempDir|tempdir\('; then
    fail R3 "test 区块未使用 tempfile 注入（Sprint-Plan 验收：单测用临时目录）"
  else
    pass R3
  fi

  # R4 危险写法禁令：remove_dir_all 的参数里出现 config_dir
  if [[ ! -f "$paths_rs" ]]; then
    fail R4 "无法检查危险写法（paths.rs 不存在）"
  elif strip_comments "$paths_rs" | grep -Eq 'remove_dir_all\([^)]*config_dir'; then
    fail R4 "检测到对 config_dir() 返回值 remove_dir_all —— 会删用户真实数据目录"
  else
    pass R4
  fi

  # R5 分层：委托 check-layering.sh，不重复实现
  if [[ ! -x "$root/scripts/check-layering.sh" && ! -f "$root/scripts/check-layering.sh" ]]; then
    fail R5 "check-layering.sh 缺失，无法执行分层子门禁"
  elif out="$(bash "$root/scripts/check-layering.sh" 2>&1)"; then
    pass R5
  else
    fail R5 "check-layering.sh 变红: $(printf '%s' "$out" | tail -n 1)"
  fi
}

summary() {
  if ((${#FAILED[@]})); then
    printf '失败规则: %s\n' "$(printf '%s\n' "${FAILED[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
    exit 1
  fi
  printf '全部通过: %s\n' "$expected_rule_pairs"
  # 必须显式退出：self-test 会对副本再次调用本脚本，缺这行会穿透进 self-test 段无限递归
  #（首跑实测：副本 run 打印全部通过后继续执行 self-test，进程树以每层两个子进程指数增长）。
  exit 0
}

# ---------------------------------------------------------------- 入口分发
if [[ "${1:-}" == "--self-test" ]]; then
  ROOT_DEFAULT="${2:-.}"
else
  ROOT_DEFAULT="${1:-.}"
fi

cd "$ROOT_DEFAULT" || { echo "GATE-BROKEN: 无法进入 $ROOT_DEFAULT"; exit 1; }
REPO_ROOT="$PWD"

if [[ "${1:-}" != "--self-test" ]]; then
  run_checks "$REPO_ROOT"
  summary
fi

# ---------------------------------------------------------------- self-test
ST_TMP="$(mktemp -d)"
trap 'rm -rf "$ST_TMP"' EXIT
ST_PASS=0
ST_FAIL=0

make_copy() { # 复制门禁要看的东西：src 与 scripts
  rm -rf "$ST_TMP/repo"; mkdir -p "$ST_TMP/repo"
  cp -r "$REPO_ROOT/src" "$REPO_ROOT/scripts" "$ST_TMP/repo/"
}

# apply 的期望值："R1"（仅此红）/ "R1 R3 R4" / "GREEN"
check_case() { # $1=用例名 $2=期望失败集(排序空格分隔,GREEN=无失败)
  local name="$1" expect="$2" out got
  out="$(bash "$SCRIPT_PATH" "$ST_TMP/repo" 2>&1)"
  local rc=$?
  if grep -q '^全部通过' <<<"$out"; then got="GREEN";
  elif grep -q '^失败规则:' <<<"$out"; then
    got="$(grep '^失败规则:' <<<"$out" | sed 's/^失败规则: //; s/ $//')"
  else
    echo "ST-FAIL [$name]: 门禁未给出结构化汇总（fail-closed 视为红）"; ((ST_FAIL++)); return
  fi
  if [[ $expect == "GREEN" && $got == "GREEN" && $rc -eq 0 ]]; then
    echo "ST-OK   [$name]: 绿（无误报）"; ((ST_PASS++))
  elif [[ $got == "$expect" && $rc -ne 0 ]]; then
    echo "ST-OK   [$name]: 红于 {$got}"; ((ST_PASS++))
  else
    echo "ST-FAIL [$name]: 期望 {$expect} 实得 {$got} (rc=$rc)"; ((ST_FAIL++))
  fi
}

echo "== S0-5 门禁 self-test =="

# D3 基线：未变异副本必须全绿
make_copy; check_case "D3 基线未变异" "GREEN"

# M1: 删 pub fn config_dir 定义 → 仅 R1 红
make_copy; sed -i '/pub fn config_dir(/d' "$ST_TMP/repo/src/infra/paths.rs"
check_case "M1 删 config_dir 定义" "R1"

# M2: 删 ensure_dir_at 定义 → 仅 R1 红
make_copy; sed -i '/fn ensure_dir_at(path/d' "$ST_TMP/repo/src/infra/paths.rs"
check_case "M2 删 ensure_dir_at 定义" "R1"

# M3: 注释掉 main.rs 调用（注释诱饵）→ 仅 R2 红
make_copy; sed -i 's|^\( *\)if let Err(e) = infra::paths::ensure_config_dir|\1// if let Err(e) = infra::paths::ensure_config_dir|' "$ST_TMP/repo/src/main.rs"
check_case "M3 main.rs 调用被注释" "R2"

# M4: 测试区块去掉 TempDir 注入 → 仅 R3 红
make_copy; sed -i 's|tempfile::TempDir|tempfile::Placeholder|g' "$ST_TMP/repo/src/infra/paths.rs"
check_case "M4 测试不再用 tempdir 注入" "R3"

# M5: 插入对 config_dir() 的 remove_dir_all → 仅 R4 红
make_copy; sed -i 's|use std::fs;|use std::fs;\n    fn _danger() { let _ = std::fs::remove_dir_all(config_dir().unwrap()); }|' "$ST_TMP/repo/src/infra/paths.rs"
check_case "M5 删除真实配置目录的危险写法" "R4"

# M6: infra 层越界引用 fltk → 仅 R5 红（分层由子门禁把关）
make_copy; sed -i '1i use fltk::App;' "$ST_TMP/repo/src/infra/paths.rs"
check_case "M6 infra 越界依赖 fltk" "R5"

# M7: paths.rs 整体缺失 → fail-closed，R1/R3/R4 同红
make_copy; rm -f "$ST_TMP/repo/src/infra/paths.rs"
check_case "M7 模块文件缺失 fail-closed" "R1 R3 R4"

# D1: main.rs 注释里出现调用样式但真实调用健在 → 必绿
make_copy; printf '\n// 提醒：确保 infra::paths::ensure_config_dir() 已接线\n' >> "$ST_TMP/repo/src/main.rs"
check_case "D1 注释诱饵不误报(接线健在)" "GREEN"

# D2: paths.rs 末尾出现注释形态的危险写法 → 必绿（去注释后才检查）
make_copy; printf '\n// 禁止 std::fs::remove_dir_all(config_dir()) 这类写法\n' >> "$ST_TMP/repo/src/infra/paths.rs"
check_case "D2 注释形态危险写法不误报" "GREEN"

echo "== self-test 结果: PASS=$ST_PASS FAIL=$ST_FAIL =="
((ST_FAIL == 0)) || exit 1
