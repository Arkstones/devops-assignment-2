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
  network <host>   Resolve a host, ping it and show the network interfaces
  disk [path]      Show disk usage (default path: /)
  help             Show this help message

Exit codes:
  0  success
  1  operational/runtime failure
  2  invalid command or input

Examples:
  docker run --rm diagnostic-tool system
  docker run --rm diagnostic-tool network google.com
  docker run --rm diagnostic-tool disk
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

cmd_disk() {
    local path="${1:-/}"

    if [[ ! -e "$path" ]]; then
        invalid "path '$path' does not exist"
    fi

    # -P keeps each filesystem on one line so awk can read the columns safely
    local df_line
    df_line=$(df -P "$path" 2>/dev/null | awk 'NR == 2')
    if [[ -z "$df_line" ]]; then
        echo "Error: could not read disk usage for '$path'" >&2
        return 1
    fi

    echo "=============================="
    echo "       Disk Information"
    echo "=============================="
    show "Path"        "$path"
    show "Filesystem"  "$(echo "$df_line" | awk '{print $1}')"
    show "Mounted on"  "$(echo "$df_line" | awk '{print $6}')"
    show "Disk usage"  "$(echo "$df_line" | awk '{print $5}')"
    echo
    df -h "$path"
    echo "=============================="
}

# letters, numbers, dots, hyphens (hostnames/IPv4) and colons (IPv6) only,
# max 253 characters. Blocks spaces, ; $( ) and so on.
valid_host() {
    local host="$1"
    [[ -n "$host" ]] || return 1
    (( ${#host} <= 253 )) || return 1
    [[ "$host" =~ ^[A-Za-z0-9.:-]+$ ]] || return 1
    [[ "$host" != -* ]] || return 1
    return 0
}

# print the IP addresses for a host, one per line (empty if it does not resolve)
resolve_host() {
    local host="$1"
    local result=""
    if command -v getent >/dev/null 2>&1; then
        result=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u)
        # some getent versions only know "hosts"
        if [[ -z "$result" ]]; then
            result=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | sort -u)
        fi
    fi
    if [[ -z "$result" ]] && command -v nslookup >/dev/null 2>&1; then
        result=$(nslookup "$host" 2>/dev/null | awk '/^Address/ && NR > 2 {print $NF}' | sort -u)
    fi
    echo "$result"
}

show_interfaces() {
    if command -v ip >/dev/null 2>&1; then
        # -brief is nicer but busybox ip does not support it
        ip -brief address show 2>/dev/null || ip address show
    else
        for iface in /sys/class/net/*; do
            printf '%-12s %s\n' "$(basename "$iface")" "$(cat "$iface/operstate" 2>/dev/null)"
        done
    fi
}

cmd_network() {
    local host="$1"
    local failed=0

    echo "=============================="
    echo "        Network Check"
    echo "=============================="
    echo "Host: $host"
    echo

    echo "--- DNS resolution ---"
    local addresses
    addresses=$(resolve_host "$host")
    if [[ -z "$addresses" ]]; then
        echo "FAIL: could not resolve '$host'"
        return 1
    fi
    echo "Resolved addresses:"
    echo "$addresses" | sed 's/^/  /'
    echo

    echo "--- Connectivity (ping) ---"
    if ! command -v ping >/dev/null 2>&1; then
        echo "SKIP: ping is not installed"
    elif ping -c 2 -W 2 "$host" >/dev/null 2>&1; then
        echo "OK: $host replied to ping"
    else
        echo "FAIL: $host did not reply to ping (it may be down or blocking ICMP)"
        failed=1
    fi
    echo

    echo "--- Network interfaces ---"
    show_interfaces
    echo "=============================="

    if (( failed )); then
        return 1
    fi
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
    disk)
        [[ $# -le 1 ]] || invalid "'disk' takes at most one argument: [path]"
        cmd_disk "${1:-/}"
        ;;
    network)
        [[ $# -ge 1 ]] || invalid "'network' needs a host, e.g. '$PROG network google.com'"
        [[ $# -eq 1 ]] || invalid "'network' takes exactly one argument: <host>"
        valid_host "$1" || invalid "'$1' is not a valid hostname or IP address"
        cmd_network "$1"
        ;;
    *)
        invalid "unknown command '$command'"
        ;;
esac

# exit with the status of the command that just ran (0 = ok, 1 = runtime failure)
exit $?
