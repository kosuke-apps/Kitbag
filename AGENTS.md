# Kitbag

One iPhone app that holds a student's everyday tools behind a Today screen, and runs other apps inside itself, so that a
free Apple ID's limit of three installed apps costs one slot. Workspace rules are in `~/Developer/AGENTS.md`; this file
adds what is specific to this project.

## Product

- Purpose: gather what a university student needs every day in one app: a Today screen (weather, next class, pinned
  notes, deadlines), tools written for Kitbag (timetable, deadlines and calendar, notes, weather) and the author's
  other apps (Headway now, Mantissa later) running inside it as full-screen "guests". A free Apple ID allows three
  apps on a device and expires each after 7 days, so fewer installs also means fewer reinstalls.
- Intended users: any student, at any school (the author first, who built it for the everyday use of a student); anyone who builds the project themselves. Nothing in the app is tied to a school or a city: the grading scales are named by their grades, the weather place is the person's own, and the apps inside it (Headway, Mantissa) are the only things that are specific, each by its own purpose.
- Core user journey: open Kitbag, see the Today screen, tap an app icon below it, the tool opens full screen inside
  Kitbag, tap the house button at the top right to come back.
- Status: a trial prototype. Working: the home screen with a Today section (date that opens the calendar, weather,
  the class that is on or comes next, today's classes, what is due soon, pinned notes), Settings (theme and appearance, app
  icon, which tools and which parts of Today are shown and in what order), the tools Timetable (grid in the
  look of a printed school timetable as an A4 page, a PDF export, terms with dates, credits and course details), GPA
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

- The author's iPhone runs iOS 18.6.2, so the deployment target stays iOS 17 and anything newer needs
  `#available`. Liquid Glass does not exist there: the look is built from materials, gradients and type.
- Stack: SwiftUI, iOS 17+, XcodeGen (`project.yml`; the `.xcodeproj` is not committed). The app is in Swift 5 mode and
  the logic package `KitbagCore` in Swift 6, as in Mantissa and Headway. Kitbag itself has no third-party dependency;
  the guests bring theirs (Headway: MapLibre, SwiftProtobuf, ZIPFoundation).
- Versions: SemVer `0.MINOR.PATCH`. After a batch of commits raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
  (a feature or visible change: the next minor; fixes only: the next patch), commit that, and make an annotated `vX.Y.Z` tag
  that says what changed. Tags stay local until the repository is pushed to `kosuke-apps`. 1.0.0 is the author's to decide.
- Bundle identifier `dev.kosuke.kitbag`. Free Apple ID: `Config/Local.xcconfig` holds the team (not committed).
- A free Apple ID's signature lasts seven days. The app reads the expiry from `embedded.mobileprovision`
  (`ProvisioningProfile` in KitbagCore, `SigningStatus` in the app), shows it quietly at the bottom of the home screen
  and warns by notification. `tools/refresh_device.sh` renews it over Wi-Fi or a USB cable from the Mac (`devicectl` picks the transport) (it moves the app's provisioning
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
    (all the terms; which one is in force today), `GradeScale` and `GPA` (four presets named by their grades, which a person copies into scales of their own;
    averages by credits; the average a target needs), `HomeLayout` (a saved order and hidden items, merged with what
    exists), `Deadline` and `DeadlineBook` (grouping by how soon), `DeadlineAlert` (one reminder of a deadline as a distance from when it is due: minutes, hours, days or weeks before, with a time of day for a deadline with no time), `Note` and `NoteBook` (title from the first
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
    `version`. `Tests/KitbagCoreTests/` uses invented data only (209 tests).
  - `App/KitbagApp.swift`: entry point; creates `GuestRuntimes` and the stores (`TimetableStore`, `DeadlineStore`,
    `NoteStore`, `WeatherStore`, `SubscriptionStore`) at launch, and refreshes the weather and the stale subscriptions when
    the app becomes active.
  - `App/Theme/`: `Theme` (five themes: Ivory, Slate, Midnight, Forest, System; each has a light and a dark palette,
    a title typeface and may force dark; `themedScreen()`, `themedCard()`, `SectionHeading`), `ThemeStore` (choice and
    appearance in UserDefaults, `ThemeRoot` hands the palette and tint down).
  - `App/Settings/SettingsView.swift`: theme and appearance, the app icon (alternate icons made by
    `tools/make_icons.swift`, shown from `IconPreviews.xcassets`), and the lists that order and hide tools and Today's parts.
  - `App/Home/LayoutStore.swift`: the tool order and the Today parts, kept in UserDefaults.
  - `App/Support/GuestShims.swift`: two runtime adjustments for the guests, which are built unchanged: Headway's
    notifications get its icon and name as they are added (`GuestNotificationBranding`), and `Bundle.main`'s version
    is the guest's own while that guest is open (`GuestVersionShim`, fed by `Guests/GuestVersions.json`, written by
    `tools/guest_versions.py` from `tools/sync_guests.sh`; `HomeView` says which guest is open). Details in `docs/guests.md`.
  - `App/Support/AppFiles.swift`: where data files live (Application Support/Kitbag) and how an unreadable one is set
    aside. A file written by hand is rewritten once on load so that every id stays the same.
  - `App/Guests/`: `GuestRuntimes.swift` (one runtime per guest, created at launch because background-task
    registration must happen before the app has finished launching), `HeadwayGuest.swift` (the adapter).
  - `App/Modules/ModuleID.swift`: the tools on the home screen: title, icon, content.
  - `App/Home/`: `HomeView` (the date pinned at the top through `safeAreaInset` so that everything else scrolls under it, a
    material bar that gets an edge once something has passed beneath; then Today, the tools, the signature footer; the
    full-screen cover), `ModuleTile` (an icon and name, a tile card, or a list row, by the style; `ToolsView` chooses; a
    guest's icon image or an SF Symbol square), `ModuleScreen` (the container with the house button at the top right: a tool
    keeps the top-right corner free, so its own toolbar uses the leading side).
  - Styles (`App/Theme/Style.swift`): a style is the look apart from the colours, chosen in Settings > Theme > Style
    (`StylePicker`, `ThemeStore.styleID`, stored as `kitbag.style` so that a backup carries it; no value means Classic).
    `KitbagStyle` is put in the environment (`\.kitbagStyle`) and carries scales for card radius, padding and shadow, whether
    cards are frosted glass, the Today layout, the tools layout, the date header and the spacing. `ThemedCard` reads it, so
    every card in every tool follows. Classic (stacked cards), Glass (frosted, rounder), Bento (tiles side by side, tools as
    tiles), Editorial (sharp corners, rules, serif, no boxes in Today, tools as a list) and Compact (dense, four icons to a
    row). The file is also compiled into the widgets target (`Theme.swift` uses it). A new style is a `StyleID` case, a
    `KitbagStyle`, and, if it arranges Today differently, a `TodayLayout`; add its thumbnail in `StylePicker`.
  - `App/Today/`: `TodayView` works out what Today shows once (`TodayModel`) and hands it to the layout the style names:
    `TodayStack` (in the same file), `TodayBento`, `TodayEditorial`, `TodayCompact`; the shared parts (`NextClassCard`,
    `DueSoonLines`, `PinnedNoteCard`, ...) live in `TodayView.swift`. `TodayHeader` is the date (opens the calendar), drawn
    large, as a page head or on one line by the style. The parts keep the order and visibility the person chose
    (`LayoutStore`); a part with nothing to show is left out. Each part opens its tool through a `ModuleRoute` (a tool
    plus where to start: a day, or a note). To look at a style without the settings, launch the simulator build with
    `-kitbag.style bento -kitbag.theme midnight -kitbag.language ja` (a launch argument overrides the saved value) and open a
    tool with `xcrun simctl openurl <udid> kitbag://settings`.
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
  - Weather detail (`App/Weather/WeatherDetail.swift`): the day's figures are tiles (temperature, sun, UV, rain and snow, wind,
    humidity, pressure, cloud and visibility); a tile opens that measure over every day the forecast has (bars or a line, a
    calendar tinted by the value, the chosen day's hours, and all its figures). `MetricReader` is the one place that turns a
    forecast into a measure's number and text. The hour chart is draggable (the readout stays until tapped), the present time
    is a dot and a faint dashed line in the theme's accent (no red), the dashed line is the "feels like" temperature and
    the legend says so. The forecast now asks Open-Meteo also for daylight and sunshine time, hours and snowfall, "feels like"
    highs and lows, the dominant wind direction and the dew point, so the cache file is `weather-v3.json`.
  - `App/Weather/`: `WeatherStore` (fetch, cache in `weather-v3.json`, chosen place or the phone's location),
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
  - Grade list import (`Sources/KitbagCore/GradeReport.swift`, `App/GPA/GradeReportImport.swift`): GPA > + > Import grades from
    a PDF reads an English "Grade list" (as some Japanese universities issue) with PDFKit, `GradeReportParser` turns its wrapped text into courses
    (checked on a real report: the credits it finds equal the report's own totals), `ReportedTerm.group` makes terms, and the
    preview sheet shows them before anything is added. Terms are titled `<year> First|Second semester`, graded on the
    `japan-aa` preset (AA 4, A 3, B 2, C 1, D 0; the import gives the person a copy of it first), kept as grades-only terms, and matched by title so that a newer
    report updates instead of duplicating (a term that an early version titled with a school's name in front is taken as the
    same term and gets the plain title). The two scales that were first named after a school (`uw-madison`, `tohoku`) are now
    `us-ab` and `japan-aa`; `GradeScale.legacyIDs` makes old files, backups and settings read as the new ids. The student's name and number are never kept. Tests use an invented report in the
    same layout; the real report is never committed.
  - `App/GPA/`: `GPAView` (the cumulative GPA over the terms that count, each term's on its own grade scale, credits
    earned, a what-if card that imagines grades for open courses, imagined courses and courses left out, and the target),
    `GPACourseEditor` (a course for its credits, grade and how it counts: in the GPA, left out, or pass/fail),
    `GradeScaleStore` and `GradeScalesView` (the person's own grading systems, saved in UserDefaults; every scale can be
    changed, a preset is only copied when one is added, and one that a term or the GPA screen still uses cannot be
    deleted). Earlier versions had four fixed scales: `GradeScaleStore.adoptInUse` gives a person a copy, with the same
    id, of each preset that a term or the chosen scale refers to, at launch and after a restore, so the GPA does not
    change; the presets' display names never name a country or a school. A term can be
    entered only for its grades (`Timetable.gradesOnly`: no grid, never the term in force), use its own scale (study abroad)
    or stay out of the cumulative GPA. All of it is KitbagCore: `GradeScale` (Codable, with which grades earn credit),
    `GPAMode`, `GPA.cumulative`, `GPA.earnedCredits`.
  - Data use: everything Kitbag downloads goes through `DataUseStore.fetch` (`App/Settings/DataUseStore.swift`), which counts
    what a request cost on the wire (the system's `URLSessionTaskMetrics`: headers and compressed body) into `DataUsage`
    (KitbagCore: bytes and requests by source, by Wi-Fi or mobile, by month, 13 months) and, for "not on mobile data", also
    forbids cellular and constrained access on the request itself. `DataUsePolicy.decide` (KitbagCore, tested) says whether
    to fetch now from the connection (`NetworkCondition`: Wi-Fi, mobile data or a hotspot, or Low Data Mode), the person's
    `DataUseSettings` (a rhythm per source for Wi-Fi and for mobile data, "save mobile data" which waits twice as long on
    mobile and four times in Low Data Mode, a monthly mobile limit) and what this month has used; what the person asked for
    (pull to refresh, a button, a new place or calendar) skips the rhythm and the limit but not "not on mobile data".
    `WeatherStore` and `SubscriptionStore` take the store; a new network call must too. The settings are in UserDefaults
    (`kitbag.dataUse.settings`, in a backup); the count is device-only (`kitbag.dataUse.usage`, listed in
    `BackupManager.deviceOnlyKeys`). `DataUseView` (Settings > Data usage) shows and changes it, and reads Headway's own meter
    through `HeadwayRuntime.dataUsed()`; Headway keeps its own choices. Both weather and calendars use ephemeral sessions.
  - Reminders: `NotificationPreferences` and `NotificationPlanner` (KitbagCore) decide what is scheduled; `ReminderScheduler`
    makes the requests and keeps to a budget, because iOS holds at most 64 per app and the guests' own count too (the
    signature's three, up to 28 class reminders for the next week, the rest of 54 for deadlines, soonest first). A deadline
    has any number of alerts (`Deadline.alerts`, edited in `DeadlineEditor` through `AlertList` and `AlertEditor` in
    `AlertViews.swift`; each row shows when it will fire, whether it has passed, whether quiet hours move it). A deadline
    with no time is reminded on the day it counts back to at the morning time (`allDayTime`, 9:00 unless changed) or the
    alert's own time. A new deadline starts with the alerts of its kind (`NotificationPreferences.alerts(for:)`, set in
    Settings > Reminders > What new deadlines start with; built-in `DeadlineAlert.standard(for:)`), and an imported one too. A
    file from before alerts has one `reminder` choice, which `Deadline` reads as the alerts it stood for and never writes
    again. "Remind again if not done" (`followUpDays`, up to 3) adds a notification on each of the mornings after the due day.
    Alerts that fall at the same minute are one; a deadline with no alerts is silent. Class reminders (off until turned on;
    lead time; per course), quiet hours and the signature warning are set in Settings > Notifications > Choose what to be
    reminded of (`NotificationPreferencesView`, stored in UserDefaults so that a backup carries it); its "Scheduled on this
    iPhone" page lists what iOS really has pending, read from the phone. Class reminders are dated for the coming days, not
    a weekly repeat, so they stop at the end of a term. Identifiers: `kitbag.deadline.<deadline id>.<alert id>` (or
    `.after<n>`), `kitbag.snooze.<deadline id>`, `kitbag.class.…`, `kitbag.signing.…`; a bare UUID is from before alerts and
    is cleaned up.
  - Notification buttons: a deadline's notification has Done, Snooze 10 min, Snooze 1 hour and Remind me tomorrow
    (category `kitbag.deadline`, registered on each `ReminderScheduler.sync`; the user info carries the deadline's id and the
    morning time). `KitbagNotificationDelegate.didReceive` hands them to `DeadlineStore.perform`, which marks done and cancels
    that deadline's pending notifications, or schedules `kitbag.snooze.<id>` from the same content. iOS starts Kitbag in the
    background just for a button, with no screen, so `KitbagApp.init` (not a `.task`) makes the stores, wires the deadlines
    to the terms and the preferences, and sets the delegate. It makes `GuestRuntimes` first because Headway installs its own
    delegate when it starts and the last one wins: with `@State` the guests were made later and Headway's replaced Kitbag's,
    so no button ever arrived. Test with `xcrun simctl push <udid> dev.kosuke.kitbag file.apns` (an `aps` alert with
    `"category": "kitbag.deadline"` and top-level `deadlineID` and `morning`), long-press the banner, and read the app's
    log (`log show --info --predicate 'subsystem == "dev.kosuke.kitbag"'`). An unsigned simulator build has no App Group, so
    the widget copy is not written there.
  - Language: `LanguageChoice` (KitbagCore: system, English, 日本語) and `LanguageStore` (`App/Support/Language.swift`) hold
    the choice for the whole of Kitbag, set in Settings > Language. SwiftUI text follows it through the environment locale
    (`LanguageRoot`); text built in code goes through `L10n.string` and dates through `formattedInLanguage` or a style with
    `.locale(...)`, because `String(localized:)` and `formatted(date:time:)` would follow the phone. The choice is passed to
    the guests (`GuestRuntimes.applyLanguage` writes it into Headway's and Mantissa's own language settings, so the two
    never disagree) and to the widgets (through `WidgetSettings`). Never use `String(localized:)` in Kitbag's own sources.
  - Licensing and privacy: `LICENSE` (MIT, Copyright (c) 2026 Kosuke Satake) is copied into the app and shown in Settings >
    About > Licences (`App/Licenses/LicensesView.swift`: Kitbag, the guests, and every library and font the guests carry,
    each with its text from the bundle, plus the data credits). That screen, `LICENSE`, `THIRD_PARTY.md` and the guests' own
    lists must change together. `PRIVACY.md` says what stays on the phone and lists every network address in Kitbag's own
    code; `App/Resources/PrivacyInfo.xcprivacy` declares no tracking and the one required-reason API used (UserDefaults,
    CA92.1). Pre-publication checks (all done 2026-10-18, nothing published): gitleaks clean over the history, only the
    noreply address in commits, no `.label.toml` tracked, no local path in a tracked file, personal data kept in `Local/`.
  - Backup folder (`App/Backup/BackupFolder.swift`): the person picks a folder with the system picker (iCloud Drive works, and
    needs no capability, which a free Apple ID cannot sign: tested, Xcode says "Personal development teams do not support the
    iCloud capability"); Kitbag keeps a bookmark to it and, at most once a day (on becoming active or going to the
    background), writes `Kitbag <date>.kitbag` into it through `NSFileCoordinator`, keeping the newest ten
    (`BackupNaming` in KitbagCore decides names, due-ness and pruning, and never touches other files). Another device picks
    the same folder and restores the newest one. This is not live sync. The bookmark and the last-backup time are
    device-only keys that a backup leaves out and a restore leaves alone.
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
  - `tools/`: `sync_guests.sh`, `guests.txt`, `merge_guest_strings.py`, `guest_versions.py`, `make_icons.swift`, `add_strings.py`.
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
