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
- FastAPI backend
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
├── GrammarForge_无周期版AI语法训练App项目方案.md
├── Dockerfile
└── backend/
    ├── app/main.py
    ├── requirements.txt
    ├── Dockerfile
    └── .env.example
├── render.yaml
└── .do/app.yaml
```

## DeepSeek API

The iOS app calls your backend. The backend calls DeepSeek. This keeps `DEEPSEEK_API_KEY` out of the open-source iOS app.

The app-facing protocol lives in:

```text
GrammarForge/GrammarForge/AIGradingService.swift
```

The default implementation is `BackendAIGradingService`, which posts to:

```text
{GRAMMARFORGE_BACKEND_URL}/grade
```

If `GRAMMARFORGE_BACKEND_URL` is not set while debugging, the app falls back to:

```text
https://api.your-domain.com
```

The backend environment variable is:

```text
DEEPSEEK_API_KEY=your-real-key
```

The grading protocol:

```swift
protocol AIGradingService {
    func grade(answer: String, exercise: Exercise, skill: GrammarSkill) async -> GradingResult
}
```

Important: do not hard-code a real DeepSeek API key in the iOS app. For this public repository, the intended architecture is:

```text
iOS App -> your backend API -> DeepSeek API
```

The backend holds `DEEPSEEK_API_KEY`, builds prompts, calls DeepSeek, validates JSON, and returns a normalized grading result to the app.

## Backend

Run the API locally:

```bash
cd backend
cp .env.example .env
# edit .env and set DEEPSEEK_API_KEY
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

For simulator testing, set this Xcode Scheme environment variable:

```text
GRAMMARFORGE_BACKEND_URL=http://127.0.0.1:8000
```

For real iPhone testing on the same Wi-Fi, use your Mac LAN IP instead of `127.0.0.1`:

```text
GRAMMARFORGE_BACKEND_URL=http://192.168.1.10:8000
```

For production, deploy `backend/` and point your domain at it:

```text
GRAMMARFORGE_BACKEND_URL=https://api.your-domain.com
```

## Deployment

Two simple deployment paths are prepared:

### Render

Use `render.yaml` as a Blueprint. Set `DEEPSEEK_API_KEY` in Render's environment variables. The service root directory is `backend/`.

### DigitalOcean App Platform

Use `.do/app.yaml` after redeeming the GitHub Student Developer Pack DigitalOcean credit. The root `Dockerfile` exists so App Platform can detect the backend even though the app code lives in `backend/`. In DigitalOcean, replace the placeholder secret with your real `DEEPSEEK_API_KEY`, then add your custom domain.

For Aliyun DNS, create a CNAME record such as:

```text
api.your-domain.com -> your platform-provided domain
```

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
