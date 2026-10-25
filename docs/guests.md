# Running other apps inside Kitbag

Kitbag shows other apps (guests) full screen inside itself. A guest stays an independent app with its own repository,
its own releases and its own standalone build; Kitbag only reads a tagged release of it.

In web terms: the guest repository is a package that Kitbag installs at a pinned version (`tools/guests.txt` is the
lockfile). Kitbag does not copy the code into its own repository; it builds the guest's source as a separate module and
mounts the guest's root component, the way a host page would mount another team's app.

## Getting the guests (a fresh checkout)

`tools/fetch_guests.sh` clones the guests next to Kitbag at the tags that `tools/guests.txt` pins:

```bash
tools/fetch_guests.sh     # ../Headway at v0.7.4 and ../Mantissa at v0.26.0, from github.com/kosuke-apps
```

They are the public repositories <https://github.com/kosuke-apps/Headway> and <https://github.com/kosuke-apps/Mantissa>.
A folder that already exists is not touched (only a missing tag is fetched), so a checkout you work in is safe;
`KITBAG_GUEST_BASE` takes the repositories from another place, such as a local folder.

Headway also needs data that is in no repository: `data/maps/madison.pmtiles` (OpenStreetMap data in a Protomaps build),
`data/seed/mmt_gtfs.zip` (the City of Madison's timetable) and `data/punctuality/punctuality.json` (statistics Headway
builds from recordings of the City's live feeds; an empty table if there are none). Build them in Headway's checkout with
Headway's tools, `tools/fetch_basemap.sh`, `tools/fetch_timetable.sh` and `tools/build_punctuality.sh` (its README lists what
they need), before `tools/sync_guests.sh`, which stops with a message if one is missing. The City's terms of use cover its
feeds and anything derived from them (Headway's `docs/data-sources.md`): Kitbag and Headway publish the statistics as part of
the app, never the recordings, and a release of Kitbag carries the data inside the app as Headway's releases do.

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
| Accent colour (an `AccentColor` asset) | the adapter's `accentColor(_:)` and `tint(_:)`: Headway has none and uses the system blue, Mantissa's colour is copied by hand (it changed in v0.24.0, so check it on every upgrade) |
| Where the house button fits | `ModuleID.homeButtonPlacement`: a floating corner button, or a slim bar for a guest that uses the top right (Mantissa) |
| App icon | not carried (Kitbag has its own); the tile uses `Guests/GuestIcons/<Name>.png` |
| Its own settings screen, version text | unchanged; a guest reads its version from `Bundle.main`, which is Kitbag's, so while a guest is open `GuestVersionShim` (`App/Support/GuestShims.swift`) answers with the guest's own, taken from `Guests/GuestVersions.json` (written by `tools/sync_guests.sh` from the guest's `project.yml`) |

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

**Notification handler.** A guest that sets `UNUserNotificationCenter.current().delegate` in its launch work replaces
whatever was there, and the last one wins. Kitbag needs its own delegate (the buttons on a deadline's notification), so
`KitbagApp.init` creates `GuestRuntimes` first and sets Kitbag's delegate after it. Do not move the guests back into a
`@State` default: that makes them when the first view is drawn, after `init`, and the guest's delegate then replaces
Kitbag's. A notification from a guest still shows as a banner because Kitbag's `willPresent` answers for every
notification; its own tap action needs no handler of Kitbag's, but a guest whose notifications need a handler on tap
would have to be forwarded to from `KitbagNotificationDelegate`.

**Icon on a guest's notifications.** iOS draws the icon of the app on the left of every notification and an app cannot
change it, so a notification from Headway shows Kitbag's icon. Kitbag adds what it can: Headway's reminders are made by
Headway's own code with no picture, and some are posted at once (a route running late, found while the app is in the
background), which cannot be changed afterwards. So `GuestNotificationBranding` (`App/Support/GuestShims.swift`)
replaces the one method that adds a notification (`UNUserNotificationCenter.add(_:withCompletionHandler:)`, exchanged
with the Objective-C runtime at launch): a request whose identifier starts with `headway.` gets Headway's icon attached
on its way in (the name is not repeated as a subtitle: the icon says it), whether it is scheduled or posted
at once; any other request passes through untouched. A request that already carries a picture is left as it is: since
Headway 0.7 its late and early notifications carry one of their own (the route's colour and the minutes), which is what
they have to say, and only one picture is drawn. The debug hook posts one of those too
(`headway.watch.test.badge`) and logs the attachment ids it finds on each delivered notification. `ReminderScheduler.decorateGuestNotifications` is kept for the ones scheduled before an update
(it runs after every plan, when a tool is closed and when the app goes to the background). Check with
`-kitbagFakeHeadwayReminder YES` in a debug build: it posts one scheduled and one immediate `headway.*` notification
and logs the attachments of the delivered ones (the thumbnail itself is not drawn in the simulator).
If a release of Headway names its notifications differently, or a system update changes that method, this quietly
stops working; nothing else breaks.
