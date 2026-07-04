# ==============================================================================
# Stage 1: Builder (의존성 설치 및 컴파일)
# ==============================================================================
FROM python:3.11-slim AS builder

WORKDIR /build

# 데비안 배포판 패키지 업데이트 및 빌드에 필요한 필수 도구 설치
# --no-install-recommends 및 rm -rf로 불필요한 패키지 캐시 삭제하여 용량 최적화
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# 가상환경(venv) 생성 및 경로 설정
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 의존성 파일 복사 및 설치
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt


# ==============================================================================
# Stage 2: Runner (최종 실행 이미지)
# ==============================================================================
FROM python:3.11-slim AS runner

WORKDIR /app

# 런타임에 필요한 시스템 패키지(curl) 설치 및 캐시 정리
# non-root 유저 및 그룹 생성 (보안 강화)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r appgroup && useradd -r -g appgroup appuser

# Builder 스테이지에서 깔끔하게 정제된 가상환경 파일만 복사
COPY --from=builder /opt/venv /opt/venv
# 애플리케이션 소스 코드 복사 및 소유권 변경
COPY --chown=appuser:appgroup ./src /app

# 환경 변수 설정 (파이썬 가상환경 경로 지정 및 버퍼링 해제)
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 보안 가이드: root가 아닌 appuser 권한으로 프로세스 실행
USER appuser

# FastAPI 포트 개방
EXPOSE 8000

# 컨테이너 헬스체크 (main.py의 /health 엔드포인트 연동)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# FastAPI 애플리케이션 실행 명령
CMD ["uvicorn", "settlement.main:app", "--host", "0.0.0.0", "--port", "8000"]