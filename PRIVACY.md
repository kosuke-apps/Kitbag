# Privacy

Kitbag has no account, no analytics, no advertising and no server of its own. Nothing about you or your phone is sent to
the author. This was checked against the source on 2026-10-18 (every network address in Kitbag's own code is listed
below). The apps that run inside Kitbag, Headway and Mantissa, are covered at the end.

## What stays on your phone

- **Your timetable, deadlines, notes** (with the photos and files you attach), **grades and grading systems.** They are
  stored in the app's own storage on the phone. They are part of an iCloud or computer backup of the phone if you make
  one, and nowhere else. Kitbag does not use iCloud itself.
- **Your settings** (language, theme, which tools are shown, reminder choices, weather place, units).
- **Your location**, only if you allow it ("While Using the App") and only when you ask the weather to follow your
  position. It is read with a coarse accuracy (about a kilometre), used to find the weather, and not stored beyond the
  place you chose or the last place the weather was fetched for.
- **The addresses of calendars you subscribe to** (a Canvas or Google "secret address" lets anyone who has it read that
  calendar). They are kept in the iOS keychain, never in a file, and are left out of backups made by Kitbag.
- **Notifications** (deadline and class reminders, the warning before the signature runs out) are scheduled on the phone
  and shown by iOS. Kitbag does not use push notifications.
- **Widgets** read a copy of the timetable, deadlines and theme that Kitbag keeps in an App Group folder shared only with
  Kitbag's own widgets.
- **Backups** (Settings > Data) are files you create and send yourself (AirDrop, Files). Kitbag never uploads them.

## What goes over the network

| To | What | Why |
|---|---|---|
| `api.open-meteo.com` ([Open-Meteo](https://open-meteo.com/)) | the latitude and longitude of the weather place (the place you chose, or your approximate position), and the measures wanted | the weather forecast and past weather |
| `geocoding-api.open-meteo.com` ([Open-Meteo](https://open-meteo.com/)) | the text you type when you search for a place, and the app language | finding a place by name |
| the address of each calendar you subscribe to | an ordinary web request for that file, with no account and no identifier from Kitbag | showing that calendar's events |

Kitbag counts what these requests cost (bytes, by Wi-Fi or mobile data, by month) and keeps the count on the phone only, in
the app's settings; a backup leaves it out. Settings > Data usage shows it and lets you choose how often the weather and your
calendars are updated on each kind of connection.

Open-Meteo can see your phone's network address, as any web server can, and says in its terms that it keeps no personal
data. The calendar's host (Canvas, Google, ...) sees the request for your calendar as it does for any calendar app.
Kitbag sends the weather and calendar requests through a session that keeps nothing on disk.

## Permissions

- **Location (While Using the App):** described above. Without it, everything works except "my location" for the weather.
- **Notifications** (optional, asked for the first time a reminder is scheduled): reminders and the signature warning.
- **Photos:** none. Photos are chosen with the system picker, which gives Kitbag only the pictures you pick.
- **Files:** Kitbag reads only the files you pick (to import a timetable, a calendar file, a backup, or to attach).

## Apps inside Kitbag

Headway and Mantissa run inside Kitbag unchanged. Headway's own `PRIVACY.md` applies to it: it talks to the City of Madison's
public transit feeds and to Apple Maps for place search, and asks for location and notifications. Mantissa has no
network access and no permissions. Both keep their data in the same app storage as Kitbag's, on the phone.

## Contact

Questions: open an issue in the repository.
