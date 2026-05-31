import json
import os
from typing import Any

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

load_dotenv()

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
APP_CLIENT_TOKEN = os.getenv("APP_CLIENT_TOKEN", "")
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
    vocabulary_level: str = Field(default="四级", min_length=1)


class ChatMessage(BaseModel):
    role: str = Field(pattern="^(system|user|assistant)$")
    content: str = Field(min_length=1)


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(min_length=1)
    temperature: float = Field(default=0.4, ge=0, le=2)
    response_format: dict[str, str] | None = None


class GenerateExerciseRequest(BaseModel):
    skill_name: str = Field(min_length=1)
    skill_description: str = Field(min_length=1)
    vocabulary_level: str = Field(default="四级", min_length=1)
    count: int = Field(default=10, ge=1, le=20)


class GeneratedExercise(BaseModel):
    chinese_sentence: str = Field(min_length=1)
    reference_answer: str = Field(min_length=1)


class GenerateExerciseResponse(BaseModel):
    exercises: list[GeneratedExercise]


class SingleExerciseResponse(BaseModel):
    chinese_sentence: str = Field(min_length=1)
    reference_answer: str = Field(min_length=1)


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


@app.post("/chat")
async def chat(
    request: ChatRequest,
    x_app_token: str | None = Header(default=None, alias="X-App-Token"),
) -> dict[str, Any]:
    verify_app_token(x_app_token)
    if not DEEPSEEK_API_KEY:
        raise HTTPException(status_code=500, detail="DEEPSEEK_API_KEY is not configured")

    payload: dict[str, Any] = {
        "model": DEEPSEEK_MODEL,
        "messages": [message.model_dump() for message in request.messages],
        "temperature": request.temperature,
    }
    if request.response_format is not None:
        payload["response_format"] = request.response_format

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

    return response.json()


@app.post("/generate-exercise", response_model=SingleExerciseResponse)
async def generate_exercise(request: GenerateExerciseRequest) -> SingleExerciseResponse:
    single_request = GenerateExerciseRequest(
        skill_name=request.skill_name,
        skill_description=request.skill_description,
        vocabulary_level=request.vocabulary_level,
        count=1,
    )
    response = await generate_exercise_set(single_request)
    if not response.exercises:
        raise HTTPException(status_code=502, detail="DeepSeek returned no exercise")
    exercise = response.exercises[0]
    return SingleExerciseResponse(
        chinese_sentence=exercise.chinese_sentence,
        reference_answer=exercise.reference_answer,
    )


@app.post("/generate-exercise-set", response_model=GenerateExerciseResponse)
async def generate_exercise_set(request: GenerateExerciseRequest) -> GenerateExerciseResponse:
    if not DEEPSEEK_API_KEY:
        raise HTTPException(status_code=500, detail="DEEPSEEK_API_KEY is not configured")

    payload = {
        "model": DEEPSEEK_MODEL,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是一个英语语法训练出题老师，服务对象是中国英语学习者。"
                    "你必须只返回 JSON，不要返回 Markdown 或多余文字。"
                ),
            },
            {
                "role": "user",
                "content": build_generate_prompt(request),
            },
        ],
        "temperature": 0.8,
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
        return GenerateExerciseResponse.model_validate(data)
    except (json.JSONDecodeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail="DeepSeek returned invalid exercise JSON") from exc


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
7. corrected_sentence 侧重改正语法和语义。
8. better_version 必须按指定词汇难度给出更自然的推荐句式。
9. similar_question_cn 必须适合学生用指定词汇难度造句。
10. 只返回 JSON，不要输出多余文字。

语法点：{request.skill_name}
中文句子：{request.chinese_sentence}
参考答案：{request.reference_answer}
学生英文：{request.user_answer}
造句词汇难度：{request.vocabulary_level}

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


def build_generate_prompt(request: GenerateExerciseRequest) -> str:
    return f"""
请生成 {request.count} 道中译英练习题，组成一组连续训练。

要求：
1. 全部题目都必须训练指定语法点，不能跑题。
2. 这一组题要有针对性：先从核心结构开始，再逐步加入常见干扰点。
3. 每道题的中文句子都要自然、具体、有生活或学习场景，不要像模板句。
4. {request.count} 道题不能重复场景、不能只替换一两个词。
5. 句子长度、词汇和 reference_answer 必须匹配指定词汇难度。
6. reference_answer 必须是对应中文句子的自然英文参考答案。
7. 不要生成选择题、填空题或解释，只生成中译英题目。
8. 只返回 JSON，不要输出多余文字。

语法点：{request.skill_name}
语法点说明：{request.skill_description}
造句词汇难度：{request.vocabulary_level}

返回格式：
{{
  "exercises": [
    {{
      "chinese_sentence": "",
      "reference_answer": ""
    }}
  ]
}}
""".strip()


def extract_content(response_json: dict[str, Any]) -> str:
    try:
        return response_json["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise HTTPException(status_code=502, detail="DeepSeek response missing content") from exc


def verify_app_token(token: str | None) -> None:
    if not APP_CLIENT_TOKEN:
        raise HTTPException(status_code=500, detail="APP_CLIENT_TOKEN is not configured")
    if token != APP_CLIENT_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid app token")
