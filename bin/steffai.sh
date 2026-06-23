#!/bin/bash

set -u
set -e

# Configuration
TARGET_USER="${TARGET_USER:-steffai}"

TARGET_LANG="C.UTF-8"

GIT_NAME="$(git config user.name)"
GIT_EMAIL="$(git config user.email)"

# Check environment variables
KEEP_VARS="DISPLAY GIT_NAME GIT_EMAIL WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR"
TARGET_ENV=()
for i in ${KEEP_VARS}; do
    if [ ! -v "${i}" ]; then
        echo "Error: variable ${i} is not set."
        exit 1
    fi
    TARGET_ENV+=("$i=${!i}")
done

SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

args=("$@")
if [ ${#args[@]} -eq 0 ]; then
    args=("bash" "--login")
elif [ "${args[0]}" = "opencode" ]; then
    HOME=$(eval echo "~${TARGET_USER}")
    args[0]="${HOME}/.opencode/bin/opencode"
fi

# Define cleanup function to revoke permissions on exit
cleanup() {
    echo "Cleaning up Wayland ACL permissions..."
    setfacl -m u:"$TARGET_USER" "$XAUTHORITY" 2>/dev/null || true
    setfacl -x u:"$TARGET_USER" "$SOCKET_PATH" 2>/dev/null || true
    setfacl -x u:"$TARGET_USER" "$XDG_RUNTIME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Grant explicit access ONLY to the target user using ACLs
setfacl -m u:"$TARGET_USER":x  "$XDG_RUNTIME_DIR"
setfacl -m u:"$TARGET_USER":rw "$SOCKET_PATH"
setfacl -m u:"$TARGET_USER":r  "$XAUTHORITY"

echo "Launching environment for OpenCode as user '$TARGET_USER'"
sudo -u "$TARGET_USER" \
    "${TARGET_ENV[@]}" \
    LANG="${TARGET_LANG}" \
    ssh-agent \
    "${args[@]}"
