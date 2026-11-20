# ProxyToggle

<img src="Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" align="right" alt="ProxyToggle icon">

SwiftUI app for jailbroken / TrollStore iOS devices that sets the system HTTP(S) proxy on every saved Wi-Fi network at once. Built for pointing a test device at Burp without digging through Settings for each network.

## Features

- One toggle to turn the system proxy on or off, with the active proxy shown live
- Apply to **all saved networks** or only the **current network**
- Profiles: manual host:port or PAC URL, plus a bypass list
- Profiles are saved in `/var/mobile/Library/Application Support/ProxyToggle/profiles.json`, so they survive reinstalls
- URL scheme for Shortcuts: `proxytoggle://on?profile=Burp`, `proxytoggle://off`, `proxytoggle://toggle`
- `proxyctl` command-line tool for use over SSH
- Changes apply within about a second, with no respring

## Compatibility

The app supports **iOS 16.0 and later** (deployment target 16.0, built with the iOS 27 SDK).

| iOS | Status |
|---|---|
| 17.5.1 (iPad 6th gen, palera1n rootful + TrollStore) | Tested |
| 16.x, 17.x | Expected to work |
| 18.x, 26.x, 27.x | Builds and should run, untested; limited by TrollStore and jailbreak availability |
| 15.x and earlier | Not supported |

Installing requires **TrollStore**, because the app needs private entitlements. TrollStore installs natively on iOS 14.0 – 16.6.1 and 17.0. On later versions it needs a jailbreak; for example, palera1n on checkm8 devices (A8 – A11) can install the TrollStore helper. On versions with neither, the app cannot be installed with its entitlements.

Rootful and rootless jailbreaks both work: the app does not touch `/var/jb`.

## Install

1. Download `ProxyToggle-<version>.ipa` from [Releases](../../releases).
2. Open it with TrollStore and tap **Install**.
3. Open ProxyToggle, edit the default **Burp** profile to point at your proxy, and turn the toggle on.

## How it works

iOS keeps one SystemConfiguration *Set* per Wi-Fi SSID (verified on iOS 17) in `/var/preferences/SystemConfiguration/preferences.plist`, each with its own `Proxies` dictionary. ProxyToggle writes the Wi-Fi and Ethernet services of every Set (or only the current one). Cellular and VPN services are left unchanged.

The SCPreferences API is marked unavailable in the iOS SDK, but the symbols ship in the iOS SystemConfiguration binary, so they are resolved with `dlsym`. The session is created with `SCPreferencesCreateWithAuthorization(..., kSCPreferencesUseEntitlementAuthorization)`. This makes configd's helper perform the write on behalf of a process holding the `com.apple.SystemConfiguration.SCPreferences-write-access` entitlement (see `ProxyToggle.entitlements`). Without that authorization, `SCPreferencesLock` fails with error 1003 when the app is not running as root.

## Build

Requires Xcode, `xcodegen` and `ldid` (`brew install xcodegen ldid`).

```sh
./build.sh            # build/ProxyToggle.tipa and build/proxyctl
./build.sh install    # also install on the device over SSH (iproxy 2222 -> 22)
```

`SSH_HOST` and `SSH_PORT` override the default `root@localhost:2222`.

To edit in Xcode, run `xcodegen generate && open ProxyToggle.xcodeproj`. Build in Xcode, but install with TrollStore: an Xcode install cannot grant the private entitlements.

## proxyctl

The same logic as a command-line tool, installed to `/usr/local/bin/proxyctl` by `./build.sh install`:

```sh
proxyctl status
proxyctl set 192.168.1.10 8080 [--current]
proxyctl pac http://192.168.1.10/proxy.pac [--current]
proxyctl off [--current]
proxyctl profiles
proxyctl use Burp [--current]
```

## Limitations

A system proxy is only a hint. Apps that ignore it (Flutter, apps with their own networking stack) send their traffic directly; use a VPN-based redirector for those.
