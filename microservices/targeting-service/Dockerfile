# ============================
# Stage 1 — Build
# ============================
FROM python:3.12-alpine3.20 AS builder

WORKDIR /app

# Instala dependências do sistema para build
RUN apk add --no-cache \
    gcc \
    musl-dev \
    postgresql-dev \
    libffi-dev

# Copia requirements e instala dependências no diretório do build
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

# Copia dependências do build stage
COPY --from=builder /usr/local  /usr/local

# Copia o código da aplicação e ajusta permissões
COPY . .

# Cria usuário e grupo restritos sem shell de login
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin && \
    chown -R appuser:appgroup /app

# Usa usuário restrito
USER appuser

# Expõe a porta do serviço conforme README.md
EXPOSE 8003

# Healthcheck baseado no endpoint /health
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8003/health || exit 1

# Comando de inicialização (Gunicorn com OTel auto-instrumentation)
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8003", "app:app"]