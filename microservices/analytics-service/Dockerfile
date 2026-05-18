# ============================
# Stage 1 — Builder
# ============================
FROM python:3.12-alpine3.20 AS builder

WORKDIR /app

# Instala dependências de compilação mínimas (psycopg2, boto3 não precisa)
RUN apk add --no-cache \
    gcc \
    musl-dev \  
    libffi-dev \
    postgresql-dev

# Copia somente requirements.txt para usar cache
COPY requirements.txt .

# Instala dependências no prefixo /install para multi-stage
RUN pip install --upgrade pip && \
    pip install --prefix=/usr/local --no-cache-dir -r requirements.txt

# ============================ 
# Stage 2 — Runtime
# ============================
FROM python:3.12-alpine3.20

WORKDIR /app

# Instala curl para HEALTHCHECK
RUN apk add --no-cache curl

# Define PYTHONPATH para os pacotes instalados no builder
ENV PYTHONPATH="/usr/local/lib/python3.12/site-packages"
ENV PATH="/usr/local/bin:$PATH"

# Copia pacotes do builder
COPY --from=builder /usr/local /usr/local

# Copia o código do microservice e ajusta permissões
COPY . .

# Cria usuário e grupo restritos sem shell de login
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin && \
    chown -R appuser:appgroup /app

USER appuser

# Porta específica do serviço (trocar conforme README)
EXPOSE 8005

# HEALTHCHECK usando curl
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8005/health || exit 1

# Comando final: gunicorn com OTel auto-instrumentation
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8005", "app:app"]