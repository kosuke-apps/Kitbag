# Third-party material

Kitbag's own code is under the MIT licence (`LICENSE`, Copyright (c) 2026 Kosuke Satake). Kitbag has no dependency of its
own. Apple's frameworks (SwiftUI, UIKit, UserNotifications, BackgroundTasks) are part of the system and need no entry.

## Shipped in the app

Kitbag embeds Headway (same author, MIT) built unchanged from a release tag, so everything Headway ships is shipped here
too, with the same terms. Headway's own list, with the checks behind it, is its `THIRD_PARTY.md`; the full licence texts
are in Headway's Settings > Licences screen inside Kitbag.

| What | Where | Licence |
|---|---|---|
| Headway | `Guests/Headway`, pinned in `tools/guests.txt` (snapshot, not committed) | MIT, Copyright (c) 2026 Kosuke Satake |
| [MapLibre Native](https://github.com/maplibre/maplibre-native) | Swift package, via maplibre-gl-native-distribution 6.31.0 | BSD 2-Clause |
| [SwiftProtobuf](https://github.com/apple/swift-protobuf) | Swift package (Headway's dependency) | Apache License 2.0 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Swift package (Headway's dependency) | MIT |
| [Open-Meteo](https://open-meteo.com/) (weather forecasts and place search over the network) | `Sources/KitbagCore/Weather.swift`, `App/Weather/` | Data CC BY 4.0, credited in the Weather screen; the free API is for non-commercial use only (no advertising, no subscription), under 10,000 calls a day, no key. Terms read on 2026-10-18 at open-meteo.com/en/terms |
| Noto Sans glyphs, protomaps map styles, OpenStreetMap data, City of Madison feeds | Headway's resources, copied into the app by `project.yml` | as listed in Headway's `THIRD_PARTY.md` |

## Used to build, not shipped

| What | Where | Licence |
|---|---|---|
| XcodeGen | command-line tool named in the README | MIT |
