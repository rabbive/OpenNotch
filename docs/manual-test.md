# Test OpenNotch on a Mac

This checklist tests a CI build of pull request #1 on a MacBook with a notch. The core steps take about 15 minutes. Steps marked optional need more time or extra hardware. Do them only if the core steps pass and you have time left.

The steps run from safest to riskiest. Steps 1 to 5 change no wallpaper. Every expected result comes from the code at the commit "Add a band color for light and dark mode". A result that the code cannot settle is marked **Not confirmed by the code**. Note what you see for those steps.

Tick a box only when you see exactly what it says. If a result differs, write down what you saw and go on, unless the step says to stop.

## Before you start (2 minutes)

You need:

- The GitHub CLI, signed in. Check with `gh auth status`.
- Two desktop Spaces. To add one, open Mission Control and click **+**.
- A photo file (JPEG, PNG, or HEIC) as the wallpaper of Desktop 1 on the built-in display. Pick it in **System Settings > Wallpaper**. An Apple gallery picture can show as unsupported, which hides the main test.

Get the kit, and keep this Terminal window open for the whole test:

```sh
gh repo clone rabbive/OpenNotch ~/OpenNotch
cd ~/OpenNotch
gh pr checkout 1
support=~/Library/Application\ Support/OpenNotch
```

`gh repo clone` needs git. If macOS offers to install the Command Line Tools, accept and run the commands again.

If `~/OpenNotch` exists already, run `cd ~/OpenNotch && gh pr checkout 1 && git pull` instead of the clone.

## Core steps

### 1. Run the probe and back up the wallpaper store (1 minute)

The probe only reads. It writes a read-only copy of `Index.plist`, a text dump of that file's full structure, and its own report to `~/Desktop/OpenNotch-backup`. It takes about a minute on a Mac with a long Spaces history.

```sh
Scripts/mac-probe.sh
```

- [ ] If Terminal has no access to your Desktop folder yet, macOS asks for it once. Click **Allow**. No other permission prompt appears. If macOS asks for Screen Recording, Accessibility, or control of another app, click **Don't Allow** and note it.
- [ ] The last line is `Saved this report to /Users/<you>/Desktop/OpenNotch-backup/probe-<time>.txt`. That folder also holds `Index-<time>.plist` and `Index-<time>.txt`, the store's full structure with its nested data decoded.
- [ ] Under `== Apps`, the report shows `TopNotch: not running`. If TopNotch is running, quit it from its own menu, because both apps rewrite the wallpaper.
- [ ] Under `== Screens`, the built-in display comes first and shows `(built-in)`. Note its `menu bar`, `safe area top`, and `OpenNotch band` numbers. An earlier probe on this Mac measured a 39 pt menu bar and a 38 pt safe area, which gives a band of 39 pt, 78 px.
- [ ] Under `== What OpenNotch would paint on each screen`, the built-in display ends with `verdict: paints <your photo>, a still image ...`. If it says `"This wallpaper type isn't supported yet"`, set a photo file as the wallpaper and run the probe again.

### 2. Install the CI build (1 minute)

```sh
Scripts/install-ci-build.sh
```

- [ ] It prints `Installed OpenNotch from commit <sha> into /Applications/OpenNotch.app`, a `CI run:` link, and `Not opened.` Write down the sha.
- [ ] If it prints `the macOS 27 CI job for <sha> is 'in_progress', not success`, nothing was installed. Wait for CI to finish and run the script again.

To install the build of another commit, pass it: `Scripts/install-ci-build.sh <commit>`.

### 3. Launch it for the first time (30 seconds)

```sh
open /Applications/OpenNotch.app
```

- [ ] No Gatekeeper dialog appears, because the install script cleared the quarantine flag. If macOS still blocks the app, open **System Settings > Privacy & Security**, click **Open Anyway**, and note the dialog's text.
- [ ] No Dock icon and no window appear. A menu bar icon appears: a rectangle with its top third filled. If you can't find it, the notch may hide it. Quit some menu bar apps to make room.
- [ ] Click the icon. The menu shows, in this order: **Black Menu Bar** (unchecked), `Off`, a separator, **MacBook Screen Only** (checked), **Rounded Corners** (a submenu with Off checked, then Small, Medium, High), **Bar Color in Light Mode** (a submenu with Black checked, then Graphite, Silver, White), **Bar Color in Dark Mode** (the same submenu, Black checked), **Launch at Login** (unchecked), **Hide Menu Bar Icon**, a separator, and **Quit OpenNotch** (⌘Q).
- [ ] The wallpaper has not changed.

### 4. Hide the menu bar icon and bring it back (1 minute)

1. Choose **Hide Menu Bar Icon**.

- [ ] The icon disappears. `pgrep -x OpenNotch` still prints a process ID.

2. Run `open -a OpenNotch`.

- [ ] The icon comes back within a second.

**Not confirmed by the code:** the icon returns only if SwiftUI passes the reopen event to OpenNotch's app delegate. If it does not return, run `killall OpenNotch && open -a OpenNotch`. A relaunch always shows the icon, because OpenNotch never saves it as hidden. Note which command brought it back.

### 5. Turn on Launch at Login (30 seconds)

1. Choose **Launch at Login**.

- [ ] The item shows a checkmark when you open the menu again.
- [ ] **System Settings > General > Login Items & Extensions** lists OpenNotch under **Open at Login**. macOS may also show a notification that a login item was added.

If macOS holds the login item for your approval, OpenNotch opens **Login Items & Extensions** for you. Allow OpenNotch there. The checkmark shows while approval is pending.

If the checkmark does not stay, the registration failed. Capture the reason with `log show --last 5m --predicate 'process == "OpenNotch"' | grep "launch at login"`.

Leave it on if you plan to do optional step O5. The last step turns it off.

### 6. Turn OpenNotch on (1.5 minutes)

1. On Desktop 1, choose **Black Menu Bar**.

- [ ] The status line shows `Painting wallpaper…`, then `MacBook: On`. A status line is never wider than the menu's other items. A longer explanation, such as an error, is in a submenu on the status line.
- [ ] The wallpaper is black from the top edge down to the bottom of the menu bar, across the full width. The notch blends into the black.
- [ ] No black shows below the menu bar, and no strip of wallpaper shows inside it.
- [ ] Below the band, the wallpaper keeps the same crop and position as before.
- [ ] `ls "$support/Renders"` lists one file named `v2-` followed by 24 hex characters and `.tiff`.
- [ ] `xattr -p io.github.rabbive.OpenNotch.origin "$support"/Renders/*.tiff` prints JSON with your photo's path as `originalURL`. Every render keeps its original this way, so OpenNotch can restore any Space that shows it.

2. Run `Scripts/mac-probe.sh` again.

- [ ] Under `== What OpenNotch would paint on each screen`, the built-in display ends with `verdict: showing an OpenNotch render, /Users/<you>/Library/Application Support/OpenNotch/Renders/v2-….tiff`.

If the verdict names your original photo or a system path instead, stop and send the report. Turning OpenNotch off restores a Space only when macOS reports the render as its wallpaper, through `desktopImageURL` or the wallpaper store. Lines `1.` and `2.` above the verdict show which source reported what.

Rendering time depends on the source and Mac. On an M1 Pro, painting a 5422 × 3615 JPEG for a 4112 × 2658 screen takes about 0.35 seconds: decode and scale 0.3 s, band under 0.03 s, uncompressed TIFF 0.015 s. A corner or bar color change within two minutes of the last paint reuses the decoded wallpaper and takes about 0.03 s. Wait for the status line to clear.

**Not confirmed by the code:** macOS picks the menu bar text color. Note whether the text turns white over the black band.

### 7. Try each rounded-corner style (1 minute)

1. Choose **Rounded Corners > Small**, then **Medium**, then **High**, then **Off**.

- [ ] After each choice, the wallpaper changes within about a second, and the status line returns to `MacBook: On`.
- [ ] For Small, Medium, and High, all four corners of the wallpaper become rounded. The two top corners, just below the band, have the band color outside the curve, and the two bottom corners have black. The radius is 6, 10, and 16 points. The Dock or a window can cover a bottom corner.
- [ ] For Off, the band's bottom edge is straight from side to side again, and the bottom corners are square.
- [ ] After each choice, `ls "$support/Renders"` still lists one file. OpenNotch deletes the old render once the new one is set.

### 8. Switch Spaces and come back (1.5 minutes)

1. Switch to Desktop 2 with Control-Right Arrow.

- [ ] Desktop 2 gets the band within about half a second. You may see its wallpaper without the band for a moment first.
- [ ] The status line shows `MacBook: On`.

2. Switch to Desktop 1, then to Desktop 2, then to Desktop 1 again.

- [ ] Each time you arrive, the Space already shows the band, with no flash.
- [ ] `cat "$support/applied.json"` shows two records, one per Space. Desktop 1 has `"space" : ""` and Desktop 2 has a UUID.
- [ ] `ls "$support/Renders"` lists one file per different render. If both Spaces show the same photo with the same placement, they share one file. The count stays the same however often you switch.

### 9. Turn it off and check the restore (2 minutes)

1. On Desktop 1, uncheck **Black Menu Bar**.

- [ ] Desktop 1 shows its original photo with its original placement at once.
- [ ] The menu shows `Off` and `Visit to restore`. Its submenu reads `Visit Desktop 2 to restore the wallpaper.`

2. Switch to Desktop 2.

- [ ] Its original wallpaper comes back within about half a second.
- [ ] The `Visit to restore` line is gone.
- [ ] `cat "$support/applied.json"` prints `[]`, and `ls "$support/Renders"` lists nothing. OpenNotch keeps a render while a saved record or a live desktop Space needs it. Stale full-screen entries do not keep a render file. If a file remains, note its name. The probe's store summary in the next step shows where it is still named.
- [ ] **System Settings > Wallpaper** shows the same photo and placement option as before, such as **Fill Screen**, with the same background color.

3. Run `Scripts/mac-probe.sh` again. Then compare its store summary with the first report's:

```sh
b=~/Desktop/OpenNotch-backup
choices() { sed -n '/^== Wallpaper choices/,/^== What OpenNotch/p' "$1"; }
diff <(choices "$(ls $b/probe-*.txt | head -1)") <(choices "$(ls $b/probe-*.txt | tail -1)")
```

- [ ] Only `LastSet` and `LastUse` dates differ.

The summary groups entries that hold the same choice. Each block lists the choice's `Provider`, its `Configuration`, and its placement in the `Content.EncodedOptionValues.values.placement.picker._0.id` line, then an `at` line for each live Space or display that uses it. If the `at` line of a Space you touched moved to another block, that Space's choice changed.

**Not confirmed by the code:** what macOS writes to `Index.plist` when an app sets the wallpaper. Note any other difference, such as a changed `Provider` or `Configuration`, or an all-Spaces entry that split into one entry per Space.

### 10. Quit and relaunch while on (1.5 minutes)

1. On Desktop 1, choose **Black Menu Bar**. Visit Desktop 2 and come back, so that both Spaces have the band.
2. Choose **Quit OpenNotch**.

- [ ] Both Spaces keep the band, because OpenNotch does nothing when it quits.

3. Run `open -a OpenNotch`.

- [ ] The icon appears. The menu shows **Black Menu Bar** checked and `MacBook: On`. The wallpaper does not flash.

4. Uncheck **Black Menu Bar**.

- [ ] Desktop 1 is restored at once, and the menu shows `Visit to restore`, with Desktop 2 named in its submenu.

5. Visit Desktop 2.

- [ ] Desktop 2 is restored, the `Visit to restore` line is gone, and `applied.json` is `[]`.

### 11. Use a dynamic wallpaper and keep the menu usable while it paints (2.5 minutes)

1. With OpenNotch off, set a time-of-day or light-and-dark HEIC file as the wallpaper of Desktop 1. The `== Multi-frame (dynamic) HEIC files` section of the probe report lists candidates with their frame counts and `apple_desktop` tags. Pick one tagged `solar` or `h24` for time of day, or `apr` for light and dark. OpenNotch paints a file with `no apple_desktop tags` as a still. In Finder, press ⇧⌘G, paste the file's folder, then right-click the file and choose **Set Desktop Picture**.

A dynamic wallpaper picked from the System Settings gallery can be an Apple collection, which OpenNotch does not support yet.

2. Choose **Black Menu Bar**. Then open the menu again at once.

- [ ] The status line reads `Painting… N of M`. M is the file's frame count. N grows each time you reopen the menu.
- [ ] While it paints, the menu opens and responds, and the **Rounded Corners** submenu opens. Note how many seconds the paint takes.
- [ ] Then the status line shows `MacBook: On`, and the wallpaper has the band.
- [ ] `ls "$support/Renders"` lists a `.heic` file.

If the status line shows `Painting wallpaper…` with no frame count and the render is a `.tiff`, the file has no `apple_desktop` schedule tags. OpenNotch then paints it as a still. Pick another file.

3. Open **System Settings > Appearance**, and switch between **Light** and **Dark**.

- [ ] For a light-and-dark wallpaper, the frame changes and both frames have the band.
- [ ] For a time-of-day wallpaper, the frame on screen matches the one the original showed at this time of day.

**Not confirmed by the code:** whether macOS follows the schedule of a rendered file. Unit tests check that every frame gets the band and that the `apple_desktop` schedule tags are copied.

4. Uncheck **Black Menu Bar**.

- [ ] The dynamic wallpaper comes back without the band.

5. Set your own photo as the wallpaper again.

### 12. Turn off Launch at Login (15 seconds)

Do this step last, after any optional steps.

1. Choose **Launch at Login**.

- [ ] The checkmark is gone, and OpenNotch no longer appears in **Login Items & Extensions**.

Send back the folder `~/Desktop/OpenNotch-backup`, the commit sha from step 2, and a note for each unticked box.

## Optional steps

### O1. MacBook Screen Only with an external display (2 minutes)

Do this step only if an external display is connected.

1. With **MacBook Screen Only** checked, choose **Black Menu Bar**.

- [ ] Only the built-in display gets the band. The status shows a line for the built-in display only.

2. Uncheck **MacBook Screen Only**.

- [ ] The external display gets a band as tall as its own menu bar. A second status line shows `<external display name>: On`, with a long name cut short.

3. Check **MacBook Screen Only** again.

- [ ] The external display gets its original wallpaper back on its current Space, and its status line disappears.
- [ ] If you visited other Spaces on the external display in between, the `Visit to restore` submenu names them as `Desktop N on <external display name>`.

4. Uncheck **Black Menu Bar**.

### O2. Show on all Spaces (2 minutes)

This step changes your wallpaper settings. The backup from step 1 records them.

1. In **System Settings > Wallpaper**, turn on **Show on all Spaces**. Run `Scripts/mac-probe.sh` so the report records how the store saves that setting.
2. On Desktop 1, choose **Black Menu Bar**.
3. Switch to Desktop 2.

- [ ] Note whether Desktop 2 already shows the band when you arrive.
- [ ] Note the status line on Desktop 2. If macOS gave it the render, OpenNotch adopts the saved original and shows `On`. Otherwise, Desktop 2 gets its own band and shows `On` after the render finishes.
- [ ] Note whether **Show on all Spaces** is still on.

4. Return to Desktop 1, uncheck **Black Menu Bar**, and visit Desktop 2.

- [ ] Note the `Visit to restore` line and the wallpaper on both Spaces. OpenNotch saves recovery data for live desktop Spaces that show a copied render, then restores each Space when you visit it. Stale full-screen entries in the wallpaper store do not keep render files after every desktop is restored.

### O3. Center placement with a small photo (2 minutes)

1. With OpenNotch off, set a photo smaller than the screen as the wallpaper, with placement **Centered**. Run `Scripts/mac-probe.sh`. The `What OpenNotch would paint` section shows the photo's size in pixels and in points.
2. Take a screenshot with ⇧⌘3. Then choose **Black Menu Bar**, and take another.

- [ ] The band covers the full width at the top.
- [ ] The photo stays centered on the same background color.
- [ ] Compare the photo's size in the two screenshots. The code draws a centered photo at one photo pixel per screen pixel.

**Not confirmed by the code:** macOS may draw a centered photo at its size in points, which is twice as large on this screen for a 72 dpi photo. If the photo shrinks to about half its size, report it with both screenshots.

3. Uncheck **Black Menu Bar**.

### O4. Restore an Apple wallpaper (2 minutes)

1. With OpenNotch off, pick a still picture from Apple's gallery in **System Settings > Wallpaper**. If it offers **Automatic**, **Light**, or **Dark**, note the choice. Run `Scripts/mac-probe.sh`.
2. Choose **Black Menu Bar**.

- [ ] Note the status line. The code shows `MacBook: On` when the store names an image file for this Space, and `MacBook: Not supported` otherwise. In the second case, nothing changes.

3. Uncheck **Black Menu Bar**, and run `Scripts/mac-probe.sh` again. Compare the store summaries with the `diff` command from step 9.

- [ ] Note any change in `Provider` or `Configuration` for this Space, and whether the Automatic, Light, or Dark choice survived. The code sets the original file back through `NSWorkspace`, so macOS may now record a plain image file where Apple's choice was.

### O5. Log out and back in with Launch at Login on (3 minutes)

1. With **Launch at Login** on, choose **Black Menu Bar**, and visit both Spaces. Run `ls "$support/Renders"`, and note the file names.
2. Log out, and log back in.

- [ ] OpenNotch starts by itself. Its icon shows, and its menu shows `MacBook: On`.
- [ ] Both Spaces show the band, with no flash.
- [ ] `ls ~/Library/Application\ Support/OpenNotch/Renders` lists the same file names. Each render's name comes from its inputs, so nothing renders again.

3. Uncheck **Black Menu Bar**, and visit Desktop 2.

- [ ] Both Spaces get their original wallpaper back.

### O6. Band colors in light and dark mode (2 minutes)

1. With OpenNotch on, choose **Bar Color in Light Mode > White** and **Bar Color in Dark Mode > Black**.
2. In **System Settings > Appearance**, choose **Light**.

- [ ] The status line shows `Painting wallpaper…`, then `On`, and the band turns white across the full width.

3. Choose **Dark**.

- [ ] The band turns black again after the render finishes.
- [ ] After each switch, `ls "$support/Renders"` lists one file.

4. Choose your usual appearance, and set both bar colors back to **Black**.

**Not confirmed by the code:** OpenNotch re-renders when macOS posts its appearance-change notification and reads the appearance from the app. If the band keeps its old color after a switch, switch to Desktop 2 and back to force a sync, and note whether the color then follows. Also note the menu bar text color over the white band.

### O7. Create a desktop while OpenNotch is on (2 minutes)

1. Turn on **Black Menu Bar** on Desktop 1. Use Mission Control to create Desktop 2 while OpenNotch is on.
2. Visit Desktop 2 while OpenNotch is still on.

- [ ] The menu shows `MacBook: On`. If macOS copied the render, the wallpaper gets the current corners and bar color without an error.

3. Return to Desktop 1 and choose another **Rounded Corners** style. Then visit Desktop 2.

- [ ] Desktop 2 changes to the new corners when you arrive. macOS gave it Desktop 1's old render, and OpenNotch reads the original from that render file.

4. Return to Desktop 1, turn OpenNotch off, then visit Desktop 2.

- [ ] Desktop 1 and Desktop 2 show their original wallpaper after you visit each one. The `Visit to restore` line clears, and `ls "$support/Renders"` lists no files.

## If something goes wrong

### Turn it off

Uncheck **Black Menu Bar**, then visit each Space that the `Visit to restore` submenu names. OpenNotch can only change the Space on screen, so each Space is restored on your next visit. The list survives a relaunch.

If the icon is hidden, run `open -a OpenNotch`. If that fails, run `killall OpenNotch && open -a OpenNotch`.

To stop OpenNotch from coming back, uncheck **Launch at Login** and choose **Quit OpenNotch**. Quitting leaves the band on screen. Only turning it off restores the wallpaper.

### Where OpenNotch keeps its files

- Settings are in the `io.github.rabbive.OpenNotch` defaults domain. The keys are `enabled`, `builtinOnly`, and `corners`. Read them with `defaults read io.github.rabbive.OpenNotch`.
- Saved originals are in `~/Library/Application Support/OpenNotch/applied.json`. Each record has a `key` (the `display` UUID and the `space` UUID), the `originalURL`, the `originalOptions`, and the `renderedURL`. The `space` is `""` for the first desktop. JSON escapes the slashes in the URLs as `\/`.
- Renders are in `~/Library/Application Support/OpenNotch/Renders`, named `v2-<hash>.tiff` or `v2-<hash>.heic`. Each keeps its original wallpaper and placement options in the `io.github.rabbive.OpenNotch.origin` extended attribute. At launch and after each sync, OpenNotch deletes renders that no saved record or live desktop Space references. Renders from older builds have no such attribute. Their name is a hash of what drew them, so OpenNotch matches it against the originals in `applied.json`.
- Logs: `log show --last 10m --predicate 'process == "OpenNotch"'`.

Do not delete `applied.json` while a render is on screen. It lists the Spaces to restore.

### Restore one Space by hand

1. Find the Space's record in `applied.json`, and read its `originalURL`.
2. In **System Settings > Wallpaper**, add that file as a photo, and select it.
3. Set the placement from `originalOptions.scaling`:
    - `1` is **Stretch to Fill Screen**.
    - `2` is **Centered**.
    - Any other value is **Fill Screen** if `allowClipping` is `true` or missing, and **Fit to Screen** if it is `false`.

### Last resort: restore Index.plist from the backup (untested)

Nobody has tested these steps. Use them only if System Settings cannot put the wallpaper back. Use the `Index-<time>.plist` from step 1, taken before OpenNotch ever ran.

1. Uncheck **Launch at Login**, and quit OpenNotch.
2. Save the current file, then copy the backup's contents over it. `cat` keeps the live file's owner and permissions. A plain `cp` from the read-only backup would not.

```sh
store=~/Library/Application\ Support/com.apple.wallpaper/Store
cp "$store/Index.plist" ~/Desktop/OpenNotch-backup/Index-before-manual-restore.plist
cat ~/Desktop/OpenNotch-backup/Index-<time>.plist > "$store/Index.plist"
```

3. Log out, and log back in.

**Not confirmed:** whether the wallpaper service reads the replaced file at login, or writes over it from memory first. If the wallpaper is still wrong, pick it again in **System Settings > Wallpaper**.
