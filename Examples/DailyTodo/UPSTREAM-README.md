# Daily To Do

A private, local-first macOS SwiftUI app for daily tasks.

## Features

- Add tasks for any day and mark them complete
- Defer unfinished tasks to the next weekday
- Configure workday start time and IANA time zone
- Send one midday reminder while pending tasks remain
- Open at login and activate the window at workday start
- Store tasks locally in the sandboxed Application Support directory

## Privacy

No network access, analytics, or telemetry. Notifications show pending counts only. See [SECURITY.md](SECURITY.md).

## Build

Requires macOS 14+.

```sh
make test
make app
open build/DailyTodo.app
```

`make test` runs the dependency-free `DailyTodoChecks` target (no Xcode or XCTest).

## Setup

1. Open `build/DailyTodo.app`
2. Open **Settings**
3. Set workday start time and time zone
4. Click **Open at login** and approve if macOS prompts

The scheduler uses IANA time zones, so daylight-saving changes stay correct. Closing the window leaves the app running; use **Disable** in Settings before quitting if you no longer want daily opening.

## Reminders

- Workday length: 8 hours
- Reminder: 4 hours after workday start, at most once per working day
- Includes incomplete tasks due that day or earlier
- Requires notification permission

## Releases

```sh
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions builds a universal macOS ZIP with a SHA-256 checksum. The binary is ad-hoc signed with App Sandbox and is not notarized. GitHub Pages serves `docs/`; Releases host the app archive.

## License

MIT. See [LICENSE](LICENSE). Replace the copyright holder name if you want a personal copyright line.
