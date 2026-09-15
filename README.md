# Wanderly

> Write it down now, flesh it out tonight, finish it on time.

Wanderly is a small native app for iPhone and Mac for the irregular things in a day: a meeting, an idea, something important that isn't urgent yet. Type a few words and pick a deadline. In the evening Wanderly reminds you to flesh the note out, and after the deadline it asks whether you did it.

![Wanderly on iPhone](docs/screenshot-ios.png)

## How it works

**Capture.** One line plus a deadline chip: today, tomorrow, this weekend, next weekend, or a specific date and time. You can also capture with Siri or Shortcuts ("用 Wanderly 记一件事") or from the Mac menu bar.

**Refine.** Every evening (21:30 by default) a notification tells you how many quick notes are still waiting. The refine view shows one note at a time, where you can add details, a next step, and a deadline. If you want, Claude can ask one to three questions about what's missing. It only asks; your answers go into the note.

**Finish.**
- A morning notification lists what's due today.
- Notes with a time go off at that time.
- After a note's deadline passes, a "做完了吗？" notification offers 完成 and 推迟到明天.
- If a note is still overdue, you get asked again the next evening.
- On Sunday evening, notes due later than a week out show up for a quick review.

**Sync.** Notes sync between devices through iCloud (a CloudKit private database). There's no server and no account to create.

## Project layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec: one multiplatform target (iOS 18, macOS 15) |
| `Wanderly/` | SwiftUI app: SwiftData model, notifications, views, App Intent |
| `WanderlyCore/` | Swift package with the pure logic: deadline math, reminder planning, Claude request/response |

## Build

```sh
brew install xcodegen
xcodegen generate
open Wanderly.xcodeproj
```

Run the logic tests with `cd WanderlyCore && swift test`. Launch with the `-demo` argument to use an in-memory store filled with sample notes.

## AI questions

Add a Claude API key in Settings. It's stored in the Keychain and syncs to your other devices through iCloud Keychain. Requests go straight from the device to the Anthropic API: `claude-opus-5` at low effort, with structured JSON output and server-side refusal fallback. The prompt is in `WanderlyCore/Sources/WanderlyCore/ClaudeRefiner.swift`.

## History

The earlier web prototype (idea garden, wandering fragments, Dreaming) is still in the git history before the native rewrite.

## License

MIT. See [LICENSE](LICENSE).
