# Changelog

All notable changes to OpenNotch are recorded here. Each release on GitHub uses its section of this file as its notes.

Versions follow [Semantic Versioning](https://semver.org). A version with a suffix, such as `0.1.0-beta.1`, is a beta and is published as a pre-release.

Add each change under **Unreleased** in the pull request that makes it. To release, rename **Unreleased** to the new version and date, add a new empty **Unreleased** above it, merge, and run the Release workflow (see the README).

## Unreleased

## 0.1.0-beta.1 - 2026-11-05

The first beta of OpenNotch.

### Added

- Hide the notch by painting the menu bar area of the wallpaper with a solid band, on the built-in display and, with **MacBook Screen Only** off, on external displays.
- Still wallpapers (JPEG, PNG, HEIC and other single-image files) with Fill, Fit, Stretch or Center placement.
- Dynamic (time-of-day and light/dark) HEIC wallpapers: every frame gets the band and the schedule is kept.
- Band colors for light and dark mode: Black, Graphite, Silver or White.
- Optional rounded screen corners (small, medium, high).
- Restore the original wallpaper on every Space and display when you turn it off, including after a relaunch.
- Launch at login and **Hide Menu Bar Icon**.
- A Liquid Glass app icon.

### Changed

- Lower memory use: after a render the app holds about 14 MB instead of 43 MB for the two minutes it keeps the wallpaper for fast corner and color changes, and a dynamic wallpaper render peaks at about 108 MB instead of 330 MB. Rendered images are unchanged. (#4)

### Fixed

- Stale corners on other desktops, a menu that was too wide, and slow setting changes. (#3)

### Known issues

- A dynamic-wallpaper band test fails on macOS 27.2. (#5)
- Builds are ad-hoc signed, not notarized, so macOS blocks the first launch. See the README.
