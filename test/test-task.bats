#!/usr/bin/env bats

load test_helper
bats_require_minimum_version 1.5.0

setup() {
  export MODULES_CALLER_PWD="$BATS_TEST_TMPDIR/caller"

  MOCK_DIR="$BATS_TEST_TMPDIR/test-runner-bin"
  BATS_LOG="$BATS_TEST_TMPDIR/bats.log"
  mkdir -p "$MOCK_DIR" "$MODULES_CALLER_PWD"
  export BATS_LOG

  cat > "$MOCK_DIR/bats" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'jobs=%s\n' "${BATS_NUMBER_OF_PARALLEL_JOBS:-}"
  printf 'runner=%s\n' "${BATS_PARALLEL_BINARY_NAME:-}"
  for argument in "$@"; do
    printf 'arg=%s\n' "$argument"
  done
} > "$BATS_LOG"
SH

  cat > "$MOCK_DIR/rush" <<'SH'
#!/usr/bin/env bash
exit 0
SH

  chmod +x "$MOCK_DIR/bats" "$MOCK_DIR/rush"
  export BATS_COMMAND="$MOCK_DIR/bats"
  export RUSH_COMMAND="$MOCK_DIR/rush"
  unset BATS_NUMBER_OF_PARALLEL_JOBS BATS_PARALLEL_BINARY_NAME
}

log_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$BATS_LOG"
}

arg_count() {
  local expected="$1"
  awk -F= -v expected="$expected" '$1 == "arg" && substr($0, 5) == expected { count++ } END { print count + 0 }' "$BATS_LOG"
}

@test "test task defaults to eight Rush jobs without disabling within-file concurrency" {
  run modules test init --filter refuses
  [ "$status" -eq 0 ]
  [[ "$output" == *"8 jobs via"* ]]
  [ "$(log_value jobs)" = "8" ]
  [ "$(log_value runner)" = "$MOCK_DIR/rush" ]
  [ "$(arg_count --no-parallelize-within-files)" -eq 0 ]
  [ "$(arg_count "$REPO_DIR/test/init.bats")" -eq 1 ]
}

@test "option values cannot suppress the whitespace transport fallback" {
  target="$BATS_TEST_TMPDIR/parallel target/fixture file.bats"
  mkdir -p "$(dirname "$target")"
  printf '%s
' '#!/usr/bin/env bats' > "$target"

  run modules test "$target" --filter --no-parallelize-across-files
  [ "$status" -eq 0 ]
  [ "$(arg_count --no-parallelize-across-files)" -eq 2 ]
  [ "$(arg_count --no-parallelize-within-files)" -eq 0 ]
  [ "$(arg_count "$target")" -eq 1 ]
}

@test "explicit serial execution does not require Rush" {
  export RUSH_COMMAND="$MOCK_DIR/missing-rush"

  run modules test --jobs 1 init
  [ "$status" -eq 0 ]
  [[ "$output" == *"BATS parallelism: serial"* ]]
  [ "$(arg_count --no-parallelize-within-files)" -eq 0 ]
}

@test "parallel execution fails clearly without the selected runner" {
  export RUSH_COMMAND="$MOCK_DIR/missing-rush"

  run -127 modules test init
  [ "$status" -eq 127 ]
  [[ "$output" == *"parallel runner '$MOCK_DIR/missing-rush' is unavailable for 8 jobs"* ]]
  [ ! -e "$BATS_LOG" ]
}

@test "invalid job count fails before BATS" {
  export BATS_NUMBER_OF_PARALLEL_JOBS=lots

  run -2 modules test init
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
  [ ! -e "$BATS_LOG" ]
}

@test "public Modules test path runs tests within one BATS file concurrently" {
  probe_dir="$BATS_TEST_TMPDIR/within-file-probe"
  export PROBE_DIR="$BATS_TEST_TMPDIR/within-file-barrier"
  mkdir -p "$probe_dir" "$PROBE_DIR"

  test_keyword='@test'
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"first test observes second test\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/one"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/two" ] || return 0
    sleep 0.05
  done
  false
}
BATS
    printf '%s\n' "$test_keyword \"second test observes first test\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/two"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/one" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/within-file.bats"

  unset BATS_COMMAND RUSH_COMMAND
  unset BATS_NUMBER_OF_PARALLEL_JOBS BATS_PARALLEL_BINARY_NAME

  run modules test "$probe_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"8 jobs via"* ]]
}
