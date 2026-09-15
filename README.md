# Wanderly

> Write it down now, flesh it out tonight, finish it on time.

Wanderly is a small native app for iPhone and Mac for the irregular things in a day: a meeting, an idea, something important that isn't urgent yet. Type a few words and pick a deadline. In the evening Wanderly reminds you to flesh the note out, and after the deadline it asks whether you did it.

![Wanderly on iPhone](docs/screenshot-ios.png)

## How it works

**Capture.** One line plus a deadline chip: today, tomorrow, this weekend, next weekend, or a specific date and time. You can also capture with Siri or Shortcuts ("用 Wanderly 记一件事") or from the Mac menu bar.

**Refine.** Every evening (21:30 by default) a notification tells you how many quick notes are still waiting. The refine view shows one note at a time, where you can add details, a next step, and a deadline. If you want, an AI can ask one to three questions about what's missing. It only asks; your answers go into the note.

**Finish.**
- A morning notification lists what's due today.
- Notes with a time go off at that time.
- After a note's deadline passes, a "做完了吗？" notification offers 完成 and 推迟到明天.
- If a note is still overdue, you get asked again the next evening.
- On Sunday evening, notes due later than a week out show up for a quick review.

Settings shows the next reminders that are scheduled on this device.

**Sync.** Notes sync between devices through iCloud (a CloudKit private database). There's no server and no account to create.

## Project layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec: one multiplatform app target (iOS 18, macOS 15) and iOS UI tests |
| `Wanderly/` | SwiftUI app: SwiftData model, notifications, views, App Intent |
| `WanderlyCore/` | Swift package with the pure logic: deadline math, reminder planning, AI requests and responses |
| `WanderlyUITests/` | Simulator UI tests: capture, refine, notifications, AI questions |

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
