#!/bin/sh
# Run on the device with: ssh ... 'sh -s' < device-preflight.sh
# Read-only sampling; exit 0 means sampling completed, NOT deployment approval.
set -u
printf '%s\n' 'Phase 4E read-only device report; compatibility requires manual review.'
probe() {
    printf '\n[%s]\n' "$1"
    shift
    "$@"
    result=$?
    if [ "$result" -ne 0 ]; then printf 'UNAVAILABLE/FAILED (exit %s)\n' "$result"; fi
    return 0
}
probe identity id
probe kernel uname -smr
probe hardware sysctl -n hw.machine
probe system-version cat /System/Library/CoreServices/SystemVersion.plist
probe host-version cat /Applications/AppleTV.app/Info.plist
probe disk df -k / /private/var
probe mounts mount
probe tools sh -c 'for tool in dpkg dpkg-query tar shasum sha256sum openssl readlink launchctl stat du; do command -v "$tool" || :; done'
probe dpkg-version dpkg --version
probe dpkg-architecture dpkg --print-architecture
probe dpkg-audit dpkg --audit
probe package dpkg-query -W '-f=${Status} ${Package} ${Version} ${Architecture}\n' org.jellyfin.atv3
probe destination ls -ldn /Applications /Applications/AppleTV.app /Applications/AppleTV.app/Appliances /Applications/Jellyfin.frappliance /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
probe bundle-owner dpkg-query -S /Applications/Jellyfin.frappliance/Info.plist
probe link-owner dpkg-query -S /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
probe appliance-link readlink /Applications/AppleTV.app/Appliances/Jellyfin.frappliance
probe services launchctl list
printf '\n%s\n' 'Sampling complete. Missing commands/paths are recorded, not a PASS. No install/restart performed.'
