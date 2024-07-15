#!/bin/bash
#
# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# An end-to-end test for Skyfocus & working sets.

# --- begin runfiles.bash initialization ---
set -euo pipefail
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---

source "$(rlocation "io_bazel/src/test/shell/integration_test_setup.sh")" \
  || { echo "integration_test_setup.sh not found!" >&2; exit 1; }

function set_up_project_file() {
  mkdir -p test
  cat > test/BUILD <<EOF
genrule(name='test', outs=['test.txt'], cmd='echo hi > \$@')
EOF
  cat > test/PROJECT.scl <<EOF
configs = {
  "test_config": ['--define=foo=bar'],
}
supported_configs = {
  "test_config": "User documentation for what this config means",
}
EOF
}

function test_scl_config_plus_user_bazelrc_fails(){
  set_up_project_file
  echo "build --define=bar=baz" > ~/.bazelrc
  if [[ $(bazel build --nobuild //test:test --enforce_project_configs --scl_config=test_config &> $TEST_log) ]] then
    fail "Scl enabled build expected to fail with config flag in user bazelrc"
  fi
  expect_log "Found [--define=bar=baz]"
}

function test_scl_config_plus_passed_bazelrc_fails(){
  set_up_project_file
  add_to_bazelrc "build --define=bar=baz"
  cat .blazerc >> test/test.bazelrc
  if [[ $(bazel --blazerc=test/test.bazelrc build --nobuild //test:test --enforce_project_configs --scl_config=test_config --experimental_enable_scl_dialect &> $TEST_log) ]] then
    fail "Scl enabled build expected to fail with config flag in user bazelrc"
  fi
  expect_log "Found [--define=bar=baz]"
}

function test_scl_config_plus_starlark_in_passed_blazerc_fails(){
  set_up_project_file
  touch test/test.bzl
  cat >> test/test.bzl <<EOF
string_flag = rule(implementation = lambda ctx: [], build_setting = config.string(flag = True))
EOF
  cat >> test/BUILD <<EOF
load("//test:test.bzl", "string_flag")
string_flag(
    name = "starlark_flags_always_affect_configuration",
    build_setting_default = "default",
)
EOF
  add_to_bazelrc "build --//test:starlark_flags_always_affect_configuration=yes"
  cat .blazerc >> test/test.bazelrc
 if [[ $(bazel --blazerc=test/test.bazelrc build --nobuild //test:test --enforce_project_configs --scl_config=test_config --experimental_enable_scl_dialect &> $TEST_log) ]] then
    fail "Scl enabled build expected to fail with starlark flag in user bazelrc"
 fi
  expect_log "Found [--\/\/test:starlark_flags_always_affect_configuration=yes]"
}

function test_scl_config_plus_command_line_starlark_flag_fails(){
  set_up_project_file
  touch test/test.bzl
  cat >> test/test.bzl <<EOF
string_flag = rule(implementation = lambda ctx: [], build_setting = config.string(flag = True))
EOF
  cat >> test/BUILD <<EOF
load("//test:test.bzl", "string_flag")
string_flag(
    name = "starlark_flags_always_affect_configuration",
    build_setting_default = "default",
)
EOF
 if [[ $(bazel build --nobuild //test:test --enforce_project_configs --scl_config=test_config --//test:starlark_flags_always_affect_configuration=yes &> $TEST_log) ]]
 then
    fail "Scl enabled build expected to fail with starlark flag on command line"
  fi
  expect_log "Found [--\/\/test:starlark_flags_always_affect_configuration=yes]"
}

function test_scl_config_plus_workspace_bazelrc_passes(){
  set_up_project_file
  add_to_bazelrc "build --define=foo=bar"
  bazel build --nobuild //test:test --enforce_project_configs --scl_config=test_config \
  || fail "Scl enabled build expected to pass with config flag in global bazelrc"
}

function test_scl_config_plus_starlark_workspace_bazelrc_passes(){
  set_up_project_file
  touch test/test.bzl
  cat >> test/test.bzl <<EOF
string_flag = rule(implementation = lambda ctx: [], build_setting = config.string(flag = True))
EOF
  cat >> test/BUILD <<EOF
load("//test:test.bzl", "string_flag")
string_flag(
    name = "starlark_flags_always_affect_configuration",
    build_setting_default = "default",
)
EOF
  add_to_bazelrc "build --//test:starlark_flags_always_affect_configuration=yes"
  bazel build --nobuild //test:test --enforce_project_configs --scl_config=test_config \
  || fail "Scl enabled build expected to pass with starlarkconfig flag in global bazelrc"
}


run_suite "Integration tests for flagsets/scl_config"