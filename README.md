# OpenNotch

OpenNotch hides the notch on a MacBook display by painting the menu bar area of your wallpaper black. The notch then blends into a solid black bar. It is an independent, open-source, clean-room app for macOS, written for macOS 27 and later and released under the MIT License.

## How it works

OpenNotch reads your wallpaper's image file, draws it at the display's exact pixel size, paints a black band the height of the menu bar across the top, and sets the result as the wallpaper for the current Space. Each display gets a band of its own menu bar height. It keeps the original file and placement options so it can put them back.

- It never captures the screen, so it needs no Screen Recording, Accessibility, or other privacy permission.
- macOS only lets an app change the wallpaper of the Space on screen. OpenNotch re-renders when you switch Spaces, change displays, wake the Mac, or change the wallpaper.
- Renders are cached by their inputs, so returning to a Space sets the same file again. OpenNotch deletes any render no Space uses, so its render folder holds only the wallpapers on show.
- When you turn it off, OpenNotch restores the current Space on every display at once and lists the other Spaces it changed. Visit each one to restore it. A display that was disconnected is restored when you connect it again. This also works after a relaunch.

## Status

OpenNotch supports:

- The built-in display, and external displays when you turn off **MacBook Screen Only** (on by default).
- Still images (JPEG, PNG, HEIC, and other single-image files) with Fill, Fit, Stretch, or Center placement.
- Dynamic (time-of-day and light/dark) HEIC wallpapers. Every frame gets the band, and the schedule is kept.
- Optional rounded screen corners (small, medium, high): the top corners take the band color, and the bottom corners are black like the bezel.
- A band color for light mode and one for dark mode: Black (the default), Graphite, Silver, or White. The band follows the system appearance. In a light-and-dark HEIC wallpaper, each frame gets the color for its appearance.
- Launch at login.
- **Hide Menu Bar Icon**. OpenNotch keeps running. Open the app again to show the icon; it also comes back on every launch.

Not yet supported: Apple's built-in wallpaper collections, aerials, and Photos shuffles. OpenNotch says so in its menu and leaves those wallpapers alone.

## Requirements

- macOS 14 or later on Apple silicon.
- Xcode 16 or later to build.

## Build and run

```sh
swift test                 # unit and golden-image tests
Scripts/build-app.sh       # builds build/OpenNotch.app (ad-hoc signed)
open build/OpenNotch.app
```

OpenNotch runs from the menu bar and has no Dock icon. Choose **Black Menu Bar** to turn it on.

The app icon's source is `Support/OpenNotch.icon`, an Icon Composer document. With Xcode 26 or later, `Scripts/build-app.sh` compiles it with `actool` into the Liquid Glass icon (`Assets.car`) and a flat `OpenNotch.icns` for older macOS. Xcode 16 cannot read `.icon` files, so the script copies `Support/OpenNotch.icns` instead. After you edit the icon, run the script with Xcode 26 or later and copy `build/OpenNotch.app/Contents/Resources/OpenNotch.icns` to `Support/OpenNotch.icns`.

### Try a CI build without building

Every CI run on macOS 27 uploads the app as an artifact named `OpenNotch-<commit>`. Download it from the run's **Summary** page, unzip it, and move `OpenNotch.app` to Applications. The build is ad-hoc signed, not notarized, so macOS blocks the first launch. Clear the download flag once:

```sh
xattr -dr com.apple.quarantine /Applications/OpenNotch.app
open /Applications/OpenNotch.app
```

Or run `Scripts/install-ci-build.sh [--open] [commit]`. It installs the CI build of PR #1's head, or of the given commit, after checking that its macOS 27 job passed.

To test a build on a Mac, follow the [manual test checklist](docs/manual-test.md). `Scripts/mac-probe.sh` prints read-only diagnostics and backs up the wallpaper store first.

To update the golden images after an intended rendering change, run `RECORD_GOLDENS=1 swift test` and review the changed PNGs in `Tests/Goldens`. A test whose golden is missing fails and prints the PNG as `golden <name> <line>:` lines of decimal bytes, so a CI run can record one without a Mac.

## Layout

| Folder | Contents |
| --- | --- |
| `Core/` | Pure rendering: band geometry, placement, the renderer, and the render cache key. No AppKit. |
| `System/` | macOS integration: wallpaper source, Spaces, displays, saved state, and the engine that applies and reverts. |
| `App/` | The menu bar app. |
| `Tests/` | Unit tests, engine tests against a fake desktop, and golden images. |

## License

MIT. See [LICENSE](LICENSE).
