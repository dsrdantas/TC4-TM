# ============================
# Stage 1 — Builder
# ============================
FROM python:3.12-alpine3.20 AS builder

WORKDIR /app

# Dependências de build mínimas para psycopg2-binary
RUN apk add --no-cache \
    gcc \
    musl-dev \
    postgresql-dev \
    libffi-dev

# Copia apenas requirements.txt para cache
COPY requirements.txt .

# Instala dependências Python no prefix /install
RUN pip install --upgrade pip && \
    pip install --prefix=/usr/local --no-cache-dir -r requirements.txt

# ============================
# Stage 2 — Runtime
# ============================
FROM python:3.12-alpine3.20

WORKDIR /app

# Instala apenas curl para o HEALTHCHECK
RUN apk add --no-cache \
    curl \
    postgresql-libs

# Define PYTHONPATH para os pacotes instalados no builder
ENV PYTHONPATH="/usr/local/lib/python3.12/site-packages"

# Copia pacotes Python instalados no builder
COPY --from=builder /usr/local /usr/local

# Copia o código da aplicação e ajusta permissões
COPY . .

# Cria usuário e grupo restritos sem shell de login
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin && \
    chown -R appuser:appgroup /app

USER appuser

# Porta do serviço
EXPOSE 8002

# HEALTHCHECK usando /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8002/health || exit 1

# Comando final: gunicorn servindo Flask com OTel auto-instrumentation
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8002", "app:app"]