# Kitbag

One iPhone app that holds a student's everyday tools behind a Today screen, and runs other apps inside itself, so that a
free Apple ID's limit of three installed apps costs one slot. Workspace rules are in `~/Developer/AGENTS.md`; this file
adds what is specific to this project.

## Product

- Purpose: gather what a university student needs every day in one app: a Today screen (weather, next class, pinned
  notes, deadlines), tools written for Kitbag (timetable, deadlines and calendar, notes, weather) and the author's
  other apps (Headway now, Mantissa later) running inside it as full-screen "guests". A free Apple ID allows three
  apps on a device and expires each after 7 days, so fewer installs also means fewer reinstalls.
- Intended users: the author first (an exchange student at UW–Madison); anyone who builds the project themselves.
- Core user journey: open Kitbag, see the Today screen, tap an app icon below it, the tool opens full screen inside
  Kitbag, tap the house button at the top right to come back.
- Status: a trial prototype. Home screen with one guest (Headway) works; the Today screen and the Kitbag-made tools
  are next. Nothing in it is a placeholder for an unbuilt feature.
- Out of scope for now: features that cross tools (for example bus times for the next class), accounts, the App Store
  (it needs the paid Developer Program), anything that needs a paid account (WeatherKit, remote push, iCloud).
- The university timetable and deadlines are the author's personal data: they never go into the repository.

## Technical context

- Stack: Swift 5 mode, SwiftUI, iOS 17+, XcodeGen (`project.yml`; the `.xcodeproj` is not committed). Kitbag itself has
  no third-party dependency; the guests bring theirs (Headway: MapLibre, SwiftProtobuf, ZIPFoundation).
- Bundle identifier `dev.kosuke.kitbag`. Free Apple ID: `Config/Local.xcconfig` holds the team (not committed).
- How a guest runs inside Kitbag (details and the upgrade steps are in `docs/guests.md`):
  - `tools/guests.txt` pins each guest to a release tag of its own repository (a sibling folder).
    `tools/sync_guests.sh` copies that tagged snapshot (`git archive`, so the guest's repository is only read) into
    `Guests/<Name>/`, which is not committed.
  - `project.yml` compiles the guest's `App/` Swift sources, unchanged, into a framework `<Name>Guest`, with
    `ENABLE_TESTABILITY` on so that Kitbag can `@testable import` the guest's internal types. The guest's resources go
    into Kitbag's own bundle, because the guests look them up in the main bundle.
  - `App/Guests/<Name>Guest.swift` is the adapter: what the guest's `@main` does at launch, and its window content as a
    view. It is the only code that knows the guest's internals.
- Layout:
  - `App/KitbagApp.swift`: entry point; creates `GuestRuntimes` at launch.
  - `App/Guests/`: `GuestRuntimes.swift` (one runtime per guest, created at launch because background-task
    registration must happen before the app has finished launching), `HeadwayGuest.swift` (the adapter).
  - `App/Modules/ModuleID.swift`: the tools on the home screen: title, icon, content.
  - `App/Home/`: `HomeView` (icon grid, full-screen cover), `ModuleTile` (icon and name), `ModuleScreen` (the container
    with the house button at the top right).
  - `App/Resources/`: `Shell.xcstrings` (Kitbag's own strings, table "Shell"; the default table "Localizable" belongs
    to Headway's catalog, which is copied into the same bundle), `en.lproj`/`ja.lproj/InfoPlist.strings`, `Assets.xcassets`
    (the app icon, drawn by `tools/make_icon.swift`).
  - `tools/`: `sync_guests.sh`, `guests.txt`, `make_icon.swift`.
- Constraints: never edit anything under `Guests/` and never write to a guest's repository. Strings are localized
  (English base, Japanese); Kitbag's own strings live in the "Shell" table. The guest Headway keeps its own in-app
  language setting; a Kitbag-wide language choice is not built yet.

## Commands

- Sync the guests: `tools/sync_guests.sh` (needs the guest's checkout next to this folder and, for Headway, its
  downloaded data; see Headway's README).
- Generate and build for the simulator:
  `xcodegen generate`, then
  `xcodebuild -project Kitbag.xcodeproj -scheme Kitbag -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`
  (another thread may be using a booted simulator; boot a different one).
- Format: `xcrun swift-format format -i -r App`; lint: `xcrun swift-format lint --strict -r App` (config in
  `.swift-format`).
- Icon: `swift tools/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset`.
- If a command fails because `xcode-select` points at the Command Line Tools, prefix it with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- On an iPhone: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, then build and run from Xcode
  (Headway's `docs/run-on-iphone.md` explains the free-account steps).

## Definition of done

- The requested behaviour is complete, including edge and error states.
- Formatting and linting pass and the app builds; logic that is added gets Swift Testing tests (the shell has none yet).
- UI is checked in the iOS Simulator at representative sizes, in light and dark mode, with Dynamic Type and VoiceOver.
- Guests are checked after every sync: the guest opens, shows its map or data, and the house button returns home.
- The Headway repository is unchanged afterwards (`git status` clean there).
- Documentation matches what was delivered.
