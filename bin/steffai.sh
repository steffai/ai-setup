#!/bin/bash

set -u
set -e

TARGET_USER="${TARGET_USER:-steffai}"
TARGET_LANG="C.UTF-8"

# ---- paths ----

LOCK_DIR="${XDG_RUNTIME_DIR}/steffai-${TARGET_USER}.instances"
INSTANCE_FILE=""

XAUTHORITY_FILE="${XDG_RUNTIME_DIR}/steffai-${TARGET_USER}.xauth"

SOCKET_PATH=""

# ---- instance tracking ----

register_instance() {
    mkdir -p "$LOCK_DIR"
    for f in "${LOCK_DIR}"/inst.*; do
        [ -f "$f" ] || continue
        pid="${f##*.}"
        kill -0 "$pid" 2>/dev/null || rm -f "$f"
    done
    INSTANCE_FILE="${LOCK_DIR}/inst.$$"
    : > "$INSTANCE_FILE"
}

cleanup() {
    rm -f "${INSTANCE_FILE}" 2>/dev/null || true
    rmdir "${LOCK_DIR}" 2>/dev/null && {
        echo "Cleaning up Wayland ACL permissions..."
        [ -n "$SOCKET_PATH" ] && setfacl -x u:"$TARGET_USER" "$SOCKET_PATH" 2>/dev/null || true
        setfacl -x u:"$TARGET_USER" "$XDG_RUNTIME_DIR" 2>/dev/null || true
        rm -f "${XAUTHORITY_FILE}" 2>/dev/null || true
    }
}

# ---- xauthority ----

setup_xauthority() {
    if [ ! -f "$XAUTHORITY_FILE" ]; then
        local tmp
        tmp=$(mktemp -p "${XDG_RUNTIME_DIR}" xauth-tmp.XXXXXXXXXX)
        xauth extract "$tmp" "$DISPLAY"
        if ! mv -n "$tmp" "$XAUTHORITY_FILE" 2>/dev/null; then
            rm -f "$tmp"
        fi
    fi
    setfacl -m u:"$TARGET_USER":r "$XAUTHORITY_FILE" 2>/dev/null || true
}

# ---- environment ----

GIT_NAME="$(git config user.name)"
GIT_EMAIL="$(git config user.email)"

TARGET_ENV=()
collect_env() {
    [ -v DISPLAY ] || { echo "Error: DISPLAY is not set." >&2; exit 1; }
    TARGET_ENV+=("DISPLAY=${DISPLAY}" "GIT_NAME=${GIT_NAME}" "GIT_EMAIL=${GIT_EMAIL}")

    if [ -v WAYLAND_DISPLAY ]; then
        TARGET_ENV+=("WAYLAND_DISPLAY=${WAYLAND_DISPLAY}")
        SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    fi
}

# ---- arguments ----

args=("$@")
resolve_args() {
    if [ ${#args[@]} -eq 0 ]; then
        args=("bash" "--login")
    elif [ "${args[0]}" = "opencode" ]; then
        local home
        home=$(eval echo "~${TARGET_USER}")
        args[0]="${home}/.opencode/bin/opencode"
    fi
}

# ---- acls ----

grant_acls() {
    setfacl -m u:"$TARGET_USER":x "$XDG_RUNTIME_DIR"
    [ -n "$SOCKET_PATH" ] && setfacl -m u:"$TARGET_USER":rw "$SOCKET_PATH"
}

# ---- launch ----

launch() {
    echo "Launching environment for OpenCode as user '$TARGET_USER'"
    if [ -v WAYLAND_DISPLAY ]; then
        echo "Wayland socket: ${SOCKET_PATH}"
        echo "To run Wayland programs, set:"
        echo "  export XDG_RUNTIME_DIR=\"\${SUDO_XDG_RUNTIME_DIR}\""
    fi
    sudo -u "$TARGET_USER" \
        "${TARGET_ENV[@]}" \
        SUDO_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
        SUDO_WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
        XAUTHORITY="${XAUTHORITY_FILE}" \
        LANG="${TARGET_LANG}" \
        ssh-agent \
        "${args[@]}"
}

# ---- main ----

register_instance
trap cleanup EXIT
collect_env
setup_xauthority
resolve_args
grant_acls
launch
