#!/usr/bin/env bash
# test.sh - tests for the diagnostic-tool Docker image.
#
# Usage:
#   ./test.sh                 build the image, then run all tests
#   SKIP_BUILD=1 ./test.sh    use an image that is already built
#   IMAGE=my-tag ./test.sh    test an image with a different name
#
# Exits 0 if every test passes, 1 if any test fails.

set -u

IMAGE="${IMAGE:-diagnostic-tool}"
PASSED=0
FAILED=0

# always run from the project folder so "docker build ." finds the Dockerfile
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed"
    exit 1
fi

# run_test <name> <allowed exit codes, e.g. "0" or "0|1"> <text the output must contain> <command...>
# use "" as the text when the output does not matter
run_test() {
    local name="$1"
    local expected_codes="$2"
    local expected_text="$3"
    shift 3

    local output rc
    output=$("$@" 2>&1)
    rc=$?

    if [[ "|$expected_codes|" != *"|$rc|"* ]]; then
        echo "FAIL: $name (exit code $rc, expected $expected_codes)"
        echo "$output" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
        return
    fi

    if [[ -n "$expected_text" ]] && ! grep -qi -- "$expected_text" <<< "$output"; then
        echo "FAIL: $name (output does not contain '$expected_text')"
        echo "$output" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
        return
    fi

    echo "PASS: $name"
    PASSED=$((PASSED + 1))
}

# ---------- build ----------

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    echo "Building image $IMAGE ..."
    if ! docker build -t "$IMAGE" . >/dev/null 2>&1; then
        echo "FAIL: docker build failed, run 'docker build -t $IMAGE .' to see the error"
        exit 1
    fi
    echo
fi

run() { docker run --rm "$IMAGE" "$@"; }

# ---------- help ----------
run_test "help shows usage"                    0 "Usage"            run help
run_test "--help works too"                    0 "Usage"            run --help
run_test "no command falls back to help (CMD)" 0 "Usage"            docker run --rm "$IMAGE"

# ---------- system ----------
run_test "system exits 0"                      0 "Hostname"         run system
run_test "system shows kernel version"         0 "Kernel"           run system
run_test "system shows memory"                 0 "Memory"           run system
run_test "system rejects extra arguments"      2 ""                 run system extra

# ---------- disk ----------
run_test "disk exits 0"                        0 "Disk usage"       run disk
run_test "disk with a path"                    0 "Path"             run disk /app
run_test "disk rejects a missing path"         2 "does not exist"   run disk /no/such/path

# ---------- network ----------
# 0 or 1: ping may be blocked depending on the network, but localhost must resolve
run_test "network localhost resolves"          "0|1" "127.0.0.1"    run network localhost
run_test "network without a host fails"        2 "needs a host"     run network
run_test "network rejects bad characters"      2 "not a valid"      run network "bad;host"
run_test "network rejects extra arguments"     2 ""                 run network localhost extra

# ---------- invalid input ----------
run_test "invalid command returns 2"           2 "unknown command"  run invalid-command
run_test "empty command returns 2"             2 ""                 run ""

# ---------- image checks ----------
run_test "container does not run as root"      0 "diag"             docker run --rm --entrypoint id "$IMAGE" -un
run_test "health-check passes in the image"    0 "HEALTHY"          docker run --rm --entrypoint /app/health-check.sh "$IMAGE"

# ---------- docker compose ----------
if docker compose version >/dev/null 2>&1; then
    run_test "compose config is valid"         0 ""                 docker compose config --quiet
    run_test "compose run system works"        0 "Hostname"         docker compose run --rm -T diagnostic system
else
    echo "SKIP: docker compose is not installed"
fi

# ---------- summary ----------
echo
echo "Passed: $PASSED"
echo "Failed: $FAILED"

[[ $FAILED -eq 0 ]]
