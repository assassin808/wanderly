# Wanderly maintainer notes

Wanderly is a native iPhone and Mac app for the irregular things in a day. Capture takes seconds and needs a deadline. Later the app reminds you to refine the note and asks whether it got done. Keep it that small.

## Product rules

- Capture is one line plus a deadline chip. Never add required fields to capture.
- There is one data type, `Entry`, with four states: rough → open → done or dropped. Don't add tags, projects, priorities, statistics, or dashboards.
- Reminders are the product. Any change to a deadline or state goes through `EntryActions`, or calls `Reminders.shared.scheduleSoon()`, so pending notifications get rebuilt.
- Keep notification and UI copy plain and short. No guilt, streaks, or motivational language.

## AI refinement behavior

The AI only asks questions. When a note is vague:

1. Find the smallest missing piece: purpose, people involved, a concrete next step, time and place, or what "done" means.
2. Ask one to three concrete questions that can each be answered in a sentence or two.
3. Don't ask about anything already written down.
4. Never write the plan, advice, or a polished version. The user's answers get appended to the note's details as question and answer pairs.

The prompt lives in `WanderlyCore/Sources/WanderlyCore/ClaudeRefiner.swift`.

## Code layout

- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated with `xcodegen generate` and is not committed.
- `WanderlyCore/`: pure Swift package with no SwiftUI or SwiftData. It holds deadline math (`Due.swift`), reminder planning (`ReminderPlanner.swift`), and the Claude request and response (`ClaudeRefiner.swift`). Put testable logic here and cover it with `swift test`.
- `Wanderly/`: the multiplatform SwiftUI app. `Model/` holds SwiftData and CloudKit code, `Services/` holds notifications, preferences, Keychain, and the App Intent, and `Views/` holds the views.

## Constraints

- SwiftData syncs through CloudKit. Every `@Model` property needs a default value or must be optional. No `@Attribute(.unique)`. Schema changes must be additive.
- iOS keeps at most 64 pending local notifications. `ReminderPlanner.maxPending` caps the plan at 60.
- The app target uses Swift 5 mode with default `MainActor` isolation. App Intent `perform()` and notification delegate callbacks need explicit isolation.
- Reminder settings are stored per device in UserDefaults. Entries sync.

## Verify

```sh
cd WanderlyCore && swift test && cd ..
xcodegen generate
xcodebuild -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Wanderly -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Launch with `-demo` to get an in-memory store with sample notes.
