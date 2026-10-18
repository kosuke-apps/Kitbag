#!/bin/zsh
# Installs (or with --remove, removes) a launchd agent that runs tools/refresh_device.sh every hour. The script itself does
# nothing until the last install is four days old, then renews the app on the phone as soon as the phone answers.
#
# Installing over a running app closes it, so a renewal can interrupt Kitbag if it is open at that moment.
set -eu

LABEL="dev.kosuke.kitbag-refresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="${0:A:h}/refresh_device.sh"
LOG="$HOME/Library/Logs/KitbagRefresh.log"

if [[ "${1:-}" == "--remove" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  print "Removed $LABEL."
  exit 0
fi

mkdir -p "${PLIST:h}" "${LOG:h}"
cat >"$PLIST" <<PLIST_END
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$SCRIPT</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3600</integer>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_END

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
print "Installed $LABEL: it runs every hour and renews the app when it is four days old."
print "Log: $LOG"
