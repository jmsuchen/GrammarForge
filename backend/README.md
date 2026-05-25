# GrammarForge Backend

FastAPI backend for GrammarForge. It keeps the DeepSeek API key on the server and exposes a small app-facing grading endpoint.

## Environment

Copy the example file and fill in your real key:

```bash
cp .env.example .env
```

```text
DEEPSEEK_API_KEY=your-real-key
DEEPSEEK_MODEL=deepseek-chat
ALLOWED_ORIGINS=*
```

`DEEPSEEK_API_KEY` must stay on the server. Do not put it in the iOS app.

## Run Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Grading request:

```bash
curl -X POST http://127.0.0.1:8000/grade \
  -H "Content-Type: application/json" \
  -d '{
    "skill_name": "现在完成时",
    "chinese_sentence": "我已经学习英语三个月了。",
    "reference_answer": "I have been learning English for three months.",
    "user_answer": "I learned English for three months."
  }'
```

## Deploy

Deploy this `backend/` directory to a server or container platform, set `DEEPSEEK_API_KEY` in that platform's environment variables, then point your domain to it.

Your iOS app should use:

```text
https://your-api-domain.com/grade
```

For local iOS simulator testing, set this Xcode Scheme environment variable:

```text
GRAMMARFORGE_BACKEND_URL=http://127.0.0.1:8000
```

For a real iPhone, `127.0.0.1` means the phone itself, not your Mac. Use a LAN address such as:

```text
GRAMMARFORGE_BACKEND_URL=http://192.168.1.10:8000
```

For production, use your HTTPS domain:

```text
GRAMMARFORGE_BACKEND_URL=https://grammarforge-app-wtofj.ondigitalocean.app
```
