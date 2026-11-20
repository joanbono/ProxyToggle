#!/usr/bin/env bash
# Builds ProxyToggle.tipa (TrollStore) and proxyctl, both fake-signed with ProxyToggle.entitlements.
#   ./build.sh            build only
#   ./build.sh install    build, then install on the device over SSH (iproxy 2222 -> 22)
set -euo pipefail
cd "$(dirname "$0")"

SSH_PORT="${SSH_PORT:-2222}"
SSH_HOST="${SSH_HOST:-root@localhost}"
ENTITLEMENTS=ProxyToggle.entitlements
OUT=build

xcodegen generate --quiet
xcodebuild -project ProxyToggle.xcodeproj -scheme ProxyToggle -configuration Release \
  -sdk iphoneos -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet build

rm -rf "$OUT/Payload" "$OUT/ProxyToggle.tipa"
mkdir -p "$OUT/Payload"
cp -R "$OUT/DerivedData/Build/Products/Release-iphoneos/ProxyToggle.app" "$OUT/Payload/"
ldid -S"$ENTITLEMENTS" "$OUT/Payload/ProxyToggle.app/ProxyToggle"
(cd "$OUT" && zip -qry ProxyToggle.tipa Payload)

xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.0 -O \
  Sources/Shared/*.swift Tools/proxyctl/main.swift -o "$OUT/proxyctl"
ldid -S"$ENTITLEMENTS" "$OUT/proxyctl"

echo "built $OUT/ProxyToggle.tipa and $OUT/proxyctl"

if [[ "${1:-}" == "install" ]]; then
  scp -q -P "$SSH_PORT" "$OUT/ProxyToggle.tipa" "$SSH_HOST:/tmp/ProxyToggle.tipa"
  scp -q -P "$SSH_PORT" "$OUT/proxyctl" "$SSH_HOST:/tmp/proxyctl"
  ssh -p "$SSH_PORT" "$SSH_HOST" '
    set -e
    helper=$(ls /var/containers/Bundle/Application/*/TrollStore.app/trollstorehelper | head -1)
    "$helper" install /tmp/ProxyToggle.tipa
    mkdir -p /usr/local/bin && install -m 755 /tmp/proxyctl /usr/local/bin/proxyctl
    rm -f /tmp/ProxyToggle.tipa /tmp/proxyctl
  '
  echo "installed ProxyToggle (TrollStore) and /usr/local/bin/proxyctl"
fi
