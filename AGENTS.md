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
- Status: a trial prototype. Working: the home screen with a Today section (date that opens the calendar, weather,
  the class that is on or comes next, today's classes, what is due soon, pinned notes), Settings (theme and appearance, app
  icon, which tools and which parts of Today are shown and in what order), the tools Timetable (grid in the
  look of a printed UW–Madison timetable, course editor, JSON import and export), Calendar (deadlines with reminders,
  month page and list), Notes (search, course, pin) and Weather (one screen, Open-Meteo), and Headway and Mantissa as
  guests. Next: redo the timetable (A4 page, PDF, terms, credits, grades and GPA), a denser weather screen, calendar
  import, export and subscription, richer notes, a Kitbag-wide language setting. Nothing in it is a placeholder for an
  unbuilt feature.
- Out of scope for now: features that cross tools (for example bus times for the next class), accounts, the App Store
  (it needs the paid Developer Program), anything that needs a paid account (WeatherKit, remote push, iCloud: the weather comes from the free Open-Meteo service instead).
- The university timetable, deadlines and notes are the author's personal data: they never go into the repository or
  the tests.
- Data sources and what they send: the weather comes from Open-Meteo, a third-party service (free for non-commercial
  use, data under CC BY 4.0, credit shown in the app, see `THIRD_PARTY.md`). A request carries the place's coordinates
  and, when the place follows the phone, that means the phone's approximate location. Nothing else leaves the phone.

## Technical context

- The author's iPhone 12 Pro runs iOS 18.6.2, so the deployment target stays iOS 17 and anything newer needs
  `#available`. Liquid Glass does not exist there: the look is built from materials, gradients and type.
- Stack: SwiftUI, iOS 17+, XcodeGen (`project.yml`; the `.xcodeproj` is not committed). The app is in Swift 5 mode and
  the logic package `KitbagCore` in Swift 6, as in Mantissa and Headway. Kitbag itself has no third-party dependency;
  the guests bring theirs (Headway: MapLibre, SwiftProtobuf, ZIPFoundation).
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
  - `Package.swift`, `Sources/KitbagCore/`: the logic, tested on the Mac with `swift test` and linked into the app.
    `Weekday` (ISO numbering, written as names), `TimeOfDay` (minutes, written as `"13:20"`), `Course` and `Meeting`
    (hand-writable JSON; id, location and instructor may be left out), `Timetable` (slots of a day, `upcoming(after:)`
    for the class on now or next, `hourRange` and `visibleDays` for the grid, the file format with a `version`),
    `LocalDate` (a day as `"2026-10-22"`, independent of time zone) and `MonthGrid` (the rows of a month page),
    `HomeLayout` (a saved order and hidden items, merged with what exists), `Deadline` and `DeadlineBook` (reminder dates, grouping by how soon), `Note` and `NoteBook` (title from the first
    line, pinned first, search), `Weather` (`Place`, `WeatherKind` from WMO codes, `Forecast`, and `OpenMeteo`: the
    request URLs and the decoding of the service's answers). Every user file has a `version`.
    `Tests/KitbagCoreTests/` uses invented data only (64 tests).
  - `App/KitbagApp.swift`: entry point; creates `GuestRuntimes` and the stores (`TimetableStore`, `DeadlineStore`,
    `NoteStore`, `WeatherStore`) at launch, and refreshes the weather when the app becomes active.
  - `App/Theme/`: `Theme` (five themes: Ivory, Slate, Midnight, Forest, System; each has a light and a dark palette,
    a title typeface and may force dark; `themedScreen()`, `themedCard()`, `SectionHeading`), `ThemeStore` (choice and
    appearance in UserDefaults, `ThemeRoot` hands the palette and tint down).
  - `App/Settings/SettingsView.swift`: theme and appearance, the app icon (alternate icons made by
    `tools/make_icons.swift`, shown from `IconPreviews.xcassets`), and the lists that order and hide tools and Today's parts.
  - `App/Home/LayoutStore.swift`: the tool order and the Today parts, kept in UserDefaults.
  - `App/Support/AppFiles.swift`: where data files live (Application Support/Kitbag) and how an unreadable one is set
    aside. A file written by hand is rewritten once on load so that every id stays the same.
  - `App/Guests/`: `GuestRuntimes.swift` (one runtime per guest, created at launch because background-task
    registration must happen before the app has finished launching), `HeadwayGuest.swift` (the adapter).
  - `App/Modules/ModuleID.swift`: the tools on the home screen: title, icon, content.
  - `App/Home/`: `HomeView` (Today section, icon grid, full-screen cover), `ModuleTile` (icon and name; a guest's
    icon image or an SF Symbol square), `ModuleScreen` (the container with the house button at the top right: a tool
    keeps the top-right corner free, so its own toolbar uses the leading side).
  - `App/Today/TodayView.swift`: the date (opens the calendar), the weather card, the next-class card (opens the
    timetable), today's classes, due-soon deadlines and pinned notes. Each part opens its tool through a `ModuleRoute`
    (a tool plus where to start: a day, or a note).
  - `App/Calendar/`: `DeadlineStore` and `ReminderScheduler` (local notifications), `CalendarView` (month or upcoming,
    a button at the bottom right to add), `MonthView` (month page and the selected day's agenda), `DeadlineViews`
    (row and editor), `DeadlineStyle` (symbols, colours, names).
  - `App/Notes/`: `NoteStore` (writes shortly after typing stops, drops empty notes), `NotesView` (list, search,
    editor with a bottom toolbar), `NoteStyle` (the sticky-note colour).
  - `App/Weather/`: `WeatherStore` (fetch, cache in `weather.json`, chosen place or the phone's location),
    `WeatherView` (now, hours, days, details, credit), `PlacePicker` and `WeatherCard` (the Today card),
    `WeatherFormat` (units, condition names, symbol colours).
  - `App/Timetable/`: `TimetableStore` (the timetable as `timetable.json` in Application Support; an unreadable file
    is moved aside, never overwritten), `TimetableView` (screen, menu, import and export), `TimetableGrid` (the grid
    and legend: blocks as tall as the class, details dropped level by level when a block is small), `CourseEditing`
    (detail sheet, course list, course form), `CourseColor+Style` (pastel and dark variants).
  - `App/Resources/`: String Catalogs `Shell`, `Today`, `Timetable`, `Calendar`, `Notes` and `Weather` (add strings
    with `tools/add_strings.py <table>`; Kitbag's own strings, always
    `Text("…", tableName: "…")`; the default table "Localizable" belongs to Headway's catalog, which is copied into the
    same bundle), `en.lproj`/`ja.lproj/InfoPlist.strings`, `Assets.xcassets` (the app icon, drawn by
    `tools/make_icon.swift`).
  - `Local/` (not committed): the author's own files, for example `timetable-2026-fall.json`, the author's real
    timetable. Put it on a device through Timetable > menu > Import a file; into a simulator with the command below.
  - `tools/`: `sync_guests.sh`, `guests.txt`, `merge_guest_strings.py`, `make_icons.swift`, `add_strings.py`.
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
- Test the logic: `swift test`.
- Format: `xcrun swift-format format -i -r App Sources Tests Package.swift`; lint:
  `xcrun swift-format lint --strict -r App Sources Tests Package.swift` (config in `.swift-format`).
- Load the author's timetable into a simulator: terminate the app, then
  `C=$(xcrun simctl get_app_container <udid> dev.kosuke.kitbag data); mkdir -p "$C/Library/Application Support/Kitbag"; cp Local/timetable-2026-fall.json "$C/Library/Application Support/Kitbag/timetable.json"`
  and launch it again.
- Icons: `swift tools/make_icons.swift App/Resources` (the main icon and the alternates, with their previews).
- If a command fails because `xcode-select` points at the Command Line Tools, prefix it with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- On an iPhone: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, then build and run from Xcode
  (Headway's `docs/run-on-iphone.md` explains the free-account steps).

## Definition of done

- The requested behaviour is complete, including edge and error states.
- Formatting and linting pass, `swift test` passes and the app builds; logic that is added gets Swift Testing tests.
- UI is checked in the iOS Simulator at representative sizes, in light and dark mode, with Dynamic Type and VoiceOver.
- Guests are checked after every sync: the guest opens, shows its map or data, and the house button returns home.
- The Headway repository is unchanged afterwards (`git status` clean there).
- Documentation matches what was delivered.
