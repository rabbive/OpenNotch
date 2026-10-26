# OpenNotch

OpenNotch hides the notch on a MacBook display by painting the menu bar area of your wallpaper black. The notch then blends into a solid black bar. It is an independent, open-source, clean-room app for macOS, written for macOS 27 and later and released under the MIT License.

## How it works

OpenNotch reads your wallpaper's image file, draws it at the display's exact pixel size, paints a black band the height of the menu bar across the top, and sets the result as the wallpaper for the current Space. It keeps the original file and placement options so it can put them back.

- It never captures the screen, so it needs no Screen Recording, Accessibility, or other privacy permission.
- macOS only lets an app change the wallpaper of the Space on screen. OpenNotch re-renders when you switch Spaces, change displays, wake the Mac, or change the wallpaper.
- Renders are cached by their inputs, so returning to a Space sets the same file again.
- When you turn it off, OpenNotch restores the current Space at once and lists the other Spaces it changed. Visit each one to restore it. This also works after a relaunch.

## Status

Version 0.1 supports:

- The built-in display only.
- Still images (JPEG, PNG, HEIC, and other single-image files) with Fill, Fit, Stretch, or Center placement.
- Optional rounded top corners (small, medium, high).
- Launch at login.

Not yet supported: external displays, dynamic (time-of-day) wallpapers, Apple's built-in wallpaper collections, aerials, and Photos shuffles. OpenNotch says so in its menu and leaves those wallpapers alone.

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

### Try a CI build without building

Every CI run on macOS 27 uploads the app as an artifact named `OpenNotch-<commit>`. Download it from the run's **Summary** page, unzip it, and move `OpenNotch.app` to Applications. The build is ad-hoc signed, not notarized, so macOS blocks the first launch. Clear the download flag once:

```sh
xattr -dr com.apple.quarantine /Applications/OpenNotch.app
open /Applications/OpenNotch.app
```

To update the golden images after an intended rendering change, run `RECORD_GOLDENS=1 swift test` and review the changed PNGs in `Tests/Goldens`.

## Layout

| Folder | Contents |
| --- | --- |
| `Core/` | Pure rendering: band geometry, placement, the renderer, and the render cache key. No AppKit. |
| `System/` | macOS integration: wallpaper source, Spaces, displays, saved state, and the engine that applies and reverts. |
| `App/` | The menu bar app. |
| `Tests/` | Unit tests, engine tests against a fake desktop, and golden images. |

## License

MIT. See [LICENSE](LICENSE).
