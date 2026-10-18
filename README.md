# Kitbag

One iPhone app that holds a student's everyday tools behind a Today screen, and runs other apps inside itself.

A free Apple ID lets you install three apps on a device, and each stops launching after 7 days. Kitbag takes one slot:
tap an app icon on its home screen and the app opens full screen inside Kitbag; tap the house button at the top right to
come back.

This is a trial prototype for the author's own use at UW–Madison. It was built with AI assistance.

## Features

- A home screen with today's date, the class that is on or comes next, and the day's classes, above a grid of app icons;
  each tool opens inside Kitbag.
- Timetable: terms (semesters) with their dates, the week as an A4 page in the look of a printed school timetable (pastel
  blocks as tall as the class), a PDF export of that page, course cards with credits, course details with grade, deadlines
  and notes, and import and export as a readable JSON file.
- GPA: grades per course for any term (an old term can be entered with just its courses, credits and grades, no timetable
  needed), the cumulative GPA over the terms that count, a term graded on its own scale (study abroad) or left out of the
  cumulative GPA, courses left out or taken pass/fail, your own grading systems, credits earned, and a what-if
  calculator (imagined grades, imagined courses, courses left out) and the average a target GPA needs.
- Calendar: deadlines (assignments, exams, quizzes, projects) with local-notification reminders, a month page with the
  day's classes and deadlines, and a list grouped by how soon each is due. Import a calendar file (`.ics`) after a
  preview, export deadlines or a term's classes as `.ics`, and subscribe to a Canvas or Google calendar by its address:
  its events show beside yours and on Today (the address stays in the keychain).
- Notes: Markdown that is styled as you type (headings, bold, italic, strike, code, links, checklists you can tick,
  numbered and bulleted lists, quotes) with a format bar above the keyboard, photos and files kept with the note,
  search, an optional course, and a pin that shows the note on the Today screen.
- Weather: everything on one screen, with no scrolling: now, a strip of days from a week back to ten ahead, a chart and
  an hourly table (temperature, feels like, rain chance and amount, wind and gusts, humidity, cloud, UV, pressure) for
  the day you pick, and the day's totals; for Madison, a place you search for, or your location. Data by
  [Open-Meteo](https://open-meteo.com/) (CC BY 4.0).
- Backup: Settings > Data exports everything (timetable, deadlines, notes with photos and files, settings) as one `.kitbag`
  file to send by AirDrop or keep in Files, and restores one (after asking, and after saving what was there). It is also the
  way to move to another iPhone, since iCloud sync needs a paid developer account.
- Widgets: the class on now or next, the day's list and the whole week as a timetable, and what is due next (tap a circle
  to mark one done), on the home screen and the lock screen.
- Settings: a language (system, English, 日本語) for Kitbag, its tools and the apps inside it, five themes, light or dark, five app icons, and which tools and which parts of Today are shown and in what
  order.
- Headway (live Madison bus map) and Mantissa (offline exact calculator) run inside it as guests, from their own
  repositories, unchanged.


## Getting started

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. Check out [Headway](https://github.com/kosuke-apps/Headway) next to this folder, and build its data once with its own
   tools (see its README).
2. `tools/sync_guests.sh`
3. `xcodegen generate`
4. Open `Kitbag.xcodeproj`, or:
   `xcodebuild -project Kitbag.xcodeproj -scheme Kitbag -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`

To run on an iPhone with a free Apple ID, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your team
in it.

## Keeping it installed (free Apple ID)

A build signed with a free Apple ID stops opening after seven days, and the signature only gets a new seven days when
Xcode asks Apple for a new provisioning profile. Kitbag shows what is left at the bottom of the home screen (and in
Settings) and warns with a notification two days before, the evening before and on the day.

`tools/refresh_device.sh` renews it from the Mac without opening Xcode: it moves this app's provisioning profile aside so
that the build fetches a new one, builds for the phone and installs over Wi-Fi with `devicectl`. The phone has to be
paired for network use (Xcode > Window > Devices and Simulators > "Connect via network"), awake and on the same Wi-Fi.
`tools/refresh_device.sh --check` says when it last ran and whether the phone answers. `tools/install_refresh_agent.sh`
installs a launchd agent that runs it every hour and does something only once the last install is four days old
(`--remove` takes it away). Installing over a running app closes it.

## Architecture

Guests are pinned release tags of other repositories, built as separate modules inside Kitbag without changing them.
`docs/guests.md` explains how, what a guest needs from the host, and how to upgrade one.

## Quality checks

- Test: `swift test`
- Format: `xcrun swift-format format -i -r App Sources Tests Package.swift`
- Lint: `xcrun swift-format lint --strict -r App Sources Tests Package.swift`
- Build: the `xcodebuild` command above
- Visual: run in the iOS Simulator, open each guest, tap the house button

## Privacy

No account, no analytics, no server of its own: see `PRIVACY.md`.

## Licence

MIT, Copyright (c) 2026 Kosuke Satake. Third-party material is listed in `THIRD_PARTY.md`.
