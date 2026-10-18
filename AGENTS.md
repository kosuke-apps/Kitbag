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
  look of a printed UW–Madison timetable as an A4 page, a PDF export, terms with dates, credits and course details), GPA
  (grades, term and cumulative GPA, what-if and target calculators), Calendar (deadlines with reminders,
  month page and list, import and export of calendar files, subscription to Canvas or Google calendars), Notes (Markdown with live formatting, photos and files, search, course, pin) and Weather (one dense screen: now, a strip of days from a week back to ten ahead, a chart and an hourly table with twelve measures, the day's totals; Open-Meteo), and Headway and Mantissa as
  guests.  Nothing in it is a placeholder for an
  unbuilt feature.
- Out of scope for now: features that cross tools (for example bus times for the next class), accounts, the App Store
  (it needs the paid Developer Program), anything that needs a paid account (WeatherKit, remote push, iCloud: the weather comes from the free Open-Meteo service instead).
- The university timetable, deadlines and notes are the author's personal data: they never go into the repository or
  the tests.
- Data sources and what they send: the weather comes from Open-Meteo, a third-party service (free for non-commercial
  use, data under CC BY 4.0, credit shown in the app, see `THIRD_PARTY.md`). A request carries the place's coordinates
  and, when the place follows the phone, that means the phone's approximate location. A calendar subscription fetches the
  address the person typed (a Canvas or Google "secret address") and sends nothing else; the address is a secret, so it
  is kept in the keychain, never in a file, and the feed goes through an ephemeral session that caches nothing on disk.
  Nothing else leaves the phone.

## Technical context

- The author's iPhone 12 Pro runs iOS 18.6.2, so the deployment target stays iOS 17 and anything newer needs
  `#available`. Liquid Glass does not exist there: the look is built from materials, gradients and type.
- Stack: SwiftUI, iOS 17+, XcodeGen (`project.yml`; the `.xcodeproj` is not committed). The app is in Swift 5 mode and
  the logic package `KitbagCore` in Swift 6, as in Mantissa and Headway. Kitbag itself has no third-party dependency;
  the guests bring theirs (Headway: MapLibre, SwiftProtobuf, ZIPFoundation).
- Bundle identifier `dev.kosuke.kitbag`. Free Apple ID: `Config/Local.xcconfig` holds the team (not committed).
- A free Apple ID's signature lasts seven days. The app reads the expiry from `embedded.mobileprovision`
  (`ProvisioningProfile` in KitbagCore, `SigningStatus` in the app), shows it quietly at the bottom of the home screen
  and warns by notification. `tools/refresh_device.sh` renews it over Wi-Fi from the Mac (it moves the app's provisioning
  profile aside, because Xcode only asks Apple for a new one when the old one is gone), and
  `tools/install_refresh_agent.sh` runs that from launchd. Checked: a rebuilt app gets a new profile with seven fresh days
  and installs over Wi-Fi in about a minute. Not checked: the agent over several days, and a locked phone.
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
    `Season` and the term fields of `Timetable` (dates, week numbers, no classes outside the term), `TimetableLibrary`
    (all the terms; which one is in force today), `GradeScale` and `GPA` (UW–Madison, US plus/minus and Japanese scales;
    averages by credits; the average a target needs), `HomeLayout` (a saved order and hidden items, merged with what
    exists), `Deadline` and `DeadlineBook` (reminder dates, grouping by how soon), `Note` and `NoteBook` (title from the first
    line without its marks, pinned first, search over text and attachment names), `NoteAttachment` (a photo or file kept
    with a note: its name, where it is stored, its size), `Markdown` (`MarkdownBlock` reads what a line is: heading,
    bullet, checkbox, number, quote; `plain` strips the marks for titles and previews) and `MarkdownEditing` (what the
    buttons above the keyboard do: bold, italic, strike, code, line markers, continuing a list on return, checking a
    box; all on UTF-16 offsets, the units a text view reports), `Weather` (`Place`, `WeatherKind` from WMO codes, `Forecast` with a week of past hours, and
    `OpenMeteo`: the request URLs and the decoding of the service's answers), `CalendarEvent` and `Recurrence` (an event
    and the occurrences of its repeat rule inside a window), `ICalendar` (the parser: line unfolding, time zones, all-day
    events, VTODO, daily, weekly, monthly and yearly rules with count, until and exceptions; a rule it cannot read
    becomes a single event), `ICSWriter` (deadlines with an alarm, a term's classes as weekly events with an end date)
    and `DeadlineImport` (what an imported file adds or updates, matched by `Deadline.sourceUID`). Every user file has a
    `version`. `Tests/KitbagCoreTests/` uses invented data only (181 tests).
  - `App/KitbagApp.swift`: entry point; creates `GuestRuntimes` and the stores (`TimetableStore`, `DeadlineStore`,
    `NoteStore`, `WeatherStore`, `SubscriptionStore`) at launch, and refreshes the weather and the stale subscriptions when
    the app becomes active.
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
    (row and editor), `DeadlineStyle` (symbols, colours, names), `SubscriptionStore` (the subscriptions in
    `subscriptions.json`, their events in `subscription-events.json`, their addresses in the keychain via
    `App/Support/Keychain.swift`; fetched when added, on launch and on becoming active once an hour has passed; a failed
    refresh keeps the events it had and shows the reason), `CalendarTransfer` (import, export and the subscription
    screens). Subscribed events are shown as hollow dots on the month page, as "Subscribed" rows in a day's agenda and
    in Today's due-soon list; they are never copied into the deadlines.
  - `App/Notes/`: `NoteStore` (writes shortly after typing stops, drops empty notes; attachments are copied to
    `Attachments/<note id>/<attachment id>/<file name>` next to the notes file and go with the note), `NotesView` (list,
    search, editor with a bottom toolbar), `MarkdownEditor` (a UITextView that draws the Markdown as it is typed, with a
    scrolling bar of format buttons above the keyboard, list continuation on return and taps on checkboxes and links;
    it does not restyle while the keyboard is composing, so Japanese input is not interrupted), `AttachmentViews` (the
    row of thumbnails under the text, Quick Look, share and remove), `NoteStyle` (the sticky-note colour). Photos come
    from the system picker, which needs no permission; files come from the file importer.
  - `App/Weather/`: `WeatherStore` (fetch, cache in `weather-v2.json`, chosen place or the phone's location),
    `WeatherView` (header and now figures, `DayStrip`, `HourChart` with Swift Charts, `HourlyTable` with the measures as
    rows and hours as columns, day totals, credit), `PlacePicker` and `WeatherCard` (the Today card), `WeatherFormat`
    (units for text and for numbers, condition names, symbol colours).
  - `App/Timetable/`: `TimetableStore` (all terms in `timetables.json`; the first version's `timetable.json` becomes the
    first term and is left in place; an unreadable file is moved aside, never overwritten; `store.timetable` is the term
    in force today, which Today, the calendar and the notes use), `TimetablePage` (the A4 page: `.paper` is the printed
    original's look with every detail and a legend, and is what `TimetablePDF` renders; `.screen` keeps the proportions
    but writes in each block only what fits), `TimetableView` (term header, the page, course cards, menu, a zoomable
    viewer), `TermViews` (term name and dates, header, editor), `CourseViews` (card, detail with grade, deadlines and
    notes of the course, editor with credits), `CourseColor+Style` (pastel, dark and strong tones).
  - `App/GPA/`: `GPAView` (the cumulative GPA over the terms that count, each term's on its own grade scale, credits
    earned, a what-if card that imagines grades for open courses, imagined courses and courses left out, and the target),
    `GPACourseEditor` (a course for its credits, grade and how it counts: in the GPA, left out, or pass/fail),
    `GradeScaleStore` and `GradeScalesView` (the person's own grading systems, saved in UserDefaults). A term can be
    entered only for its grades (`Timetable.gradesOnly`: no grid, never the term in force), use its own scale (study abroad)
    or stay out of the cumulative GPA. All of it is KitbagCore: `GradeScale` (Codable, with which grades earn credit),
    `GPAMode`, `GPA.cumulative`, `GPA.earnedCredits`.
  - Reminders: `NotificationPreferences` and `NotificationPlanner` (KitbagCore) decide what is scheduled; `ReminderScheduler`
    makes the requests and keeps to a budget, because iOS holds at most 64 per app and the guests' own count too (the
    signature's three, up to 28 class reminders for the next week, the rest of 54 for deadlines, soonest first). Deadline
    reminders (by kind), class reminders (off until turned on; lead time; per course), quiet hours and the signature
    warning are set in Settings > Notifications > Choose what to be reminded of (`NotificationPreferencesView`, stored in
    UserDefaults so that a backup carries it). Class reminders are dated for the coming days, not a weekly repeat, so they
    stop at the end of a term.
  - Language: `LanguageChoice` (KitbagCore: system, English, 日本語) and `LanguageStore` (`App/Support/Language.swift`) hold
    the choice for the whole of Kitbag, set in Settings > Language. SwiftUI text follows it through the environment locale
    (`LanguageRoot`); text built in code goes through `L10n.string` and dates through `formattedInLanguage` or a style with
    `.locale(...)`, because `String(localized:)` and `formatted(date:time:)` would follow the phone. The choice is passed to
    the guests (`GuestRuntimes.applyLanguage` writes it into Headway's and Mantissa's own language settings, so the two
    never disagree) and to the widgets (through `WidgetSettings`). Never use `String(localized:)` in Kitbag's own sources.
  - `App/Backup/`: `BackupManager` writes everything into one `.kitbag` file (timetable, deadlines, notes with their
    attachments, and the `kitbag.*` and `weather.*` settings from UserDefaults; not the weather cache, not the calendar
    subscriptions or their secret addresses, not the guests' own data) using `BackupArchive` from KitbagCore (a header, a
    JSON list, then the bytes of each file one after the other, read and written in chunks, names checked so that none can
    leave the folder). A restore unpacks first, saves what is there now as `Backups/Before restore <time>.kitbag` (never
    deleted), then replaces the files and settings and has the stores `reload()`. `.kitbag` is a registered file type, so
    a backup sent by AirDrop opens in Kitbag and asks before restoring (`HomeView.onOpenURL`). The share sheet is
    presented from the top view controller: inside a SwiftUI sheet it closed again at once.
  - `Widgets/` and `Shared/`: the WidgetKit extension (`dev.kosuke.kitbag.widgets`) with a Timetable widget (small,
    medium, large and lock screen rectangular and inline: the class on or next; the day's list, which moves on to the next
    class day once today is over; and the large one is the week drawn by the app's own `TimetablePage`, `.screen` style,
    compiled into the extension) and a Deadlines widget (small, medium, large, lock screen) whose circles mark a deadline
    done without opening Kitbag: `CompleteDeadlineIntent` updates the widget's copy and queues the change
    (`Shared/WidgetActions.swift`), and `DeadlineStore.applyWidgetActions()` applies it when the app runs. A reminder for a
    deadline ticked off that way can still arrive until then, because a widget cannot cancel the app's notifications. A widget cannot read the app's
    files, so `App/Support/WidgetBridge.swift` copies `timetables.json`, `deadlines.json` and the theme into the App
    Group folder (`group.dev.kosuke.kitbag`, see `Shared/AppGroup.swift`) whenever the app is entered or left, and asks
    the widgets to redraw. The widgets compile `Theme.swift`, `CourseColor+Style.swift` and `DeadlineStyle.swift` from
    the app so that they look the same; their strings are in `Widgets/Localizable.xcstrings`. A widget opens a tool
    through the `kitbag://<tool>` URL scheme. A free Apple ID can sign an App Group and an extension (checked on the
    phone); the extension gets its own App ID and provisioning profile.
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
- Check the PDF without the UI: a debug build launched with `-kitbagExportPDF <path>` writes the current term's page there
  (`sips -s format png file.pdf --out file.png` turns it into an image).
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
