# Wanderly maintainer notes

Wanderly is a native iPhone and Mac app for the irregular things in a day. The user pastes a paragraph and picks how urgent it is; AI organizes it in the background and asks what's missing; reminders keep coming back until the note is refined and done. Keep it that simple.

## Product rules

- Capture is text plus an urgency (紧急, 这几天, 不急, 只记录). Never add required fields. Deadlines are optional, and deadline detection (`DueParser`, or the AI's `due`) is a suggestion the user can remove.
- There is one note type, `Entry`, with four states: rough → open → done or dropped. Rough means AI's questions haven't been answered; replying or tapping 完善好了 makes it open.
- AI never blocks the UI. Anything the user is waiting for is saved on the entry (`aiStatus`, messages, `replyError`) and processed by `AIWorker`, so it survives closing the screen, backgrounding, or quitting.
- Reminders are the product. Any change to a deadline, urgency, or state goes through `EntryActions` or ends with `EntryActions.save`, so notifications and the widget snapshot get rebuilt.
- Keep copy plain and short. No guilt, streaks, or motivational language.

## AI behavior

- **Organize** (`Organizer`): title, category, a summary that only uses what the note says, a deadline only if the text states one, and follow-up questions. To-dos and meetings get at most two practical questions; ideas get two or three deeper ones; references usually none. Never write the plan for the user.
- **Conversation** (`Conversation`): ideas get a curious partner that can offer perspectives and ends with a question (deep model); everything else stays within three sentences (quick model). Don't make decisions for the user.
- **Beta** (`Watering`, `Wanderer`): watering asks one new question about an idea left alone for a few days; wandering links two or three ideas and must read as speculation the user can adopt or delete.

## Code layout

- `project.yml`: XcodeGen spec. The `.xcodeproj` and every target's `Info.plist` are generated with `xcodegen generate` and are not committed.
- `WanderlyCore/`: pure Swift package with no SwiftUI, SwiftData, or WidgetKit. Deadline parsing (`Due.swift`, `DueParser.swift`), reminder planning (`ReminderPlanner.swift`), provider-neutral AI requests (`AIClient.swift`, `GeminiClient.swift`, `ClaudeClient.swift`), prompts (`Organizer.swift`, `Conversation.swift`, `Wanderer.swift`), widget snapshot and inbox (`WidgetSnapshot.swift`, `SharedContainer.swift`), and `MarkdownExport.swift`. Put testable logic here and cover it with `swift test`; `StubResponses` fakes HTTP responses.
- `Wanderly/`: the multiplatform SwiftUI app. `Model/` holds `Entry`, `ChatMessage`, `WanderLink`, and `EntryActions`. `Services/` holds `AIWorker`, notifications, background refresh, preferences, Keychain, sync status, the widget bridge, and App Intents. `Views/` holds the list, capture bar, detail/conversation, refine flow, and settings.
- `WanderlyWidgets/`: WidgetKit extension. `TodayWidgetView.swift` is also compiled into the app so debug builds can render previews. `OpenCaptureIntent.swift` from the app is compiled into the extension; app-only code goes behind `#if !WIDGET_EXTENSION`.
- `WanderlyShare/`: share extension. It never opens the database; it writes an `InboxItem` that the app imports in `AppRefresh.run()`.
- `WanderlyUITests/`: iOS simulator UI tests. They always launch with `-demo`, so they never touch real data.

## Constraints

- SwiftData syncs through CloudKit. Every `@Model` property needs a default value or must be optional, relationships must be optional with an inverse, no `@Attribute(.unique)`, and schema changes must be additive. Insert a `ChatMessage` before setting its `entry` (`EntryActions.addMessage`).
- `AIWorker` claims work with `aiStatus`, `aiClaimedAt`, and `aiDevice` so iPhone and Mac don't process the same entry twice. Stale claims are retried after a few minutes; failures after half an hour. On iOS, requests run inside a background task so they finish after the user leaves.
- In `-demo` the worker is disabled unless `-demoAI` is also passed, so UI tests don't spend API quota by accident.
- SwiftData's CloudKit sync events (shown by `SyncStatus`) lose the error details, and the system log hides them as `<private>`. To see the real error, call `CKContainer(identifier:)` directly and log the error with `privacy: .public`. A brand-new iCloud container can take over an hour to start accepting zone saves.
- The app, widgets, and share extension share `group.io.github.assassin808.wanderly`. `SharedContainer.defaultURL` is nil in unsigned builds, so every caller has to handle that.
- iOS keeps at most 64 pending local notifications. `ReminderPlanner` plans 14 days, keeps 59 notifications, and always ends with a keep-alive notification. Rescheduling only removes planned requests, never pending `test-` notifications.
- The app target uses Swift 5 mode with default `MainActor` isolation; the widget extension and UI tests use `nonisolated`. App Intent `perform()` and notification delegate callbacks need explicit isolation.
- Reminder settings, the AI provider, and beta toggles are stored per device in UserDefaults. Notes and conversations sync.
- `Config/Secrets.xcconfig` holds a real API key. It is git-ignored and generated by `scripts/sync-secrets.sh`. Never commit it or print its contents.

## Verify

```sh
cd WanderlyCore && swift test && cd ..
xcodegen generate
xcodebuild -scheme Wanderly -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

Launch arguments: `-demo` for an in-memory store with sample notes (add `-demoAI` to let AI run), `-skipNotificationPrompt` to skip the permission prompt, `-refine` (with `-demo`) to open the refine view, and `-renderWidgets` (iOS debug) to write widget previews into the app's `tmp` folder.
