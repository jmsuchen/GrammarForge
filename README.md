# GrammarForge

GrammarForge is an iOS app for English grammar output training. It is designed for Chinese English learners who understand grammar rules but still make unstable grammar mistakes in writing or speaking.

The app does not use a fixed daily course schedule. Instead, it uses a grammar skill tree, adaptive practice, AI grading, mistake classification, similar-question review, and mastery scoring to help learners turn grammar knowledge into usable output ability.

## Current MVP

- Home dashboard with current stage, recommended training, weak points, and next action.
- Grammar skill tree with locked, trainable, training, mastered, and review states.
- Chinese-to-English practice flow.
- Local mock AI grading result for rapid development.
- Mistake book grouped by grammar point and error type.
- Stage report based on progress instead of calendar cycles.
- Mastery algorithm:

```text
mastery = total accuracy * 70% + recent 5-question accuracy * 30%
```

## Tech Stack

- Swift
- SwiftUI
- iOS 17+
- Local in-memory data for the first MVP
- Pluggable AI grading service interface

## Project Structure

```text
GrammarForge/
├── GrammarForge.xcodeproj
├── GrammarForge/
│   ├── GrammarForgeApp.swift
│   ├── ContentView.swift
│   ├── Models.swift
│   ├── GrammarStore.swift
│   ├── AIGradingService.swift
│   ├── HomeView.swift
│   ├── SkillTreeView.swift
│   ├── PracticeView.swift
│   ├── MistakeBookView.swift
│   ├── ReportView.swift
│   └── Components.swift
└── GrammarForge_无周期版AI语法训练App项目方案.md
```

## DeepSeek API

The app currently uses `MockAIGradingService` so the training loop can run without network setup.

The DeepSeek API should be connected at:

```swift
GrammarForge/GrammarForge/AIGradingService.swift
```

That file already defines the app-facing protocol:

```swift
protocol AIGradingService {
    func grade(answer: String, exercise: Exercise, skill: GrammarSkill) async -> GradingResult
}
```

For a quick local prototype, add a new implementation in the same file or a new file such as `DeepSeekAIGradingService.swift`, then replace this line in `GrammarStore.swift`:

```swift
init(gradingService: AIGradingService = MockAIGradingService())
```

with:

```swift
init(gradingService: AIGradingService = DeepSeekAIGradingService())
```

Important: do not hard-code a real DeepSeek API key in the iOS app before open sourcing. For a public repository, the recommended production architecture is:

```text
iOS App -> your backend API -> DeepSeek API
```

The backend should hold `DEEPSEEK_API_KEY`, build prompts, call DeepSeek, validate JSON, and return a normalized grading result to the app.

For MVP experiments only, keep local secrets in an untracked config file or Xcode scheme environment variable. Never commit API keys.

## Run

Open the project in Xcode:

```bash
open GrammarForge/GrammarForge.xcodeproj
```

Or build from the command line:

```bash
xcodebuild \
  -project GrammarForge/GrammarForge.xcodeproj \
  -scheme GrammarForge \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath GrammarForge/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Roadmap

- Replace mock grading with a backend-backed DeepSeek grading service.
- Add persistent storage with SwiftData or SQLite.
- Add login and user-specific mastery records.
- Add similar-question generation as a separate AI endpoint.
- Add review queue and stage reports generated from real training history.
- Add free sentence writing and correction modes.

## License

MIT
