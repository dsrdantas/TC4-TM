# ToggleMaster - Tech Challenge Fase 4

Observabilidade Total, APM, Alertas Inteligentes e Self-Healing para a plataforma de Feature Flags ToggleMaster.

**Repositorio:** [github.com/rivachef/TC4-ToggleMaster](https://github.com/rivachef/TC4-ToggleMaster)

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
├── scripts/
│   └── tc4-tm.sh                   # Script unificado com todos os comandos (flags --*)
└── docs/
    ├── ROTEIRO-COMPLETO.md         # Guia passo-a-passo
    ├── RESUMO-EXECUTIVO.md         # Resumo executivo
    └── PIPELINE-EXPLAINED.md       # Arquitetura de observabilidade
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
                                │
                    ┌───────────▼───────────┐
                    │   OTel Collector      │
                    │   (Central Hub)       │
                    └───┬───────┬───────┬───┘
                        │       │       │
              ┌─────────▼──┐ ┌─▼────┐ ┌▼──────────┐
              │ Prometheus  │ │ Loki │ │ New Relic  │
              │ (Metricas)  │ │(Logs)│ │  (Traces)  │
              └──────┬──────┘ └──┬───┘ └─────┬─────┘
                     │           │           │
                     └─────┬─────┘           │
                     ┌─────▼─────┐           │
                     │  Grafana  │           │
                     │(Dashboard)│    Service Map
                     └─────┬─────┘  Distributed Tracing
                           │
                    ┌──────▼──────┐
                    │   Alertas   │
                    │ Prometheus  │
                    │   Rules     │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐ ┌───▼───┐ ┌─────▼──────┐
        │ OpsGenie  │ │Discord│ │GitHub Action│
        │(Incidente)│ │(Chat) │ │(Self-Heal)  │
        └───────────┘ └───────┘ └─────────────┘
```

---

## Stack de Tecnologias (Fase 4)

| Camada | Tecnologia | Funcao |
|--------|-----------|--------|
| Metricas | **Prometheus** (kube-prometheus-stack) | Armazenamento e consulta de metricas |
| Logs | **Loki** + Promtail | Centralizacao de logs dos conteineres |
| Visualizacao | **Grafana** | Dashboard customizado + alertas |
| Telemetria | **OpenTelemetry Collector** | Hub central: recebe, processa e exporta metricas/logs/traces |
| APM | **New Relic** (OTLP) | Distributed tracing + Service Map |
| Incidentes | **OpsGenie** | Gerenciamento de incidentes (P1 automatico) |
| ChatOps | **Discord** | Notificacoes de alertas e self-healing |
| Self-Healing | **GitHub Actions** (repository_dispatch) | `kubectl rollout restart` automatico |
| Instrumentacao (Go) | OTel SDK + HTTP middleware | Traces, metricas, propagacao de contexto |
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
- [OpsGenie](https://www.atlassian.com/software/opsgenie/pricing) - free tier (5 usuarios)
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

# OpsGenie + Discord (Alertmanager)
# Editar gitops/monitoring/alerting/alertmanager-config.yaml com suas chaves
```

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

# Acessar Grafana
kubectl get svc prometheus-grafana -n monitoring
# User: admin / Pass: togglemaster2024
```

---

## Testar o Fluxo de Incidente (Demo)

```bash
# 1. Injetar falha (escala servico para 0)
./scripts/self-healing/inject-fault.sh auth-service

# 2. Observar no Grafana: alerta dispara (~2-5 min)
# 3. OpsGenie: incidente P1 criado automaticamente
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

## Documentacao

- [Roteiro Completo](docs/ROTEIRO-COMPLETO.md) - Passo a passo detalhado do setup
- [Resumo Executivo](docs/RESUMO-EXECUTIVO.md) - Visao geral e conformidade com requisitos
- [Arquitetura de Observabilidade](docs/PIPELINE-EXPLAINED.md) - Como funciona o pipeline de telemetria
