# Shared helpers for install.sh and desktop.sh. Source this file; do not run it.
#
# Dry-run: with DRY_RUN=1 (set by --dry-run / -n) every change goes through a helper below that
# prints what it WOULD do instead of doing it. Read-only checks (is X installed? is the marker
# already in the file?) still run, so the printed plan reflects the machine's real state.

DRY_RUN="${DRY_RUN:-0}"
export DRY_RUN

dry() { [[ $DRY_RUN == 1 ]]; }
would() { printf '  [dry-run] %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

# run <cmd...>: run a command, or only print it in dry-run mode.
run() {
    if dry; then would "$*"; else "$@"; fi
}

# append_once <file> <marker>: append stdin to <file> (creating it and its directory) unless a
# line equal to <marker> is already in the file.
append_once() {
    local file=$1 marker=$2
    if grep -qxF "$marker" "$file" 2>/dev/null; then
        if dry; then would "$file: already contains \"$marker\", nothing to do"; fi
        cat >/dev/null
        return 0
    fi
    if dry; then would "append to $file: $marker"; cat >/dev/null; return 0; fi
    mkdir -p "$(dirname "$file")"
    cat >> "$file"
}

# write_file <file>: overwrite <file> with stdin (creating its directory).
write_file() {
    local file=$1
    if dry; then would "write $file"; cat >/dev/null; return 0; fi
    mkdir -p "$(dirname "$file")"
    cat > "$file"
}

# sudo_write <file>: write stdin to a root-owned file.
sudo_write() {
    if dry; then would "write $1 (as root)"; cat >/dev/null; else sudo tee "$1" >/dev/null; fi
}
