# Wanderly

> Write it down now, flesh it out tonight, finish it on time.

Wanderly is a small native app for iPhone and Mac for the irregular things in a day: a meeting, an idea, something important that isn't urgent yet. Type a few words and pick a deadline. In the evening Wanderly reminds you to flesh the note out, and after the deadline it asks whether you did it.

![Wanderly on iPhone](docs/screenshot-ios.png)

## How it works

**Capture.** One line plus a deadline. If the text already says when ("周五下午三点和导师开会", "明天", "下周一 10:30", "tomorrow 3pm"), Wanderly fills in the deadline and shows it as a chip you can tap to dismiss. Otherwise pick today, tomorrow, this weekend, next weekend, or a specific date. You can also capture from:
- the home screen and lock screen widgets, and the 记一件事 control in Control Center or on the Action button
- the share sheet in other apps (存到 Wanderly)
- Siri or Shortcuts ("用 Wanderly 记一件事")
- the Mac menu bar

**Refine.** Every evening (21:30 by default) a notification tells you how many quick notes are still waiting. The refine view shows one note at a time, where you can add details, a next step, and a deadline. If you want, an AI can ask one to three questions about what's missing. It only asks; your answers go into the note.

**Finish.**
- A morning notification lists what's due today.
- Notes with a time go off at that time.
- After a note's deadline passes, a "做完了吗？" notification offers 完成 and 推迟到明天.
- If a note is still overdue, you get asked again the next evening.
- On Sunday evening, notes due later than a week out show up for a quick review.

Reminders are planned two weeks ahead. The iPhone app asks the system to wake it about once a day to keep planning, and the Mac app refreshes every few hours from the menu bar. If Wanderly hasn't been opened for a long time, one last notification asks you to open it so reminders don't silently stop.

Settings shows the next reminders scheduled on this device and whether iCloud sync is working.

**Sync.** Notes sync between devices through iCloud (a CloudKit private database). There's no server and no account to create. The widgets and the share extension reach the app through an App Group: the app writes a small snapshot for the widgets, and shared notes wait in an inbox until the app next opens.

## Project layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec: the multiplatform app (iOS 18, macOS 15), its widget and share extensions, and iOS UI tests |
| `Wanderly/` | SwiftUI app: SwiftData model, notifications, background refresh, views, App Intents |
| `WanderlyWidgets/` | Home screen and lock screen widgets, plus the Control Center control |
| `WanderlyShare/` | Share extension for iPhone and Mac |
| `WanderlyCore/` | Swift package with the pure logic: deadline math and parsing, reminder planning, widget snapshot and inbox, AI requests and responses |
| `WanderlyUITests/` | Simulator UI tests: capture, time detection, links, refine, notifications, AI questions |

## Build

```sh
brew install xcodegen
scripts/sync-secrets.sh   # optional: bake the Gemini key from ~/.env into local builds
xcodegen generate
open Wanderly.xcodeproj
```

## Test

```sh
# Logic tests. Set GEMINI_API_KEY to also call the live API.
cd WanderlyCore && swift test

# UI tests on the simulator. TEST_RUNNER_WANDERLY_LIVE_AI=1 enables the live AI question test.
xcodebuild test -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 17'
```

Launch arguments:
- `-demo` uses an in-memory store with sample notes.
- `-skipNotificationPrompt` doesn't ask for notification permission.
- `-refine` (together with `-demo`) opens the refine view right away.
- `-renderWidgets` (iOS debug builds) writes widget previews as PNGs into the app's `tmp` folder.

## AI questions

Gemini is the default; you can switch to Claude in Settings.

- **Gemini:** `gemini-flash-latest` with structured JSON output and low thinking. If that model is busy or rate-limited, the app retries with `gemini-flash-lite-latest`.
- **Claude:** `claude-opus-5` at low effort, with structured JSON output and server-side refusal fallback.

A key typed into Settings is stored in the Keychain and syncs to your other devices through iCloud Keychain. For your own builds you can also bake in a Gemini key: `scripts/sync-secrets.sh` reads `GEMINI_FREE_API` from `~/.env` and writes it to `Config/Secrets.xcconfig`, which git ignores. The key then sits inside the app bundle, so don't do this for builds you give to other people.

Both providers share the prompt in `WanderlyCore/Sources/WanderlyCore/Refinement.swift`.

## History

The earlier web prototype (idea garden, wandering fragments, Dreaming) is still in the git history before the native rewrite.

## License

MIT. See [LICENSE](LICENSE).
