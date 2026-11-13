<div align="center">
    <img src="Ice/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Ice for macOS 27</h1>
</div>

A personal fork of [jordanbaird/Ice](https://github.com/jordanbaird/Ice), the menu bar manager, made to work on macOS 27.

[![Download](https://img.shields.io/github/v/release/TK88101/Ice?style=flat-square&label=download)](https://github.com/TK88101/Ice/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square)
![Tested](https://img.shields.io/badge/tested-macOS%2027.0.1-fa4e49?style=flat-square)
[![License](https://img.shields.io/github/license/TK88101/Ice?style=flat-square)](LICENSE)

## Why this fork

On macOS 27 the system no longer lets an app move another app's menu bar items, and the
upstream release stops hiding anything there. This fork hides them a different way: the
items you choose are moved off the bar and shown in the **Ice Bar**, a panel under the
menu bar, where a click opens their menu.

## Install

Download `Ice-1.0.dmg` from the [latest release](https://github.com/TK88101/Ice/releases/latest),
open it and drag Ice into `Applications`.

- The app is signed with an Apple Development certificate and is **not notarized**. On a Mac
  other than the developer's, macOS will block the first launch: right-click Ice and choose
  Open, or allow it in System Settings > Privacy & Security.
- Ice needs **Accessibility** and **Screen Recording** permissions (System Settings > Privacy
  & Security). It asks for them on first launch.
- The bundle id is `io.github.tk88101.Ice`, so it does not share settings with the upstream
  Ice. Quit the upstream app before using this one: two menu bar managers fight over the bar.

## Using it on macOS 27

- **Hide an item**: hold Command and drag it to the left of Ice's divider. It leaves the bar
  and appears in the Ice Bar.
- **Show hidden items**: click an empty area of the menu bar (or hover, scroll, or use the
  hotkey, as set in Settings). Click an item in the Ice Bar to open its menu.
- **Take an item out**: hold Command with the pointer on the menu bar; the hidden items come
  back to their places. Drag the one you want to the right of the divider.
- Ice's own icon must stay to the right of its divider; if it is not, Settings says so.
- A newly launched app's item that lands left of the divider is listed in the Ice Bar within
  about two seconds.

On macOS 27 Settings only shows what was seen to work there. Not offered on 27: the
always-hidden section, item spacing, the search panel, divider styles, hiding application
menus, the split menu bar shape, and automatic updates. On macOS 14 to 26 the app behaves as
upstream.

What was measured, how, and what is still open: [docs/macos-27/STATUS.md](docs/macos-27/STATUS.md).

## Known limits

- Tested on one Mac with one display, macOS 27.0.1. macOS 14 to 26 were not run with this
  build.
- The Ice Bar shows each item as its app's icon, not the item's own picture.
- Launch at login is registered; an actual login start has not been observed yet.

## Build

Open `Ice.xcodeproj`, scheme `Ice`. Build outside `~/Documents` if that folder is synced by
iCloud (synced files carry attributes that break code signing). To sign with your own team,
set `DEVELOPMENT_TEAM` and change the bundle id.

## Credits and license

Ice is by [Jordan Baird](https://github.com/jordanbaird); this fork keeps its code and adds
the macOS 27 work. Available under the [GPL-3.0 license](LICENSE), as the original.
