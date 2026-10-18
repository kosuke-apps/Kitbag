# Running other apps inside Kitbag

Kitbag shows other apps (guests) full screen inside itself. A guest stays an independent app with its own repository,
its own releases and its own standalone build; Kitbag only reads a tagged release of it.

In web terms: the guest repository is a package that Kitbag installs at a pinned version (`tools/guests.txt` is the
lockfile). Kitbag does not copy the code into its own repository; it builds the guest's source as a separate module and
mounts the guest's root component, the way a host page would mount another team's app.

## What happens

1. `tools/sync_guests.sh` runs `git archive <tag>` on the guest's repository and unpacks it into `Guests/<Name>/`
   (ignored by Git). The guest's repository is never written, and its unfinished work never leaks in. Files that the
   guest does not commit (Headway's map, timetable seed and punctuality data) are copied from its working tree.
2. `project.yml` builds `Guests/<Name>/App/*.swift` into a framework `<Name>Guest`, except the guest's `@main` file,
   its `Info.plist` and its `Resources/`.
3. The `Kitbag` target carries the guest's resources in its own bundle, because the guest finds them with
   `Bundle.main` and SwiftUI looks strings up in the main bundle. Every guest's `Localizable.xcstrings` is merged into
   one (`tools/merge_guest_strings.py` writes `Guests/Merged/`), because two catalogs of that name cannot share a bundle.
4. `App/Guests/<Name>Guest.swift` does what the guest's `@main` does, then shows its root view. It uses
   `@testable import <Name>Guest`, which reaches the guest's internal types without changing them.

## What a guest needs from the host

Kitbag mirrors these by hand. When a release changes one, change it here too.

| Guest need | Where it lives in Kitbag |
|---|---|
| Launch-time work in the guest's `@main` (model, language, notification delegate, `BGTaskScheduler` registration) | `App/Guests/<Name>Guest.swift`, run from `GuestRuntimes` at launch |
| Info.plist keys (location string, background modes, BGTask identifiers) | `project.yml`, target `Kitbag`, `info.properties` |
| Localized Info.plist strings | `App/Resources/*.lproj/InfoPlist.strings` (Kitbag's own display name too) |
| Swift package dependencies and their versions | `project.yml`, `packages` (same versions as the guest's `project.yml`) |
| Resource files (styles, glyphs, data) | `project.yml`, target `Kitbag`, `sources` |
| String Catalog | merged by `tools/merge_guest_strings.py` (a clash between two guests is printed; the first guest in `tools/guests.txt` wins) |
| Accent colour (an `AccentColor` asset) | the adapter's `accentColor(_:)` and `tint(_:)`: Headway has none and uses the system blue, Mantissa's rose is copied by hand |
| Where the house button fits | `ModuleID.homeButtonPlacement`: a floating corner button, or a slim bar for a guest that uses the top right (Mantissa) |
| App icon | not carried (Kitbag has its own); the tile uses `Guests/GuestIcons/<Name>.png` |
| Its own settings screen, version text | unchanged; the version shown is Kitbag's, because the guest reads `Bundle.main` |

Known limits: every guest's launch work is paid when Kitbag starts, unless its adapter creates it lazily (Mantissa's does);
two guests that define a resource with the same name clash (image assets are not carried at all, string catalogs are
merged, and a key that two guests translate differently goes to the first guest: "Times" and "System default" today);
a guest reads `UserDefaults.standard` with its own keys, so Kitbag's keys are prefixed `kitbag.` and `weather.`.

## Upgrading a guest (for example Headway 0.6.2 to 0.7.0)

1. Edit the tag in `tools/guests.txt`.
2. `tools/sync_guests.sh` (it warns if the guest's asset catalog has grown beyond the app icon).
3. Compare the release with the previous tag for the rows of the table above:
   `git -C ../Headway diff v0.6.2 v0.7.0 -- project.yml App/HeadwayApp.swift App/Info.plist Package.swift`.
4. Mirror what changed, `xcodegen generate`, build. A change to an internal type that the adapter uses stops the build
   with a compile error; fix the adapter.
5. Run the app in the simulator: open the guest, check it shows its data, tap the house button.
6. Confirm the guest's repository is unchanged: `git -C ../Headway status`.
