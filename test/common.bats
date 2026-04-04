#!/usr/bin/env bats
# common.bats — test shared helpers

bats_require_minimum_version 1.5.0

setup() {
  load test_helper
}

@test "hash_name produces consistent 12-char hex" {
  local hash
  hash="$(hash_name "my-module")"
  [ ${#hash} -eq 12 ]
  [[ "$hash" =~ ^[0-9a-f]{12}$ ]]
}

@test "hash_name is deterministic" {
  local h1 h2
  h1="$(hash_name "test-repo")"
  h2="$(hash_name "test-repo")"
  [ "$h1" = "$h2" ]
}

@test "hash_name differs for different inputs" {
  local h1 h2
  h1="$(hash_name "repo-a")"
  h2="$(hash_name "repo-b")"
  [ "$h1" != "$h2" ]
}
