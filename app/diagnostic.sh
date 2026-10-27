#!/usr/bin/env bash
# diagnostic.sh - small Linux diagnostic CLI, made to run inside a container.
#
# Usage: diagnostic <command> [arguments]
#
# Exit codes:
#   0  success
#   1  operational/runtime failure (e.g. host does not resolve)
#   2  invalid command or input

set -u

PROG="diagnostic"

# ---------- helpers ----------

# print an error, show how to use the tool, and exit with code 2
invalid() {
    echo "Error: $1" >&2
    echo "Run '$PROG help' to see the available commands." >&2
    exit 2
}

# print one "label: value" line with the labels lined up
show() {
    printf '%-20s %s\n' "$1:" "$2"
}

# ---------- commands ----------

cmd_help() {
    cat <<EOF
Usage: $PROG <command> [arguments]

Commands:
  system           Show system information (host, user, OS, kernel, uptime, CPU, memory)
  help             Show this help message

Exit codes:
  0  success
  1  operational/runtime failure
  2  invalid command or input

Examples:
  docker run --rm diagnostic-tool system
EOF
}

get_os_name() {
    if [[ -r /etc/os-release ]]; then
        # subshell so the variables from os-release don't leak into the script
        ( . /etc/os-release; echo "${PRETTY_NAME:-${NAME:-unknown}}" )
    else
        uname -s
    fi
}

get_uptime() {
    # read /proc/uptime directly, works the same with busybox and coreutils
    local seconds
    seconds=$(cut -d. -f1 /proc/uptime)
    printf '%d days, %d hours, %d minutes\n' \
        $((seconds / 86400)) $((seconds % 86400 / 3600)) $((seconds % 3600 / 60))
}

get_cpu_model() {
    local model
    model=$(awk -F: '/^model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    echo "${model:-unknown}"
}

get_memory() {
    awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
         END {printf "%.1f GiB total, %.1f GiB available\n", t/1048576, a/1048576}' /proc/meminfo
}

cmd_system() {
    echo "=============================="
    echo "      System Information"
    echo "=============================="
    show "Hostname"          "$(hostname)"
    show "Current user"      "$(id -un 2>/dev/null || id -u)"
    show "Date/time"         "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    show "Operating system"  "$(get_os_name)"
    show "Kernel version"    "$(uname -r)"
    show "Architecture"      "$(uname -m)"
    show "Uptime"            "$(get_uptime)"
    show "CPU model"         "$(get_cpu_model)"
    show "CPU cores"         "$(nproc)"
    show "Memory"            "$(get_memory)"
    echo "=============================="
}

# ---------- main ----------

if [[ $# -lt 1 ]]; then
    invalid "no command given"
fi

command="$1"
shift

case "$command" in
    help|-h|--help)
        cmd_help
        ;;
    system)
        [[ $# -eq 0 ]] || invalid "'system' does not take any arguments"
        cmd_system
        ;;
    *)
        invalid "unknown command '$command'"
        ;;
esac
