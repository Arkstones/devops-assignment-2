#!/usr/bin/env bash
# health-check.sh - quick self-check for the diagnostic tool.
# Makes sure the tools diagnostic.sh depends on exist and that the CLI answers.
# Run it inside the image to confirm the build is complete:
#   docker run --rm --entrypoint /app/health-check.sh diagnostic-tool
#
# Exit codes: 0 healthy, 1 something is missing or broken

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0

for tool in bash awk df hostname uname id date cut sort sed nproc; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "OK:   $tool found"
    else
        echo "FAIL: $tool is missing"
        failed=1
    fi
done

for file in /proc/cpuinfo /proc/meminfo /proc/uptime; do
    if [[ -r "$file" ]]; then
        echo "OK:   $file is readable"
    else
        echo "FAIL: $file cannot be read"
        failed=1
    fi
done

if "$SCRIPT_DIR/diagnostic.sh" help >/dev/null 2>&1; then
    echo "OK:   diagnostic.sh responds to 'help'"
else
    echo "FAIL: diagnostic.sh did not respond to 'help'"
    failed=1
fi

if (( failed )); then
    echo "Status: UNHEALTHY"
    exit 1
fi

echo "Status: HEALTHY"
exit 0
