# Alpha Edge — image du SaaS (API + site + worker). Le pont MT5 et la compilation MQL5
# tournent sur un VPS Windows à part (docs/SAAS.md, « Déploiement »).
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    HF_DATA_DIR=/data HF_FEED=simulation HF_HOST=0.0.0.0 HF_PORT=8000

RUN useradd --create-home --uid 10001 alpha
WORKDIR /app
COPY pyproject.toml README.md ./
COPY hedgefund ./hedgefund
COPY config ./config
COPY .claude/skills ./.claude/skills
RUN pip install ".[research,web,saas]" && mkdir -p /data && chown alpha:alpha /data

USER alpha
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=4)"
CMD ["python", "-m", "hedgefund.web", "serve"]
