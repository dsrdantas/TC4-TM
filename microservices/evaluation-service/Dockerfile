# ============================
# Stage 1 — Build
# ============================
FROM golang:1.23-alpine3.20 AS builder

# Instala dependências necessárias para build
RUN apk add --no-cache git bash build-base

WORKDIR /app

# Copia o projeto inteiro (incluindo go.mod quebrado)
COPY . .

# Limpa e ajusta dependências
RUN GONOSUMDB=* GONOSUMCHECK=* go mod tidy

# Compila binário estático para Linux
RUN CGO_ENABLED=0 GOOS=linux go build -o evaluation-service .

# ============================
# Stage 2 — Runtime
# ============================
FROM alpine:3.20

# Instala runtime essentials
RUN apk add --no-cache curl

# Cria usuário não privilegiado
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin

WORKDIR /app

# Copia o binário compilado
COPY --from=builder /app/evaluation-service .

# Ajusta permissões
RUN chown -R appuser:appgroup /app

USER appuser

# Expõe a porta conforme .env (default 8004)
EXPOSE 8004

# HealthCheck baseado no endpoint /health
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8004/health || exit 1

# Comando de inicialização
CMD ["./evaluation-service"]