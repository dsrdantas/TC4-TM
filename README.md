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
│   ├── auth-service/               # Go 1.23 + OTel SDK (porta 8001)
│   ├── flag-service/               # Python 3.12 + OTel auto-instrumentation (porta 8002)
│   ├── targeting-service/          # Python 3.12 + OTel auto-instrumentation (porta 8003)
│   ├── evaluation-service/         # Go 1.23 + OTel SDK (porta 8004)
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
│   ├── setup-full.sh               # Setup completo (inclui monitoring)
│   ├── install-monitoring.sh       # [FASE 4] Instala stack via Helm
│   ├── self-healing/               # [FASE 4] Scripts de teste e fault injection
│   │   ├── test-self-healing.sh
│   │   └── inject-fault.sh
│   ├── generate-secrets.sh
│   ├── apply-secrets.sh
│   ├── generate-api-key.sh
│   └── update-aws-credentials.sh
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
./scripts/setup-full.sh
```
Este script executa 10 passos: secrets, ArgoCD, Docker build, GitOps, NGINX Ingress, **monitoring stack** (Prometheus + Loki + Grafana + OTel Collector) e New Relic secret.

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

## Documentacao

- [Roteiro Completo](docs/ROTEIRO-COMPLETO.md) - Passo a passo detalhado do setup
- [Resumo Executivo](docs/RESUMO-EXECUTIVO.md) - Visao geral e conformidade com requisitos
- [Arquitetura de Observabilidade](docs/PIPELINE-EXPLAINED.md) - Como funciona o pipeline de telemetria
