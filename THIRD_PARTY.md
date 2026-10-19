# Third-party material

Kitbag's own code is under the MIT licence (`LICENSE`, Copyright (c) 2026 Kosuke Satake). Kitbag has no dependency of its
own. Apple's frameworks (SwiftUI, UIKit, Charts, WidgetKit, AppIntents, QuickLook, PhotosUI, CoreLocation, Security,
UserNotifications, BackgroundTasks) are part of the system and need no entry. The licences and data credits are also shown
in the app (Settings > About > Licences); keep that screen, `LICENSE` and this file in step.

## Shipped in the app

Kitbag embeds Headway and Mantissa (same author, MIT) built unchanged from release tags, so everything they ship is
shipped here too, with the same terms. Mantissa uses no library. Headway's own list, with the checks behind it, is its `THIRD_PARTY.md`; the full licence texts
are in Headway's Settings > Licences screen inside Kitbag.

| What | Where | Licence |
|---|---|---|
| Headway | `Guests/Headway`, pinned in `tools/guests.txt` (snapshot, not committed) | MIT, Copyright (c) 2026 Kosuke Satake |
| Mantissa | `Guests/Mantissa`, pinned in `tools/guests.txt` (snapshot, not committed) | MIT, Copyright (c) 2026 Kosuke Satake |
| [MapLibre Native](https://github.com/maplibre/maplibre-native) | Swift package, via maplibre-gl-native-distribution 6.31.0 | BSD 2-Clause |
| [SwiftProtobuf](https://github.com/apple/swift-protobuf) | Swift package (Headway's dependency) | Apache License 2.0 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Swift package (Headway's dependency) | MIT |
| [Open-Meteo](https://open-meteo.com/) (weather forecasts and place search over the network) | `Sources/KitbagCore/Weather.swift`, `App/Weather/` | Data CC BY 4.0 (credited in the Weather screen and in Licences). The free API is for non-commercial use: its terms (open-meteo.com/en/terms, read on 2026-10-19) count an app as commercial when it has advertising or a subscription, and allow donations; they say nothing about open-source apps. Kitbag stays within them because it is free, with no advertising, no subscription and no price. If Kitbag were ever sold, carried advertising or charged for anything, an Open-Meteo commercial API subscription (with a key) would be needed first. The free tier allows under 10,000 calls a day per IP address, and Kitbag makes a few a day, which Settings > Data usage shows. |
| Map data (Headway's map of Madison) | `data/maps/madison.pmtiles` in Headway, not in either repository: built by Headway's `tools/fetch_basemap.sh` and copied into the app by `project.yml` | © OpenStreetMap contributors, [Open Database Licence 1.0](https://opendatacommons.org/licenses/odbl/1-0/); tiles from a Protomaps build. Credited in Settings > About > Licences and on Headway's map |
| Noto Sans glyphs, protomaps map styles, City of Madison transit feeds (timetable, live positions) | Headway's resources, copied into the app by `project.yml` | as listed in Headway's `THIRD_PARTY.md`. The City of Madison's terms apply to its feeds and to anything derived from them: build that data yourself (Headway's `docs/data-sources.md`); neither repository contains it |

## Used to build, not shipped

| What | Where | Licence |
|---|---|---|
| XcodeGen | command-line tool named in the README | MIT |
