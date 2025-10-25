# Repository Guidelines

## Project Structure & Module Organization
The Xcode project lives under `footballplay/footballplay.xcodeproj`, with app sources in `footballplay/footballplay`. `footballplayApp.swift` bootstraps the SwiftUI scene, while `ContentView.swift` is the primary entry point. Visual assets belong in `Assets.xcassets`; add new image sets there instead of embedding files in code. Keep logic-heavy extensions or helpers in dedicated subfolders inside `footballplay/` to avoid bloated view files. Unit tests live in `footballplay/footballplayTests`, and UI automation resides in `footballplay/footballplayUITests`.

## Build, Test, and Development Commands
- `xed footballplay/footballplay.xcodeproj` – opens the project in Xcode for interactive development.
- `xcodebuild -project footballplay/footballplay.xcodeproj -scheme footballplay -destination 'platform=iOS Simulator,name=iPhone 15' build` – reproducible CI-style build.
- `xcodebuild -project footballplay/footballplay.xcodeproj -scheme footballplay -destination 'platform=iOS Simulator,name=iPhone 15' test` – runs both unit and UI test targets; add `-only-testing:footballplayUITests` to scope as needed.
Prefer simulator destinations that match the one cited above so snapshot diffs stay consistent.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: 4-space indentation, braces on the same line, camelCase for properties/actions (`selectedTeam`), UpperCamelCase for types (`MatchSummaryView`). Keep SwiftUI view files focused on layout; extract stateful logic into `ObservableObject` models. When adding assets, use lowercase hyphenated names (`pitch-dark`) to match existing catalog entries. No linting tool is configured yet, so rely on Xcode’s `Editor > Structure > Re-Indent` and build warnings.

## Testing Guidelines
Unit specs go into `footballplayTests.swift`; prefer `test_<Feature>_<Condition>_<Result>()` naming, e.g., `test_LineupLoader_handlesEmptyRoster()`. UI flows belong in `footballplayUITests.swift` with concise scenarios plus reusable launch helpers in `footballplayUITestsLaunchTests.swift`. Aim to cover new view models and networking helpers with at least one deterministic test before opening a PR. Run `xcodebuild ... test` locally before pushing; flakiness is usually caused by hard-coded waits, so use predicates instead.

## Commit & Pull Request Expectations
Existing history uses short, descriptive messages (e.g., “Initial commit”, “專案初始化完成”). Continue with imperative, <=50-character summaries, optionally in English or Traditional Chinese for consistency. Each PR should list: a one-paragraph summary, testing evidence (`xcodebuild … test` output or simulator screenshots for UI), and any linked GitHub issues. Screenshot changes to major UI surfaces and mention new assets or configurations that reviewers should double-check. Avoid force pushes after review unless you call them out explicitly.
