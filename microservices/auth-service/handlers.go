package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

type CreateKeyRequest struct {
	Name string `json:"name"`
}

type CreateKeyResponse struct {
	Name    string `json:"name"`
	Key     string `json:"key"`
	Message string `json:"message"`
}

func (a *App) healthHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	if err := a.DB.PingContext(ctx); err != nil {
		log.Printf("[health] DB unreachable: %v", err)
		w.WriteHeader(http.StatusServiceUnavailable)
		if encErr := json.NewEncoder(w).Encode(map[string]string{"status": "unhealthy", "reason": "db_unreachable"}); encErr != nil {
			log.Printf("Erro ao codificar resposta de health: %v", encErr)
		}
		return
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok", "version": "1.1.0"}); err != nil {
		log.Printf("Erro ao codificar resposta de health: %v", err)
	}
}

func (a *App) validateKeyHandler(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	keyString := strings.TrimPrefix(authHeader, "Bearer ")

	if keyString == "" {
		http.Error(w, "Authorization header não encontrado", http.StatusUnauthorized)
		return
	}

	keyHash := hashAPIKey(keyString)

	const selectSQL = "SELECT id FROM api_keys WHERE key_hash = $1 AND is_active = true"
	ctx, dbSpan := otel.Tracer("auth-service").Start(r.Context(), "db.api_keys.select",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
			attribute.String("db.sql.table", "api_keys"),
			attribute.String("db.statement", selectSQL),
			attribute.String("db.name", "auth_db"),
			attribute.String("server.address", "postgres"),
			attribute.Int("server.port", 5432),
		),
	)
	defer dbSpan.End()

	var id int
	err := a.DB.QueryRowContext(ctx, selectSQL, keyHash).Scan(&id)
	if err != nil {
		dbSpan.RecordError(err)
		dbSpan.SetStatus(codes.Error, "key validation failed")
		log.Printf("Falha na validação da chave (hash: %s...): %v", keyHash[:6], err)
		http.Error(w, "Chave de API inválida ou inativa", http.StatusUnauthorized)
		return
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(map[string]string{"message": "Chave válida"}); err != nil {
		log.Printf("Erro ao codificar resposta de validação: %v", err)
	}
}

func (a *App) createKeyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Método não permitido", http.StatusMethodNotAllowed)
		return
	}

	var req CreateKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Corpo da requisição inválido", http.StatusBadRequest)
		return
	}

	if req.Name == "" {
		http.Error(w, "O campo 'name' é obrigatório", http.StatusBadRequest)
		return
	}

	newKey, err := generateAPIKey()
	if err != nil {
		span := trace.SpanFromContext(r.Context())
		span.RecordError(err)
		span.SetStatus(codes.Error, "failed to generate api key")
		http.Error(w, "Erro ao gerar a chave", http.StatusInternalServerError)
		return
	}
	newKeyHash := hashAPIKey(newKey)

	const insertSQL = "INSERT INTO api_keys (name, key_hash) VALUES ($1, $2) RETURNING id"
	ctx, dbSpan := otel.Tracer("auth-service").Start(r.Context(), "db.api_keys.insert",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "INSERT"),
			attribute.String("db.sql.table", "api_keys"),
			attribute.String("db.statement", insertSQL),
			attribute.String("db.name", "auth_db"),
			attribute.String("server.address", "postgres"),
			attribute.Int("server.port", 5432),
		),
	)
	defer dbSpan.End()

	var newID int
	err = a.DB.QueryRowContext(ctx, insertSQL, req.Name, newKeyHash).Scan(&newID)

	if err != nil {
		dbSpan.RecordError(err)
		dbSpan.SetStatus(codes.Error, "failed to insert api key")
		log.Printf("Erro ao salvar a chave no banco: %v", err)
		http.Error(w, "Erro ao salvar a chave", http.StatusInternalServerError)
		return
	}

	log.Printf("Nova chave criada com sucesso (ID: %d, Name: %s)", newID, req.Name)
	w.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(w).Encode(CreateKeyResponse{
		Name:    req.Name,
		Key:     newKey,
		Message: "Guarde esta chave com segurança! Você não poderá vê-la novamente.",
	}); err != nil {
		log.Printf("Erro ao codificar resposta de criação: %v", err)
	}
}

func (a *App) masterKeyAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		keyString := strings.TrimPrefix(authHeader, "Bearer ")

		if keyString != a.MasterKey {
			span := trace.SpanFromContext(r.Context())
			span.SetStatus(codes.Error, "unauthorized master key")
			http.Error(w, "Acesso não autorizado", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}
