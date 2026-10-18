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
- GPA: grades per course, term and cumulative GPA (UW–Madison, US plus/minus or Japanese scale), a what-if calculator and
  the average a target GPA needs.
- Calendar: deadlines (assignments, exams, quizzes, projects) with local-notification reminders, a month page with the
  day's classes and deadlines, and a list grouped by how soon each is due.
- Notes: free text with search, an optional course, and a pin that shows the note on the Today screen.
- Weather: everything on one screen, with no scrolling: now, a strip of days from a week back to ten ahead, a chart and
  an hourly table (temperature, feels like, rain chance and amount, wind and gusts, humidity, cloud, UV, pressure) for
  the day you pick, and the day's totals; for Madison, a place you search for, or your location. Data by
  [Open-Meteo](https://open-meteo.com/) (CC BY 4.0).
- Settings: five themes, light or dark, five app icons, and which tools and which parts of Today are shown and in what
  order.
- Headway (live Madison bus map) and Mantissa (offline exact calculator) run inside it as guests, from their own
  repositories, unchanged.

Next: calendar import, export and subscription, richer notes.

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

## Architecture

Guests are pinned release tags of other repositories, built as separate modules inside Kitbag without changing them.
`docs/guests.md` explains how, what a guest needs from the host, and how to upgrade one.

## Quality checks

- Test: `swift test`
- Format: `xcrun swift-format format -i -r App Sources Tests Package.swift`
- Lint: `xcrun swift-format lint --strict -r App Sources Tests Package.swift`
- Build: the `xcodebuild` command above
- Visual: run in the iOS Simulator, open each guest, tap the house button

## Licence

MIT, Copyright (c) 2026 Kosuke Satake. Third-party material is listed in `THIRD_PARTY.md`.
