#!/bin/bash
# Screenshots of every screen, dark and light, from the iOS Simulator on GitHub's Mac. Each launch starts again from
# the demo data, opened on one screen (App/ScreenshotMode.swift). Output: screens/<look>-<screen>.png
set -euo pipefail
app=build/Build/Products/Debug-iphonesimulator/Track.app
id=com.nighth4wkg.track
python3 tools/demo-data.py > demo.json
xcrun simctl install "$UDID" "$app"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl launch "$UDID" "$id" > /dev/null; sleep 4; xcrun simctl terminate "$UDID" "$id" || true
data="$(xcrun simctl get_app_container "$UDID" "$id" data)/Library/Application Support"
mkdir -p "$data" screens
for look in dark light; do
  xcrun simctl ui "$UDID" appearance "$look"
  for screen in ${SCREENS:-home history detail progress rank workout recap settings confirm name}; do
    xcrun simctl terminate "$UDID" "$id" 2> /dev/null || true
    cp demo.json "$data/training.v1.json"
    xcrun simctl launch "$UDID" "$id" -screen "$screen" -track.storageMode local > /dev/null
    sleep 5
    xcrun simctl io "$UDID" screenshot "screens/$look-$screen.png" > /dev/null
    echo "screens/$look-$screen.png"
  done
done
