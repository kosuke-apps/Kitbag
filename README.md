# Kitbag

One iPhone app that holds a student's everyday tools behind a Today screen, and runs other apps inside itself.

A free Apple ID lets you install three apps on a device, and each stops launching after 7 days. Kitbag takes one slot:
tap an app icon on its home screen and the app opens full screen inside Kitbag; tap the house button at the top right to
come back.

This is a trial prototype for the author's own use at UW–Madison. It was built with AI assistance.

## Features

- A home screen with today's date, the class that is on or comes next, and the day's classes, above a grid of app icons;
  each tool opens inside Kitbag.
- Timetable: the week as a grid in the look of a printed school timetable (pastel blocks as tall as the class, a legend
  of courses), a course editor, and import and export as a readable JSON file.
- Calendar: deadlines (assignments, exams, quizzes, projects) with local-notification reminders, a month page with the
  day's classes and deadlines, and a list grouped by how soon each is due.
- Notes: free text with search, an optional course, and a pin that shows the note on the Today screen.
- Weather: now, the next 24 hours, the next 8 days and the details on one screen, for Madison, a place you search for,
  or your location. Data by [Open-Meteo](https://open-meteo.com/) (CC BY 4.0).
- Headway (live Madison bus map) runs inside it as a guest, from its own repository, unchanged.

Next: Mantissa as a second guest.

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
