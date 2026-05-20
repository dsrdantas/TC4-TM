# ToggleMaster - Tech Challenge Fase 4

Observabilidade Total, APM, Alertas Inteligentes e Self-Healing para a plataforma de Feature Flags ToggleMaster.

**Repositorio:** [github.com/dsrdantas/TC4-TM](https://github.com/dsrdantas/TC4-TM)

> **Projeto Evolutivo:** Este repositorio e a continuacao das Fases 1, 2 e 3.
> A base completa (5 microsservicos, Terraform, CI/CD, GitOps) esta funcional
> e agora recebe a camada de **observabilidade e resposta ativa a incidentes**.

---

## Estrutura do Projeto

```
TC4-ToggleMaster/
├── terraform/                      # IaC - Infraestrutura AWS (Fase 3)
│   └── modules/                    # networking, eks, databases, messaging, ecr
├── microservices/                  # 5 microsservicos instrumentados com OTel
│   ├── auth-service/               # Go 1.24 + OTel SDK (porta 8001)
│   ├── flag-service/               # Python 3.12 + OTel auto-instrumentation (porta 8002)
│   ├── targeting-service/          # Python 3.12 + OTel auto-instrumentation (porta 8003)
│   ├── evaluation-service/         # Go 1.24 + OTel SDK (porta 8004)
│   └── analytics-service/          # Python 3.12 + OTel auto-instrumentation (porta 8005)
├── gitops/                         # Manifestos K8s (ArgoCD)
│   ├── auth-service/               # Deployment, Service, DB init
│   ├── flag-service/               # Deployment, Service, DB init
│   ├── targeting-service/          # Deployment, Service, DB init
│   ├── evaluation-service/         # Deployment, Service, HPA
│   ├── analytics-service/          # Deployment, Service
│   ├── monitoring/                 # [FASE 4] Stack de observabilidade
│   │   ├── namespace.yaml
│   │   ├── prometheus/             # kube-prometheus-stack Helm values
│   │   ├── loki/                   # Loki Helm values
│   │   ├── promtail/               # Promtail Helm values
│   │   ├── grafana/                # Dashboard customizado
│   │   │   └── dashboards/
│   │   │       └── togglemaster-overview.json
│   │   ├── otel-collector/         # OpenTelemetry Collector config
│   │   └── alerting/               # PrometheusRules + Alertmanager config
│   ├── namespace.yaml
│   └── ingress.yaml
├── argocd/                         # ArgoCD AppProject + Applications
├── .github/workflows/
│   ├── ci-*-service.yaml           # Pipelines CI/CD (Fase 3)
│   └── self-healing.yaml           # [FASE 4] Automacao de self-healing
└── scripts/
    └── tc4-tm.sh                   # Script unificado com todos os comandos (flags --*)
```

---

## Arquitetura de Observabilidade (Fase 4)

```
┌─────────────────────────────────────────────────────────────┐
│                    5 Microsservicos                          │
│  auth  │  flag  │  targeting  │  evaluation  │  analytics   │
│  (Go)  │  (Py)  │    (Py)     │    (Go)      │    (Py)      │
│  OTel  │  OTel  │   OTel      │   OTel       │   OTel       │
│  SDK   │  Auto  │   Auto      │   SDK        │   Auto       │
└────┬───┴────┬───┴──────┬──────┴──────┬───────┴──────┬───────┘
     │        │          │             │              │
     └────────┴──────────┴──────┬──────┴──────────────┘
                                │  (traces + metricas + logs via OTLP)
                    ┌───────────▼───────────┐
                    │   OTel Collector      │
                    │   (Central Hub)       │
                    └───┬───────┬───────┬───┘
                        │       │       │
              ┌─────────▼──┐ ┌─▼────┐ ┌▼──────────────────┐
              │ Prometheus  │ │ Loki │ │     New Relic      │
              │ (Metricas)  │ │(Logs)│ │ Traces + Metricas  │
              └──────┬──────┘ └──┬───┘ │ Logs + Service Map │
                     │           │     └────────────────────┘
                     └─────┬─────┘
                     ┌─────▼─────┐
                     │  Grafana  │
                     │(Dashboard)│
                     │admin/     │
                     │tc4-tm     │
                     └─────┬─────┘
                           │
                    ┌──────▼──────┐
                    │   Alertas   │
                    │ Prometheus  │
                    │   Rules     │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼──────┐ ┌──▼────┐ ┌─────▼──────┐
        │ PagerDuty  │ │Discord│ │GitHub Action│
        │(Incidentes)│ │(Chat) │ │(Self-Heal)  │
        └────────────┘ └───────┘ └─────────────┘

  Roteamento Alertmanager:
  - critical (ex: PodCrashLooping) → PagerDuty + Discord
  - warning                        → Discord
```

---

## Stack de Tecnologias (Fase 4)

| Camada | Tecnologia | Funcao |
|--------|-----------|--------|
| Metricas | **Prometheus** (kube-prometheus-stack) | Armazenamento e consulta de metricas |
| Logs | **Loki** + Promtail | Centralizacao de logs dos conteineres |
| Visualizacao | **Grafana** (admin / tc4-tm) | Dashboard customizado + alertas |
| Telemetria | **OpenTelemetry Collector** | Hub central: recebe, processa e exporta metricas/logs/traces |
| APM | **New Relic** (OTLP) | Distributed tracing + Service Map + Logs + Erros |
| Incidentes | **PagerDuty** | Gerenciamento de incidentes P1 automatico via routing key |
| ChatOps | **Discord** | Notificacoes de alertas e self-healing |
| Self-Healing | **GitHub Actions** (repository_dispatch) | `kubectl rollout restart` automatico |
| Instrumentacao (Go) | OTel SDK + HTTP middleware | Traces, metricas, propagacao de contexto, DB spans |
| Instrumentacao (Python) | OTel auto-instrumentation | Flask, requests, psycopg2, botocore |

---

## Pre-requisitos

| Ferramenta | Versao Minima | Finalidade |
|------------|--------------|------------|
| AWS CLI | v2 | Acesso a AWS |
| Terraform | >= 1.5 | Provisionamento de infra |
| kubectl | >= 1.28 | Gerenciamento do cluster |
| Helm | >= 3.12 | Instalacao de charts (monitoring) |
| Docker | >= 24 | Build de imagens |
| Git | >= 2.0 | Versionamento |
| gh CLI | >= 2.0 | Testes de self-healing |

**Contas externas necessarias:**
- [New Relic](https://newrelic.com/signup) - conta gratuita (100 GB/mes)
- [PagerDuty](https://www.pagerduty.com/sign-up/) - free trial (14 dias) ou developer plan
- Discord - servidor com webhook configurado

---

## Guia Rapido - Setup Completo

### 1. Configurar credenciais AWS + Terraform (Fase 3)
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

cd terraform
terraform init && terraform apply -auto-approve
```

### 2. Setup automatizado (inclui monitoring)
```bash
./scripts/tc4-tm.sh --setup-full
```
Este comando executa 12 passos: Terraform apply, kubectl config, secrets, ArgoCD, Docker build/push ECR, GitOps, NGINX Ingress, **monitoring stack** (Prometheus + Loki + Grafana + OTel Collector) e geracao da API key.

Outros comandos disponíveis:
```bash
./scripts/tc4-tm.sh --terraform-bootstrap   # Cria bucket S3 + tabela DynamoDB para state
./scripts/tc4-tm.sh --terraform-apply       # Provisiona infraestrutura AWS
./scripts/tc4-tm.sh --install-monitoring    # Instala stack Prometheus/Loki/Grafana via Helm
./scripts/tc4-tm.sh --generate-secrets      # Gera secrets Kubernetes
./scripts/tc4-tm.sh --apply-secrets         # Aplica secrets no cluster
./scripts/tc4-tm.sh --generate-api-key      # Cria e exibe API key de servico
./scripts/tc4-tm.sh --update-aws-credentials # Atualiza credenciais AWS no cluster
./scripts/tc4-tm.sh --inject-fault          # Injeta falha para teste de self-healing
./scripts/tc4-tm.sh --test-self-healing     # Dispara workflow de self-healing via gh CLI
./scripts/tc4-tm.sh --destroy-all           # Remove toda a infraestrutura
./scripts/tc4-tm.sh --help                  # Lista todos os comandos
```

### 3. Configurar secrets externos
```bash
# New Relic
cp gitops/monitoring/newrelic-secret.yaml.example gitops/monitoring/newrelic-secret.yaml
# Editar com sua license key
kubectl apply -f gitops/monitoring/newrelic-secret.yaml

# PagerDuty + Discord (Alertmanager)
# Editar gitops/monitoring/alerting/alertmanager-secret.yaml com suas chaves:
#   pagerduty_routing_key: <sua routing key do PagerDuty>
#   discord_webhook_url:   <seu webhook Discord>
kubectl apply -f gitops/monitoring/alerting/alertmanager-secret.yaml
```

**Como obter a PagerDuty Routing Key:**
1. PagerDuty > Services > seu servico > Integrations > Add Integration
2. Escolha "Events API v2"
3. Copie a **Integration Key** (essa e a routing key)

### 4. Configurar GitHub Secrets (para self-healing)
No GitHub: Settings > Secrets and variables > Actions:

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Access Key |
| `AWS_SECRET_ACCESS_KEY` | Secret Key |
| `AWS_SESSION_TOKEN` | Session Token |
| `ECR_REGISTRY` | `<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com` |
| `DISCORD_WEBHOOK_URL` | URL do webhook Discord |

### 5. Verificar tudo
```bash
# Pods dos microsservicos
kubectl get pods -n togglemaster

# Pods do monitoring
kubectl get pods -n monitoring

# Acessar Grafana (port-forward se nao tiver ingress)
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# Abrir http://localhost:3000
# Usuario: admin
# Senha:   tc4-tm

# Acessar New Relic APM
# https://one.newrelic.com > APM & Services > togglemaster-*
```

---

## Testar o Fluxo de Incidente (Demo)

```bash
# 1. Injetar falha (escala servico para 0 replicas)
./scripts/tc4-tm.sh --inject-fault

# 2. Observar no Grafana: alerta PodCrashLooping dispara (~2-5 min)
# 3. PagerDuty: incidente criado automaticamente
# 4. Discord: notificacao recebida
# 5. GitHub Actions: self-healing executa rollout restart
# 6. Servico restaurado automaticamente
```

---

## Problemas Encontrados e Correcoes

Registro dos problemas identificados durante a execucao real do projeto e as correcoes aplicadas.

### 1. Terraform — state lock sem backend pre-criado

**Problema:** `terraform init` falha com `ResourceNotFoundException` porque o bucket S3 e a tabela DynamoDB do backend precisam existir antes do `init`.

**Correcao:** Adicionado o comando `--terraform-bootstrap` em `scripts/tc4-tm.sh` que cria idempotentemente o bucket `tc4-tm` (versionamento + criptografia + bloqueio de acesso publico) e a tabela DynamoDB `tc4-terraform-lock` antes de qualquer operacao Terraform. O `--setup-full` agora chama bootstrap automaticamente como passo [1/12].

---

### 2. ECR — endereco nao atualizado nos deployments

**Problema:** O script de atualizacao do endereco ECR usava `grep -q '<AWS_ACCOUNT_ID>'` para decidir se devia substituir. Quando o arquivo ja tinha um account ID real (de execucao anterior), o grep retornava false e o sed nao era executado, deixando o endereco errado.

**Correcao:** Substituido por dois passes de `sed` encadeados: o primeiro troca o placeholder literal `<AWS_ACCOUNT_ID>.dkr.ecr`, o segundo usa regex `-E "[0-9]{12}\.dkr\.ecr"` para substituir qualquer account ID de 12 digitos. O resultado e idempotente independentemente do estado anterior do arquivo.

---

### 3. `generate-api-key` — "Acesso nao autorizado"

**Problema:** O script lia `MASTER_KEY` via `kubectl get secret ... -o jsonpath` + `base64 -d`. O `base64 -d` adicionava `\n` ao final, causando mismatch com a chave que o pod tinha em memoria. Alem disso, se `generate-secrets` era executado novamente criava uma nova chave aleatoria sem reiniciar o pod, deixando secret e pod dessincronizados.

**Correcao:** O script agora le `MASTER_KEY` diretamente do ambiente do pod via `kubectl exec ... -- printenv MASTER_KEY | tr -d '\n\r'`, garantindo que a chave usada na chamada HTTP e exatamente a mesma que o processo tem em memoria. O `--apply-secrets` foi complementado com `kubectl rollout restart` automatico do auth-service.

---

### 4. Servicos Python — OTel exportando para porta errada

**Problema:** Os deployments dos servicos Python (flag-service, targeting-service, analytics-service) apontavam `OTEL_EXPORTER_OTLP_ENDPOINT` para a porta `4317` com protocolo `http://`. A porta 4317 e gRPC; usar `http://` nela gera `StatusCode.UNAVAILABLE` e o OTel auto-instrumentado nao exporta nada.

**Correcao:** Atualizado em `gitops/flag-service/deployment.yaml`, `gitops/targeting-service/deployment.yaml` e `gitops/analytics-service/deployment.yaml`:
- Porta `4317` → `4318`
- Adicionada variavel `OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf"`

Os servicos Go (auth-service, evaluation-service) permanecem na porta 4317 pois usam o SDK gRPC nativo.

---

### 5. auth-service — CrashLoopBackOff na inicializacao

**Problema:** `db.Ping()` (sem timeout) bloqueava indefinidamente enquanto o RDS ainda nao estava acessivel. O liveness probe matava o pod apos 15 s, gerando CrashLoopBackOff antes de o servico conseguir iniciar.

**Correcoes aplicadas:**
- `microservices/auth-service/main.go`: substituido `db.Ping()` por `db.PingContext` com `context.WithTimeout` de 10 s, retornando erro descritivo em vez de travar.
- `gitops/auth-service/deployment.yaml`: `livenessProbe.initialDelaySeconds` aumentado de 15 s para 30 s e `readinessProbe.failureThreshold` aumentado para 6, dando tempo suficiente para a conexao com RDS ser estabelecida.

---

### 6. evaluation-service — distributed tracing quebrado

**Problema:** O `evaluation-service` chamava `flag-service` e `targeting-service` usando `http.NewRequest` (sem contexto), o que cortava a propagacao do trace W3C. Os spans filhos nao apareciam no New Relic Service Map.

**Correcoes aplicadas:**
- `microservices/evaluation-service/main.go`: cliente HTTP criado com `otelhttp.NewTransport` para injetar automaticamente os headers `traceparent`/`tracestate` em todas as chamadas de saida. Adicionado timeout de 5 s no cliente.
- `microservices/evaluation-service/evaluator.go`: todas as funcoes (`getDecision`, `getCombinedFlagInfo`, `fetchFromServices`, `fetchFlag`, `fetchRule`) refatoradas para receber e propagar `context.Context`. Chamadas HTTP migradas para `http.NewRequestWithContext`.
- `microservices/evaluation-service/handlers.go`: `evaluationHandler` passa `r.Context()` para a cadeia de avaliacao.
- `microservices/evaluation-service/main.go`: ping do Redis migrado para `rdb.Ping(ctx)` com timeout de 10 s.

---

### 7. golangci-lint — errcheck em telemetry.go

**Problema:** O linter `errcheck` sinalizava retornos de erro nao verificados nas chamadas `tp.Shutdown(ctx)` e `mp.Shutdown(ctx)` em ambos os servicos Go.

**Correcao:** Todos os `Shutdown` agora verificam o erro e registram via `log.Printf`:
- `microservices/evaluation-service/telemetry.go`
- `microservices/auth-service/telemetry.go`

---

### 8. CVE-2026-33186 — vulnerabilidade critica no grpc-go

**Problema:** Trivy identificou `google.golang.org/grpc v1.65.0` (dependencia indireta do OTel) com CVE-2026-33186 (CRITICAL): authorization bypass via validacao incorreta de path HTTP/2.

**Correcao:** Executado `go get google.golang.org/grpc@v1.79.3` em ambos os servicos Go, atualizando tambem OTel SDK `v1.28.0 → v1.39.0` e demais dependencias transitivas. A versao minima do Go nos `go.mod` subiu para `1.24.0`.

---

### 9. golangci-lint incompativel com Go 1.24

**Problema:** A atualizacao do grpc para v1.79.3 forcou o `go.mod` para `go 1.24.0`. O golangci-lint `v1.61` nos workflows de CI foi compilado com Go 1.23 e rejeita modulos com `go >= 1.24.0`.

**Correcao:** Atualizado em `.github/workflows/ci-auth-service.yaml` e `.github/workflows/ci-evaluation-service.yaml`:
- `go-version: '1.23'` → `'1.24'` (em todos os steps)
- `version: v1.61` → `v1.64` (golangci-lint)

---

### 10. Dockerfile — builder incompativel com Go 1.24

**Problema:** Os Dockerfiles usavam `golang:1.23-alpine3.20` como imagem de build. Com `go.mod` exigindo `go 1.24.0`, o `go mod tidy` dentro do container falhava com `go.mod requires go >= 1.24.0 (running go 1.23.9; GOTOOLCHAIN=local)`.

**Correcao:** Atualizado `FROM golang:1.23-alpine3.20` → `FROM golang:1.24-alpine3.20` nos Dockerfiles de:
- `microservices/evaluation-service/Dockerfile`
- `microservices/auth-service/Dockerfile`

---

### 11. New Relic — databases, logs e erros nao apareciam

**Problema:** O New Relic nao exibia: (a) chamadas ao banco de dados nos traces; (b) logs dos microsservicos; (c) erros sinalizados nas respostas HTTP.

**Causas e correcoes:**

**(a) Banco de dados invisivel nos traces (servicos Go):**
A biblioteca `otelsql` foi avaliada mas descartada porque sua versao `@latest` puxava dependencias incompativeis com Go 1.24 (`otelsql → otel v1.42 → golang.org/x/sys v0.40+`). Solucao: spans de banco de dados criados manualmente com `otel.Tracer("auth-service").Start(ctx, "db.api_keys.select", trace.WithSpanKind(trace.SpanKindClient))` e atributos `db.system`, `db.operation`, `db.sql.table` em `microservices/auth-service/handlers.go`.

**(b) Logs nao apareciam no New Relic:**
O pipeline `logs` do OTel Collector exportava apenas para o Loki (`otlphttp/loki`). Correcao: adicionado `otlphttp/newrelic` como exporter adicional no pipeline de logs em `gitops/monitoring/otel-collector/values.yaml`.

**(c) Erros nao rastreados:**
Os handlers Go nao chamavam `span.RecordError(err)` + `span.SetStatus(codes.Error, msg)`, entao o New Relic nao contabilizava as falhas. Correcao: todos os caminhos de erro em `microservices/auth-service/handlers.go` e `microservices/evaluation-service/handlers.go` agora registram o erro no span ativo.

---

### 12. flake8 — violacoes nos microsservicos Python

**Problema:** Os tres microsservicos Python falhavam no CI com 44+ violacoes flake8: `E302` (linhas em branco insuficientes antes de funcoes), `W291`/`W293` (espacos em branco no final de linhas), `E701` (multiplas instrucoes na mesma linha), `F401` (importacao nao utilizada), `W292` (sem newline no final do arquivo).

**Correcao:** Reescrita completa dos tres arquivos:
- `microservices/flag-service/app.py` — 44 violacoes corrigidas
- `microservices/targeting-service/app.py` — removido tambem `import json` nao utilizado (a serializacao e feita pelo `Json` do psycopg2)
- `microservices/analytics-service/app.py` — espacos em branco e ausencia de linhas em branco corrigidos

---

### 13. auth-service — pod nao conectava ao RDS

**Problema:** O pod do auth-service inicializava mas falhava ao conectar ao banco RDS com erro de autenticacao/SSL. Duas causas:
1. `DATABASE_URL` nao incluia `?sslmode=require`, obrigatorio para conexoes RDS com pgx/lib-pq.
2. A senha do banco continha caracteres especiais que nao eram URL-encoded, corrompendo a connection string.

**Correcao em `scripts/tc4-tm.sh`:**
```bash
# URL-encoding da senha antes de montar a DATABASE_URL
DB_PASSWORD_ENCODED=$(python3 -c \
  "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" \
  "$DB_PASSWORD")

# sslmode=require adicionado em todas as tres URLs
DATABASE_URL: "postgres://tm_user:${DB_PASSWORD_ENCODED}@${AUTH_DB_ENDPOINT}:5432/auth_db?sslmode=require"
```

O arquivo `gitops/auth-service/secret.yaml.example` tambem foi atualizado para refletir o formato correto com `?sslmode=require`.

**Causa raiz de infraestrutura:** Os managed node groups do EKS usam o security group auto-criado (`cluster_security_group_id`), nao o SG customizado `eks_nodes`. O Terraform ja havia sido corrigido em fase anterior com `aws_security_group_rule` referenciando `module.eks.cluster_security_group_id` para permitir acesso dos nodes ao RDS e ao Redis.
