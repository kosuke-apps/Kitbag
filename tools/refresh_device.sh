#!/bin/zsh
# Builds Kitbag signed for your iPhone and installs it over Wi-Fi, so that the seven-day signature of a free Apple ID is
# renewed without touching Xcode. Run it by hand, or let a launchd agent run it (tools/install_refresh_agent.sh).
#
#   tools/refresh_device.sh            renew when the last install is older than 4 days (what the agent runs)
#   tools/refresh_device.sh --force    renew now
#   tools/refresh_device.sh --check    say when it last ran and whether the phone answers; change nothing
#
# What it needs: the phone paired with this Mac for network use (Xcode > Window > Devices and Simulators > "Connect via
# network"), on the same Wi-Fi and awake, and your team in Config/Local.xcconfig. A signature only gets a new seven days
# when Xcode asks Apple for a new provisioning profile, and it only does that when the old one is gone, so the profile of
# this app is moved aside first (to the folder below, never deleted).
set -u

DEVICE="${KITBAG_DEVICE:-iPhone 12 Pro}"
BUNDLE_ID="dev.kosuke.kitbag"
MAX_AGE_DAYS="${KITBAG_MAX_AGE_DAYS:-4}"

ROOT="${0:A:h:h}"
STATE_DIR="$HOME/Library/Application Support/KitbagRefresh"
LAST_FILE="$STATE_DIR/last-install"
ASIDE_DIR="$STATE_DIR/old-profiles"
LOG="$HOME/Library/Logs/KitbagRefresh.log"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
DERIVED="$ROOT/build/DerivedDevice"
APP="$DERIVED/Build/Products/Debug-iphoneos/Kitbag.app"

mkdir -p "$STATE_DIR" "$ASIDE_DIR" "${LOG:h}"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }
notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Kitbag\"" >/dev/null 2>&1 || true
}

mode="due"
case "${1:-}" in
  --force) mode="force" ;;
  --check) mode="check" ;;
  "") ;;
  *) print "usage: ${0:t} [--force|--check]" >&2; exit 2 ;;
esac

last=0
[[ -f "$LAST_FILE" ]] && last="$(<"$LAST_FILE")"
now="$(date +%s)"
age_days=$(( (now - last) / 86400 ))

# Does the phone answer? A paired phone is listed even when it is asleep or on another network, so ask it something.
reachable() {
  xcrun devicectl device info details --device "$DEVICE" --timeout 20 >/dev/null 2>&1
}

if [[ "$mode" == "check" ]]; then
  if (( last == 0 )); then print "Never installed by this script."; else print "Last install: $(date -r "$last" '+%Y-%m-%d %H:%M') (${age_days} days ago)."; fi
  if reachable; then print "The phone answers."; else print "The phone does not answer (asleep, locked away, or on another network)."; fi
  exit 0
fi

if [[ "$mode" == "due" ]] && (( last > 0 )) && (( age_days < MAX_AGE_DAYS )); then
  exit 0   # not due yet; stay quiet, the agent runs often
fi

if ! reachable; then
  log "The phone ($DEVICE) does not answer; will try again on the next run."
  exit 1
fi

# Move this app's provisioning profile aside so that the build fetches a new one (seven fresh days).
if [[ -d "$PROFILES" ]]; then
  for file in "$PROFILES"/*.mobileprovision(N); do
    name="$(security cms -D -i "$file" 2>/dev/null | plutil -extract Name raw - 2>/dev/null)"
    if [[ "$name" == *"$BUNDLE_ID" ]]; then
      mv "$file" "$ASIDE_DIR/$(date +%Y%m%d-%H%M%S)-${file:t}"
      log "Moved the old provisioning profile aside: ${file:t}"
    fi
  done
fi

cd "$ROOT" || exit 1
log "Building for $DEVICE..."
if ! xcodebuild -project Kitbag.xcodeproj -scheme Kitbag -destination "platform=iOS,name=$DEVICE" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates build >"$STATE_DIR/build.log" 2>&1; then
  log "The build failed; see $STATE_DIR/build.log"
  notify "The build for your iPhone failed. See $STATE_DIR/build.log"
  exit 1
fi

log "Installing..."
if ! xcrun devicectl device install app --device "$DEVICE" "$APP" --timeout 120 >"$STATE_DIR/install.log" 2>&1; then
  log "The install failed; see $STATE_DIR/install.log"
  notify "Kitbag could not be installed on your iPhone. Is it awake and on the same Wi-Fi?"
  exit 1
fi

print "$now" >"$LAST_FILE"
log "Installed. The new signature lasts seven days."
notify "Kitbag was renewed on your iPhone for seven more days."
