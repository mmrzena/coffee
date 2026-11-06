#!/usr/bin/env bash
# Lets Coffee keep the Mac awake with the lid closed. Installs a sudoers rule that allows you to
# run exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password, and
# nothing else. The rule must match the arguments in Coffee.swift's setSystemSleepDisabled.
# Undo: turn off "Stay Awake With Lid Closed" (or quit Coffee), then sudo rm /etc/sudoers.d/coffee
set -euo pipefail

SUDO=/usr/bin/sudo
RULE=/etc/sudoers.d/coffee

# The real user. SUDO_USER is only trusted when we really are running under sudo.
if [[ $EUID -eq 0 ]]; then USER_NAME="${SUDO_USER:-}"; else USER_NAME="$(/usr/bin/id -un)"; fi
if [[ -z $USER_NAME || $USER_NAME == root || $USER_NAME == ALL || ! $USER_NAME =~ ^[A-Za-z0-9._-]+$ ]] \
	|| ! /usr/bin/id -u "$USER_NAME" >/dev/null 2>&1; then
	echo "Run this as your own user, not root (got: '${USER_NAME}')." >&2
	exit 1
fi
LINE="$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"

# Stage the file root-owned from the start, so nothing running as you can swap it between the
# syntax check and the install. sudo ignores sudoers.d names containing a dot, so the staged
# file isn't live until it's renamed.
$SUDO /bin/mkdir -p /etc/sudoers.d
STAGE="$($SUDO /usr/bin/mktemp /etc/sudoers.d/.coffee.XXXXXX)"
trap '$SUDO /bin/rm -f "$STAGE"' EXIT
printf '%s\n' "$LINE" | $SUDO /usr/bin/tee "$STAGE" >/dev/null
$SUDO /usr/sbin/visudo -cf "$STAGE" >/dev/null # a broken sudoers file can lock you out of sudo
$SUDO /usr/sbin/chown root:wheel "$STAGE"
$SUDO /bin/chmod 0440 "$STAGE"
$SUDO /bin/mv "$STAGE" "$RULE"
echo "Installed $RULE for $USER_NAME"
