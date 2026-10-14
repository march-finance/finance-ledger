#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_root=$(pwd)
IFS= read -r task_version < .march-version
task_compiler="${MARCH_COMPILER:-${HOME}/.march/versions/${task_version}/bin/march}"
if [ ! -x "$task_compiler" ]; then
  echo "Install pinned compiler with: forge toolchain install $task_version" >&2
  exit 1
fi
task_log=$(mktemp)
trap 'rm -f "$task_log"' EXIT HUP INT TERM
task_core_lib="${MARCH_CORE_LIB:-${HOME}/.march/cas/deps/finance-core/0.1.0/lib}"
if [ ! -d "$task_core_lib" ]; then
  echo "Run forge deps before contract checks (finance-core 0.1.0 is required)" >&2
  exit 1
fi
export MARCH_LIB_PATH="$task_root/lib:$task_core_lib"
# Ensure expected failures are not caused by broken module discovery.
"$task_compiler" --check fixtures/contracts/positive.march
check_rejected() {
  if "$task_compiler" --check "$1" > "$task_log" 2>&1; then
    echo "Expected rejection: $1" >&2
    exit 1
  fi
  if ! rg -q "$2" "$task_log"; then
    cat "$task_log" >&2
    exit 1
  fi
}
check_rejected fixtures/contracts/forged_validated.march unknown_constructor
check_rejected fixtures/contracts/forged_posted.march unknown_constructor
check_rejected fixtures/contracts/forged_ledger.march unknown_constructor
check_rejected fixtures/contracts/forged_posting.march unknown_constructor
check_rejected fixtures/contracts/unvalidated_post.march type_mismatch
echo "5 compile-time contract checks passed (and positive control accepted)"
