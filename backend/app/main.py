import json
import os
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

load_dotenv()

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("ALLOWED_ORIGINS", "*").split(",")
    if origin.strip()
]

app = FastAPI(title="GrammarForge API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS or ["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class GradeRequest(BaseModel):
    skill_name: str = Field(min_length=1)
    chinese_sentence: str = Field(min_length=1)
    reference_answer: str = Field(min_length=1)
    user_answer: str = Field(min_length=1)


class GradeResponse(BaseModel):
    is_correct: bool
    score: int = Field(ge=0, le=100)
    corrected_sentence: str
    error_type: list[str]
    explanation_cn: str
    better_version: str
    similar_question_cn: str


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/grade", response_model=GradeResponse)
async def grade(request: GradeRequest) -> GradeResponse:
    if not DEEPSEEK_API_KEY:
        raise HTTPException(status_code=500, detail="DEEPSEEK_API_KEY is not configured")

    payload = {
        "model": DEEPSEEK_MODEL,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是一个英语语法训练教练，服务对象是中国英语学习者。"
                    "你必须只返回 JSON，不要返回 Markdown 或多余文字。"
                ),
            },
            {
                "role": "user",
                "content": build_prompt(request),
            },
        ],
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{DEEPSEEK_BASE_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
            response.raise_for_status()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"DeepSeek API error: {exc.response.status_code}",
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Unable to reach DeepSeek API") from exc

    content = extract_content(response.json())
    try:
        data = json.loads(content)
        return GradeResponse.model_validate(data)
    except (json.JSONDecodeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail="DeepSeek returned invalid grading JSON") from exc


def build_prompt(request: GradeRequest) -> str:
    return f"""
你的任务：
1. 判断学生英文是否准确表达中文意思。
2. 找出语法错误。
3. 给出正确句子。
4. 给出中文解释。
5. 生成一道相似训练题。
6. 分数必须是 0-100 的整数。
7. 只返回 JSON，不要输出多余文字。

语法点：{request.skill_name}
中文句子：{request.chinese_sentence}
参考答案：{request.reference_answer}
学生英文：{request.user_answer}

返回格式：
{{
  "is_correct": true,
  "score": 0,
  "corrected_sentence": "",
  "error_type": [],
  "explanation_cn": "",
  "better_version": "",
  "similar_question_cn": ""
}}
""".strip()


def extract_content(response_json: dict[str, Any]) -> str:
    try:
        return response_json["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise HTTPException(status_code=502, detail="DeepSeek response missing content") from exc
