# ============================
# Stage 1 — Build
# ============================
FROM golang:1.23-alpine3.20 AS builder

WORKDIR /app

# Instala git (necessário para go mod download)
RUN apk add --no-cache git

# Copia o projeto e resolve dependências
COPY . .
RUN GONOSUMDB=* GONOSUMCHECK=* go mod tidy

# Compila binário estático
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o auth-service .

# ============================
# Stage 2 — Runtime
# ============================
FROM alpine:3.20

WORKDIR /app

# Instala curl para testes/healthcheck
RUN apk add --no-cache curl

# Cria usuário e grupo restritos sem shell de login
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /sbin/nologin

# Copia somente o binário
COPY --from=builder /app/auth-service .

# Ajusta permissões para o usuário não privilegiado
RUN chown -R appuser:appgroup /app

USER appuser

# Expõe a porta declarada no README
EXPOSE 8001

# HEALTHCHECK — usa o endpoint /health já documentado no README.md
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8001/health || exit 1

CMD ["./auth-service"]