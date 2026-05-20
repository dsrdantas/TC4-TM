#!/bin/bash
###############################################################################
# tc4-tm.sh
#
# Ponto de entrada unificado para todos os comandos do ToggleMaster (TC4).
#
# Uso:
#   ./scripts/tc4-tm.sh <flag> [args]
#
# Flags disponíveis:
#   --setup-full              Setup completo do ambiente (orquestra tudo)
#   --install-monitoring      Instala Prometheus + Loki + Grafana + OTel
#   --generate-secrets        Gera secrets a partir dos outputs do Terraform
#   --apply-secrets           Aplica os secrets gerados no cluster K8s
#   --generate-api-key        Gera SERVICE_API_KEY via auth-service
#   --update-aws-credentials  Atualiza credenciais AWS nos secrets (a cada 4h)
#   --destroy-all             Destrói toda a infraestrutura (K8s + Terraform)
#   --inject-fault [service]  Injeta falha em um serviço para testar alertas
#   --test-self-healing [svc] Dispara o workflow de self-healing via GitHub
#   --help                    Exibe esta mensagem de ajuda
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Helpers de log (compartilhados por todos os comandos)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

  ████████╗ ██████╗  ██████╗  ██████╗ ██╗     ███████╗
     ██╔══╝██╔═══██╗██╔════╝ ██╔════╝ ██║     ██╔════╝
     ██║   ██║   ██║██║  ███╗██║  ███╗██║     █████╗
     ██║   ██║   ██║██║   ██║██║   ██║██║     ██╔══╝
     ██║   ╚██████╔╝╚██████╔╝╚██████╔╝███████╗███████╗
     ╚═╝    ╚═════╝  ╚═════╝  ╚═════╝ ╚══════╝╚══════╝
         ToggleMaster TC4 — Observability & Self-Healing

Uso:
  ./scripts/tc4-tm.sh <flag> [args]

Flags:
  --setup-full              Setup completo do ambiente (1ª execução)
                            Orquestra: Terraform → kubectl → secrets
                            → ArgoCD → Docker build → K8s deployments
                            → monitoring stack

  --terraform-bootstrap     Cria o S3 bucket e a tabela DynamoDB usados
                            como backend do Terraform (roda antes do init)
                            Idempotente: seguro de re-executar

  --terraform-apply         Provisiona a infraestrutura AWS via Terraform:
                            VPC, EKS, RDS (x3), Redis, SQS, ECR (x5)
                            Inclui bootstrap automático do backend
                            Requer terraform/terraform.tfvars preenchido

  --install-monitoring      Instala a stack de monitoramento via Helm:
                            Prometheus + Alertmanager + Loki + Promtail
                            + OpenTelemetry Collector + Grafana dashboard

  --generate-secrets        Lê outputs do Terraform e gera todos os
                            secret.yaml em gitops/ (não aplica no cluster)

  --apply-secrets           Aplica os secret.yaml gerados no cluster K8s
                            (requer generate-secrets executado antes)

  --generate-api-key        Gera SERVICE_API_KEY via auth-service e
                            atualiza o secret do evaluation-service

  --update-aws-credentials  Atualiza credenciais AWS nos secrets do
                            evaluation-service e analytics-service
                            (necessário a cada nova sessão AWS Academy ~4h)

  --destroy-all             Destrói toda a infraestrutura:
                            K8s resources → LBs → ENIs → terraform destroy

  --inject-fault [service]  Injeta falha proposital em um serviço para
                            disparar alertas e testar o self-healing
                            Padrão: auth-service
                            Ex: --inject-fault evaluation-service

  --test-self-healing [svc] Dispara o workflow de self-healing via
                            GitHub repository_dispatch (requer gh CLI)
                            Padrão: auth-service
                            Ex: --test-self-healing flag-service

  --help                    Exibe esta mensagem

Exemplos:
  # Provisionar infraestrutura apenas
  ./scripts/tc4-tm.sh --terraform-apply

  # Setup completo (primeira vez, inclui terraform)
  ./scripts/tc4-tm.sh --setup-full
  ./scripts/tc4-tm.sh --install-monitoring
  ./scripts/tc4-tm.sh --update-aws-credentials
  ./scripts/tc4-tm.sh --inject-fault auth-service
  ./scripts/tc4-tm.sh --test-self-healing auth-service
  ./scripts/tc4-tm.sh --destroy-all

EOF
}

###############################################################################
# --generate-secrets
###############################################################################
cmd_generate_secrets() {
  local TERRAFORM_DIR="$PROJECT_DIR/terraform"
  local GITOPS_DIR="$PROJECT_DIR/gitops"

  echo "============================================"
  echo "  ToggleMaster - Gerador de Secrets"
  echo "============================================"
  echo ""

  echo ">>> Lendo outputs do Terraform..."
  if ! (cd "$TERRAFORM_DIR" && terraform output -json > /dev/null 2>&1); then
    echo "ERRO: Nao foi possivel ler terraform output."
    echo "Verifique se 'terraform apply' foi executado com sucesso."
    exit 1
  fi

  local TF_OUTPUT
  TF_OUTPUT=$(cd "$TERRAFORM_DIR" && terraform output -json)

  local AUTH_DB_ENDPOINT FLAG_DB_ENDPOINT TARGETING_DB_ENDPOINT REDIS_ENDPOINT SQS_QUEUE_URL
  AUTH_DB_ENDPOINT=$(echo "$TF_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['auth_db_endpoint']['value'].split(':')[0])")
  FLAG_DB_ENDPOINT=$(echo "$TF_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['flag_db_endpoint']['value'].split(':')[0])")
  TARGETING_DB_ENDPOINT=$(echo "$TF_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['targeting_db_endpoint']['value'].split(':')[0])")
  REDIS_ENDPOINT=$(echo "$TF_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['redis_endpoint']['value'])")
  SQS_QUEUE_URL=$(echo "$TF_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['sqs_queue_url']['value'])")

  echo "  auth_db:    $AUTH_DB_ENDPOINT"
  echo "  flag_db:    $FLAG_DB_ENDPOINT"
  echo "  targeting:  $TARGETING_DB_ENDPOINT"
  echo "  redis:      $REDIS_ENDPOINT"
  echo "  sqs:        $SQS_QUEUE_URL"
  echo ""

  echo ">>> Lendo db_password do terraform.tfvars..."
  if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    echo "ERRO: terraform.tfvars nao encontrado."
    echo "Crie com: cp terraform.tfvars.example terraform.tfvars"
    exit 1
  fi

  local DB_PASSWORD
  DB_PASSWORD=$(grep 'db_password' "$TERRAFORM_DIR/terraform.tfvars" | python3 -c "import sys; print(sys.stdin.read().split('\"')[1])")

  if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "<SUA_SENHA_SEGURA>" ]; then
    echo "ERRO: db_password nao definida no terraform.tfvars"
    exit 1
  fi
  echo "  db_password: ****${DB_PASSWORD: -4}"
  echo ""

  echo ">>> Verificando credenciais AWS..."
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SESSION_TOKEN" ]; then
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || echo "")
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERRO: Credenciais AWS nao encontradas (nem em env vars, nem em aws configure)."
    echo 'Execute: export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." AWS_SESSION_TOKEN="..."'
    echo "Ou configure via: aws configure"
    exit 1
  fi
  echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:12}..."
  echo ""

  local MASTER_KEY="${MASTER_KEY:-$(openssl rand -hex 32)}"
  echo ">>> MASTER_KEY: ${MASTER_KEY:0:8}..."
  echo ""

  echo ">>> Gerando secrets em $GITOPS_DIR ..."
  echo ""

  # URL-encoda a senha para evitar que caracteres especiais (@, #, %, /) quebrem a URL de conexão
  local DB_PASSWORD_ENCODED
  DB_PASSWORD_ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")

  cat > "$GITOPS_DIR/auth-service/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  POSTGRES_PASSWORD: "$DB_PASSWORD"
  MASTER_KEY: "$MASTER_KEY"
  DATABASE_URL: "postgres://tm_user:${DB_PASSWORD_ENCODED}@${AUTH_DB_ENDPOINT}:5432/auth_db?sslmode=require"
EOF
  echo "  [OK] gitops/auth-service/secret.yaml"

  cat > "$GITOPS_DIR/auth-service/db/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: auth-db-secret
  namespace: togglemaster
type: Opaque
stringData:
  POSTGRES_HOST: "$AUTH_DB_ENDPOINT"
  POSTGRES_DB: "auth_db"
  POSTGRES_USER: "tm_user"
  POSTGRES_PASSWORD: "$DB_PASSWORD"
EOF
  echo "  [OK] gitops/auth-service/db/secret.yaml"

  cat > "$GITOPS_DIR/flag-service/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: flag-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  POSTGRES_PASSWORD: "$DB_PASSWORD"
  DATABASE_URL: "postgres://tm_user:${DB_PASSWORD_ENCODED}@${FLAG_DB_ENDPOINT}:5432/flag_db?sslmode=require"
EOF
  echo "  [OK] gitops/flag-service/secret.yaml"

  cat > "$GITOPS_DIR/flag-service/db/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: flag-db-secret
  namespace: togglemaster
type: Opaque
stringData:
  POSTGRES_HOST: "$FLAG_DB_ENDPOINT"
  POSTGRES_DB: "flag_db"
  POSTGRES_USER: "tm_user"
  POSTGRES_PASSWORD: "$DB_PASSWORD"
EOF
  echo "  [OK] gitops/flag-service/db/secret.yaml"

  cat > "$GITOPS_DIR/targeting-service/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: targeting-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  POSTGRES_PASSWORD: "$DB_PASSWORD"
  DATABASE_URL: "postgres://tm_user:${DB_PASSWORD_ENCODED}@${TARGETING_DB_ENDPOINT}:5432/targeting_db?sslmode=require"
EOF
  echo "  [OK] gitops/targeting-service/secret.yaml"

  cat > "$GITOPS_DIR/targeting-service/db/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: targeting-db-secret
  namespace: togglemaster
type: Opaque
stringData:
  POSTGRES_HOST: "$TARGETING_DB_ENDPOINT"
  POSTGRES_DB: "targeting_db"
  POSTGRES_USER: "tm_user"
  POSTGRES_PASSWORD: "$DB_PASSWORD"
EOF
  echo "  [OK] gitops/targeting-service/db/secret.yaml"

  cat > "$GITOPS_DIR/evaluation-service/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  REDIS_URL: "redis://${REDIS_ENDPOINT}:6379"
  SERVICE_API_KEY: "PLACEHOLDER_GERAR_DEPOIS"
  AWS_SQS_URL: "$SQS_QUEUE_URL"
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_SESSION_TOKEN: "$AWS_SESSION_TOKEN"
EOF
  echo "  [OK] gitops/evaluation-service/secret.yaml"

  cat > "$GITOPS_DIR/analytics-service/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: analytics-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  AWS_SQS_URL: "$SQS_QUEUE_URL"
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_SESSION_TOKEN: "$AWS_SESSION_TOKEN"
EOF
  echo "  [OK] gitops/analytics-service/secret.yaml"

  echo ""
  echo "============================================"
  echo "  8 secrets gerados com sucesso!"
  echo "============================================"
  echo ""
  echo "Proximo passo - aplicar no cluster:"
  echo "  ./scripts/tc4-tm.sh --apply-secrets"
  echo ""
  echo "NOTA: O SERVICE_API_KEY do evaluation-service sera"
  echo "gerado automaticamente apos o auth-service subir."
  echo "Execute: ./scripts/tc4-tm.sh --generate-api-key"
  echo ""
}

###############################################################################
# --apply-secrets
###############################################################################
cmd_apply_secrets() {
  local GITOPS_DIR="$PROJECT_DIR/gitops"

  echo "============================================"
  echo "  ToggleMaster - Aplicar Secrets no Cluster"
  echo "============================================"
  echo ""

  echo ">>> Verificando conexao com o cluster..."
  if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "ERRO: Nao conectado ao cluster. Execute:"
    echo "  aws eks update-kubeconfig --name togglemaster-cluster --region us-east-1"
    exit 1
  fi
  echo "  [OK] Conectado ao cluster"
  echo ""

  echo ">>> Garantindo namespace togglemaster..."
  kubectl apply -f "$GITOPS_DIR/namespace.yaml"
  echo ""

  echo ">>> Aplicando secrets..."
  local SECRETS=(
    "auth-service/secret.yaml"
    "auth-service/db/secret.yaml"
    "flag-service/secret.yaml"
    "flag-service/db/secret.yaml"
    "targeting-service/secret.yaml"
    "targeting-service/db/secret.yaml"
    "evaluation-service/secret.yaml"
    "analytics-service/secret.yaml"
  )

  for secret in "${SECRETS[@]}"; do
    local FILE="$GITOPS_DIR/$secret"
    if [ -f "$FILE" ]; then
      kubectl apply -f "$FILE"
      echo "  [OK] $secret"
    else
      echo "  [SKIP] $secret (arquivo nao encontrado - execute --generate-secrets primeiro)"
    fi
  done

  echo ""
  echo ">>> Verificando secrets criados..."
  echo ""
  kubectl get secrets -n togglemaster --no-headers | grep -v 'default-token' | grep -v 'sh.helm'
  echo ""

  echo "============================================"
  echo "  Secrets aplicados com sucesso!"
  echo "============================================"
  echo ""
  echo "Proximo passo:"
  echo "  kubectl apply -f argocd/applications.yaml"
  echo ""
}

###############################################################################
# --generate-api-key
###############################################################################
cmd_generate_api_key() {
  echo "============================================"
  echo "  ToggleMaster - Gerar SERVICE_API_KEY"
  echo "============================================"
  echo ""

  echo ">>> Verificando se auth-service esta Running..."
  local AUTH_STATUS
  AUTH_STATUS=$(kubectl get pods -n togglemaster -l app=auth-service -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

  if [ "$AUTH_STATUS" != "Running" ]; then
    echo "ERRO: auth-service nao esta Running (status: $AUTH_STATUS)"
    echo "Aguarde os pods subirem: kubectl get pods -n togglemaster -w"
    exit 1
  fi
  echo "  [OK] auth-service esta Running"
  echo ""

  if lsof -i :8001 > /dev/null 2>&1; then
    echo "  AVISO: Porta 8001 ja em uso. Tentando liberar..."
    kill $(lsof -t -i :8001) 2>/dev/null || true
    sleep 2
  fi

  echo ">>> Abrindo port-forward para auth-service..."
  kubectl port-forward svc/auth-service 8001:8001 -n togglemaster &
  local PF_PID=$!
  sleep 3

  echo ">>> Obtendo MASTER_KEY do pod em execucao..."
  # Lemos direto do env do pod para garantir o valor exato que ele usa em memoria.
  # Ler do secret pode retornar um valor desatualizado se o pod nao foi reiniciado
  # apos o ultimo apply-secrets.
  local AUTH_POD MASTER_KEY
  AUTH_POD=$(kubectl get pods -n togglemaster -l app=auth-service \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -n "$AUTH_POD" ]; then
    MASTER_KEY=$(kubectl exec -n togglemaster "$AUTH_POD" -- printenv MASTER_KEY 2>/dev/null | tr -d '\n\r')
  fi

  # Fallback: ler do secret com strip de newline
  if [ -z "$MASTER_KEY" ]; then
    MASTER_KEY=$(kubectl get secret auth-service-secret -n togglemaster \
      -o jsonpath='{.data.MASTER_KEY}' 2>/dev/null | base64 -d | tr -d '\n\r')
  fi

  if [ -z "$MASTER_KEY" ]; then
    kill "$PF_PID" 2>/dev/null || true
    echo "ERRO: MASTER_KEY nao encontrada (pod: $AUTH_POD)"
    exit 1
  fi
  echo "  [OK] MASTER_KEY: ${MASTER_KEY:0:8}... (lida do pod $AUTH_POD)"
  echo ""

  echo ">>> Gerando API key via auth-service..."
  local RESPONSE
  RESPONSE=$(curl -s -X POST http://localhost:8001/admin/keys \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -d '{"name": "evaluation-service"}')

  local API_KEY
  API_KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")

  kill "$PF_PID" 2>/dev/null || true

  if [ -z "$API_KEY" ]; then
    echo "ERRO: Nao foi possivel gerar a API key."
    echo "Resposta do auth-service: $RESPONSE"
    exit 1
  fi
  echo "  [OK] API Key gerada: ${API_KEY:0:15}..."
  echo ""

  echo ">>> Atualizando evaluation-service-secret com a nova API key..."
  local API_KEY_B64
  API_KEY_B64=$(echo -n "$API_KEY" | base64 | tr -d '\n')

  kubectl patch secret evaluation-service-secret -n togglemaster \
    -p "{\"data\":{\"SERVICE_API_KEY\":\"$API_KEY_B64\"}}"
  echo "  [OK] evaluation-service-secret atualizado"
  echo ""

  echo ">>> Reiniciando pods do evaluation-service..."
  kubectl rollout restart deployment/evaluation-service -n togglemaster
  kubectl rollout status deployment/evaluation-service -n togglemaster --timeout=120s
  echo ""

  echo "============================================"
  echo "  SERVICE_API_KEY configurada com sucesso!"
  echo "============================================"
  echo ""
  echo "API Key: $API_KEY"
  echo ""
  echo "Todos os servicos devem estar operacionais agora."
  echo "Verifique: kubectl get pods -n togglemaster"
  echo ""
}

###############################################################################
# --install-monitoring
###############################################################################
cmd_install_monitoring() {
  local MONITORING_DIR="$PROJECT_DIR/gitops/monitoring"

  echo "============================================"
  echo "  ToggleMaster - Monitoring Stack Installer"
  echo "  Phase 4: Observability & Self-Healing"
  echo "============================================"
  echo ""

  echo "[1/6] Creating monitoring namespace..."
  kubectl apply -f "$MONITORING_DIR/namespace.yaml"

  echo "[2/6] Adding Helm repositories..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
  helm repo update

  echo "[3/6] Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
  helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values "$MONITORING_DIR/prometheus/values.yaml" \
    --wait --timeout 10m

  echo "[4/6] Installing Loki..."
  helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --values "$MONITORING_DIR/loki/values.yaml" \
    --wait --timeout 10m

  echo "[5/6] Installing Promtail..."
  helm upgrade --install promtail grafana/promtail \
    --namespace monitoring \
    --values "$MONITORING_DIR/promtail/values.yaml" \
    --wait --timeout 5m

  echo "[6/6] Installing OpenTelemetry Collector..."
  helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    --namespace monitoring \
    --values "$MONITORING_DIR/otel-collector/values.yaml" \
    --wait --timeout 5m

  echo ""
  echo "============================================"
  echo "  Monitoring Stack Installed Successfully!"
  echo "============================================"
  echo ""

  echo "Applying Alertmanager custom configuration..."
  local ALERTING_DIR="$MONITORING_DIR/alerting"
  local AM_SECRET_FILE="$ALERTING_DIR/alertmanager-secret.yaml"
  if [ -f "$AM_SECRET_FILE" ]; then
    kubectl apply --server-side --force-conflicts -f "$AM_SECRET_FILE"
    echo "  [OK] Alertmanager config applied (PagerDuty + Discord + Self-Healing)"
  else
    echo "  [AVISO] $AM_SECRET_FILE not found — alerting not configured"
  fi

  echo "Applying ToggleMaster alert rules..."
  if [ -f "$ALERTING_DIR/prometheus-rules.yaml" ]; then
    kubectl apply -f "$ALERTING_DIR/prometheus-rules.yaml"
    echo "  [OK] PrometheusRules applied"
  fi

  echo "Loading ToggleMaster Grafana dashboard..."
  echo "  Waiting for Grafana to be ready (up to 5 min)..."
  kubectl rollout status deployment/prometheus-grafana -n monitoring --timeout=300s || true

  local GRAFANA_POD=""
  for i in $(seq 1 18); do
    GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana \
      --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [ -n "$GRAFANA_POD" ] && break
    echo "  Grafana pod not ready yet... (${i}/18)"
    sleep 10
  done

  if [ -z "$GRAFANA_POD" ]; then
    echo "  [AVISO] Grafana pod nao encontrado apos 3 min — dashboard nao carregado."
    echo "    Execute manualmente: kubectl apply -f gitops/monitoring/grafana/dashboard-configmap.yaml"
    return 0
  fi

  local LOKI_UID=""
  for i in $(seq 1 12); do
    LOKI_UID=$(kubectl exec -n monitoring "$GRAFANA_POD" -c grafana -- \
      curl -sf http://localhost:3000/api/datasources -u admin:tc4-tm 2>/dev/null | \
      python3 -c "import sys,json; ds=json.load(sys.stdin); print(next((d['uid'] for d in ds if d['type']=='loki'),''))" 2>/dev/null)
    [ -n "$LOKI_UID" ] && break
    echo "  Waiting for Loki datasource... (${i}/12)"
    sleep 5
  done

  if [ -z "$LOKI_UID" ]; then
    echo "  [AVISO] Loki datasource UID not found — log panels may not work."
    echo "    Fix manually: Grafana > Dashboard > Edit panel > change datasource to Loki"
    LOKI_UID="loki"
  fi
  echo "  Loki datasource UID: $LOKI_UID"

  local DASHBOARD_TMP
  DASHBOARD_TMP=$(mktemp)
  sed "s|<LOKI_DS_UID>|$LOKI_UID|g" "$MONITORING_DIR/grafana/dashboards/togglemaster-overview.json" > "$DASHBOARD_TMP"

  kubectl create configmap togglemaster-dashboard \
    --from-file=togglemaster-overview.json="$DASHBOARD_TMP" \
    --namespace monitoring \
    --dry-run=client -o yaml | \
    kubectl label --local -f - grafana_dashboard=1 -o yaml | \
    kubectl annotate --local -f - grafana_folder=ToggleMaster -o yaml | \
    kubectl apply -f -

  rm -f "$DASHBOARD_TMP"

  echo "Deploying self-healing bridge..."
  local BRIDGE_DIR="$MONITORING_DIR/self-healing-bridge"
  local BRIDGE_SECRET="$BRIDGE_DIR/secret.yaml"
  if [ -f "$BRIDGE_SECRET" ]; then
    kubectl apply -f "$BRIDGE_SECRET"
    echo "  [OK] self-healing-bridge-secret aplicado"
  else
    log_warn "  $BRIDGE_SECRET nao encontrado — bridge iniciara sem GITHUB_TOKEN (self-healing desativado)"
    echo "    Para ativar:"
    echo "    cp gitops/monitoring/self-healing-bridge/secret.yaml.example gitops/monitoring/self-healing-bridge/secret.yaml"
    echo "    # Edite com seu GitHub PAT (Actions: write em dsrdantas/TC4-TM)"
    echo "    kubectl apply -f gitops/monitoring/self-healing-bridge/secret.yaml"
    # Cria secret vazio para nao bloquear o deploy
    kubectl create secret generic self-healing-bridge-secret \
      --from-literal=GITHUB_TOKEN="" \
      --namespace monitoring \
      --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
  fi
  kubectl apply -f "$BRIDGE_DIR/deployment.yaml"
  echo "  [OK] self-healing-bridge deployado"
  echo ""

  echo "--- Access Information ---"
  echo ""
  echo "Grafana:"
  echo "  URL:      kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  echo "  User:     admin"
  echo "  Password: tc4-tm"
  echo ""
  echo "Prometheus:"
  echo "  Internal: http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
  echo ""
  echo "Loki:"
  echo "  Internal: http://loki.monitoring.svc.cluster.local:3100"
  echo ""
  echo "OTel Collector:"
  echo "  gRPC:     otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
  echo "  HTTP:     otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
  echo ""
  echo "--- IMPORTANT ---"
  echo "Don't forget to apply the New Relic secret:"
  echo "  cp gitops/monitoring/newrelic-secret.yaml.example gitops/monitoring/newrelic-secret.yaml"
  echo "  # Edit with your license key"
  echo "  kubectl apply -f gitops/monitoring/newrelic-secret.yaml"
  echo ""
}

###############################################################################
# --update-aws-credentials
###############################################################################
cmd_update_aws_credentials() {
  echo "============================================"
  echo "  ToggleMaster - Atualizar Credenciais AWS"
  echo "============================================"
  echo ""

  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SESSION_TOKEN" ]; then
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || echo "")
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERRO: Credenciais AWS nao encontradas (nem em env vars, nem em aws configure)."
    echo 'Execute: export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." AWS_SESSION_TOKEN="..."'
    echo "Ou configure via: aws configure"
    exit 1
  fi
  echo ">>> AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:12}..."
  echo ""

  echo ">>> Atualizando evaluation-service-secret..."
  local REDIS_URL SERVICE_API_KEY AWS_SQS_URL
  REDIS_URL=$(kubectl get secret evaluation-service-secret -n togglemaster -o jsonpath='{.data.REDIS_URL}' | base64 -d)
  SERVICE_API_KEY=$(kubectl get secret evaluation-service-secret -n togglemaster -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)
  AWS_SQS_URL=$(kubectl get secret evaluation-service-secret -n togglemaster -o jsonpath='{.data.AWS_SQS_URL}' | base64 -d)

  cat > /tmp/eval-secret-update.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  REDIS_URL: "$REDIS_URL"
  SERVICE_API_KEY: "$SERVICE_API_KEY"
  AWS_SQS_URL: "$AWS_SQS_URL"
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_SESSION_TOKEN: "$AWS_SESSION_TOKEN"
EOF
  kubectl apply -f /tmp/eval-secret-update.yaml
  rm -f /tmp/eval-secret-update.yaml
  echo "  [OK] evaluation-service-secret"

  echo ">>> Atualizando analytics-service-secret..."
  local AWS_SQS_URL_ANALYTICS
  AWS_SQS_URL_ANALYTICS=$(kubectl get secret analytics-service-secret -n togglemaster -o jsonpath='{.data.AWS_SQS_URL}' | base64 -d)

  cat > /tmp/analytics-secret-update.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: analytics-service-secret
  namespace: togglemaster
type: Opaque
stringData:
  AWS_SQS_URL: "$AWS_SQS_URL_ANALYTICS"
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_SESSION_TOKEN: "$AWS_SESSION_TOKEN"
EOF
  kubectl apply -f /tmp/analytics-secret-update.yaml
  rm -f /tmp/analytics-secret-update.yaml
  echo "  [OK] analytics-service-secret"

  echo ""
  echo ">>> Reiniciando pods para aplicar novas credenciais..."
  kubectl rollout restart deployment/evaluation-service -n togglemaster
  kubectl rollout restart deployment/analytics-service -n togglemaster

  echo ""
  echo "============================================"
  echo "  Credenciais AWS atualizadas!"
  echo "============================================"
  echo ""
  echo "Aguarde os pods reiniciarem:"
  echo "  kubectl get pods -n togglemaster -w"
  echo ""
}

###############################################################################
# --terraform-bootstrap  (uso interno + flag publica)
# Cria o S3 bucket e a tabela DynamoDB do backend antes do terraform init.
###############################################################################
cmd_terraform_bootstrap() {
  local REGION="us-east-1"
  local BUCKET="tc4-tm"
  local DYNAMO_TABLE="tc4-terraform-lock"

  echo "============================================"
  echo "  ToggleMaster - Terraform Backend Bootstrap"
  echo "============================================"
  echo ""
  echo "  S3 bucket:      $BUCKET"
  echo "  DynamoDB table: $DYNAMO_TABLE"
  echo "  Region:         $REGION"
  echo ""

  # S3 bucket
  if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    echo "  [OK] S3 bucket '$BUCKET' ja existe"
  else
    echo ">>> Criando S3 bucket '$BUCKET'..."
    # us-east-1 nao aceita LocationConstraint
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION"
    aws s3api put-bucket-versioning \
      --bucket "$BUCKET" \
      --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption \
      --bucket "$BUCKET" \
      --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    aws s3api put-public-access-block \
      --bucket "$BUCKET" \
      --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    echo "  [OK] S3 bucket criado e configurado"
  fi

  # DynamoDB table
  if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" &>/dev/null; then
    echo "  [OK] DynamoDB table '$DYNAMO_TABLE' ja existe"
  else
    echo ">>> Criando DynamoDB table '$DYNAMO_TABLE'..."
    aws dynamodb create-table \
      --table-name "$DYNAMO_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "$REGION"
    echo "  Aguardando tabela ficar ACTIVE..."
    aws dynamodb wait table-exists --table-name "$DYNAMO_TABLE" --region "$REGION"
    echo "  [OK] DynamoDB table criada"
  fi

  echo ""
  echo "  Backend pronto. Pode executar terraform init."
  echo ""
}

###############################################################################
# --terraform-apply
###############################################################################
cmd_terraform_apply() {
  local TERRAFORM_DIR="$PROJECT_DIR/terraform"

  echo "============================================"
  echo "  ToggleMaster - Terraform Apply"
  echo "============================================"
  echo ""

  if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    echo "ERRO: terraform/terraform.tfvars nao encontrado."
    echo "Crie a partir do exemplo:"
    echo "  cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
    echo "  # Edite com sua db_password e demais variaveis"
    exit 1
  fi

  # Garantir que o backend S3 + DynamoDB existem antes do init
  echo ">>> [1/4] Verificando/criando backend S3 + DynamoDB..."
  cmd_terraform_bootstrap
  echo ""

  echo ">>> [2/4] Inicializando Terraform..."
  (cd "$TERRAFORM_DIR" && terraform init -input=false)
  echo ""

  echo ">>> [3/4] Validando configuracao..."
  (cd "$TERRAFORM_DIR" && terraform validate)
  echo ""

  echo ">>> [4/4] Executando terraform apply (isso pode levar 15-20 minutos)..."
  echo "    Recursos criados: VPC, EKS, RDS (x3), Redis, SQS, ECR (x5)"
  echo ""
  (cd "$TERRAFORM_DIR" && terraform apply -auto-approve -input=false)

  echo ""
  echo "============================================"
  echo "  Terraform Apply concluido!"
  echo "============================================"
  echo ""
  echo "Outputs:"
  (cd "$TERRAFORM_DIR" && terraform output)
  echo ""
}

###############################################################################
# --setup-full
###############################################################################
cmd_setup_full() {
  # Se ainda nao estamos dentro de uma sessao com log, re-lanca com tee
  if [ -z "${TC4_LOGGING:-}" ]; then
    local LOG_FILE="$PROJECT_DIR/tc4-tm-setup-$(date +%Y%m%d-%H%M%S).log"
    echo "Logging to: $LOG_FILE"
    export TC4_LOGGING=1
    exec > >(tee -a "$LOG_FILE") 2>&1
  fi

  echo "============================================"
  echo "  ToggleMaster - Setup Completo"
  echo "============================================"
  echo ""

  # -------------------------------------------------------------------
  # [0/12] Verificacoes iniciais (apenas credenciais AWS, sem kubectl)
  # -------------------------------------------------------------------
  echo ">>> [0/12] Verificacoes iniciais..."

  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SESSION_TOKEN" ]; then
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || echo "")
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERRO: Credenciais AWS nao encontradas (nem em env vars, nem em aws configure)."
    echo 'Execute: export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." AWS_SESSION_TOKEN="..."'
    echo "Ou configure via: aws configure"
    exit 1
  fi
  echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:12}..."

  if ! command -v terraform &>/dev/null; then
    echo "ERRO: terraform nao encontrado no PATH."
    exit 1
  fi
  if ! command -v docker &>/dev/null; then
    echo "ERRO: docker nao encontrado no PATH."
    exit 1
  fi
  echo "  [OK] terraform, docker disponiveis"
  echo ""

  # -------------------------------------------------------------------
  # [1/12] Terraform — cria EKS, RDS, Redis, SQS, ECR
  # -------------------------------------------------------------------
  echo ">>> [1/12] Provisionando infraestrutura via Terraform..."
  cmd_terraform_apply
  echo ""

  # -------------------------------------------------------------------
  # [2/12] Configurar kubectl apos o EKS estar criado
  # -------------------------------------------------------------------
  echo ">>> [2/12] Configurando kubectl para o cluster EKS..."
  aws eks update-kubeconfig --name togglemaster-cluster --region us-east-1
  kubectl get nodes
  echo ""

  # -------------------------------------------------------------------
  # [3/12] Gerar secrets (le outputs do Terraform recem criado)
  # -------------------------------------------------------------------
  echo ">>> [3/12] Gerando secrets a partir dos outputs do Terraform..."
  cmd_generate_secrets
  echo ""

  # -------------------------------------------------------------------
  # [4/12] Instalar ArgoCD
  # -------------------------------------------------------------------
  echo ">>> [4/12] Instalando ArgoCD..."
  if kubectl get namespace argocd > /dev/null 2>&1; then
    echo "  ArgoCD namespace ja existe, pulando instalacao."
  else
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
  fi

  echo "  Aguardando ArgoCD ficar pronto..."
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
  kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true
  echo "  [OK] ArgoCD instalado"
  echo ""

  # -------------------------------------------------------------------
  # [5/12] Aplicar secrets no cluster e reiniciar auth-service
  # -------------------------------------------------------------------
  echo ">>> [5/12] Aplicando secrets no cluster..."
  cmd_apply_secrets

  echo "  Reiniciando auth-service para carregar o novo MASTER_KEY..."
  kubectl rollout restart deployment/auth-service -n togglemaster 2>/dev/null || true
  kubectl rollout status deployment/auth-service -n togglemaster --timeout=120s 2>/dev/null || true
  echo "  [OK] auth-service atualizado com o novo MASTER_KEY"
  echo ""

  # -------------------------------------------------------------------
  # [6/12] Build e push de imagens Docker para o ECR
  # -------------------------------------------------------------------
  echo ">>> [6/12] Build e push de imagens Docker..."

  local ACCOUNT_ID ECR_REGISTRY GITHUB_REPO_URL GITHUB_USER
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
  GITHUB_REPO_URL=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
  GITHUB_USER=$(echo "$GITHUB_REPO_URL" | sed 's|https://github.com/||' | cut -d/ -f1)

  echo "  ECR Registry: $ECR_REGISTRY"
  echo "  GitHub User:  $GITHUB_USER"

  echo "  Atualizando ECR nos manifestos..."
  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    local DEPLOY_FILE="$PROJECT_DIR/gitops/$svc/deployment.yaml"
    if [ ! -f "$DEPLOY_FILE" ]; then
      echo "    [SKIP] $DEPLOY_FILE nao encontrado"
      continue
    fi
    # Substitui placeholder (<AWS_ACCOUNT_ID>) OU qualquer account ID de 12 digitos
    # ja presente na URL do ECR — cobre re-execucoes sem precisar de destroy.
    sed -i.bak "s|<AWS_ACCOUNT_ID>\.dkr\.ecr|${ACCOUNT_ID}.dkr.ecr|g" "$DEPLOY_FILE"
    rm -f "$DEPLOY_FILE.bak"
    sed -i.bak -E "s|[0-9]{12}\.dkr\.ecr|${ACCOUNT_ID}.dkr.ecr|g" "$DEPLOY_FILE"
    rm -f "$DEPLOY_FILE.bak"
    echo "    [OK] $svc → $ECR_REGISTRY/$svc:latest"
  done

  local ARGOCD_FILE="$PROJECT_DIR/argocd/applications.yaml"
  if [ -f "$ARGOCD_FILE" ]; then
    # Substitui placeholder OU qualquer username GitHub ja presente
    sed -i.bak "s|<GITHUB_USER>|$GITHUB_USER|g" "$ARGOCD_FILE"
    rm -f "$ARGOCD_FILE.bak"
    echo "    [OK] argocd/applications.yaml atualizado (GitHub: $GITHUB_USER)"
  fi

  echo "  Commitando manifestos atualizados no git..."
  git -C "$PROJECT_DIR" add gitops/*/deployment.yaml argocd/applications.yaml 2>/dev/null
  if ! git -C "$PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    git -C "$PROJECT_DIR" commit -m "Update manifests with AWS account $ACCOUNT_ID and GitHub user $GITHUB_USER" --quiet
    git -C "$PROJECT_DIR" push --quiet || echo "    [AVISO] git push falhou — faca push manualmente antes do ArgoCD sync"
    echo "    [OK] Manifestos commitados e enviados"
  else
    echo "    Manifestos ja estavam atualizados"
  fi
  echo ""

  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"

  local SKIP_BUILD=true
  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    local IMAGE_COUNT
    IMAGE_COUNT=$(aws ecr list-images --repository-name "$svc" --region us-east-1 --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
    if [ "$IMAGE_COUNT" = "0" ] || [ "$IMAGE_COUNT" = "None" ]; then
      SKIP_BUILD=false
      break
    fi
  done

  if [ "$SKIP_BUILD" = "true" ]; then
    echo "  Imagens ja existem no ECR, pulando build."
  else
    echo "  Construindo e enviando imagens (isso pode levar 5-10 minutos)..."
    for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
      echo "  >>> Building $svc..."
      docker build --platform linux/amd64 -t "$ECR_REGISTRY/$svc:latest" "$PROJECT_DIR/microservices/$svc"
      docker push "$ECR_REGISTRY/$svc:latest"
      echo "  [OK] $svc"
    done
  fi
  echo ""

  # -------------------------------------------------------------------
  # [7/12] Aplicar ArgoCD Applications
  # -------------------------------------------------------------------
  echo ">>> [7/12] Aplicando ArgoCD Applications..."
  kubectl apply -f "$PROJECT_DIR/argocd/applications.yaml"
  echo "  [OK] Applications criadas"

  # Garantia: ArgoCD pode sincronizar do git remoto antes do push propagar.
  # Forcamos a imagem correta diretamente no cluster para eliminar a condicao de corrida.
  echo "  Forcando imagens corretas no cluster (safety net)..."
  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    kubectl set image deployment/$svc $svc=${ECR_REGISTRY}/${svc}:latest \
      -n togglemaster 2>/dev/null || true
  done
  echo "  [OK] Imagens atualizadas"
  echo ""

  # -------------------------------------------------------------------
  # [8/12] Instalar NGINX Ingress
  # -------------------------------------------------------------------
  echo ">>> [8/12] Instalando NGINX Ingress Controller..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml 2>/dev/null || true
  echo "  [OK] NGINX Ingress instalado"
  echo ""

  # -------------------------------------------------------------------
  # [9/12] Aguardar pods
  # -------------------------------------------------------------------
  echo ">>> [9/12] Aguardando pods do ToggleMaster ficarem prontos..."
  echo "  (isso pode levar 2-5 minutos)"
  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    echo -n "  Aguardando $svc... "
    kubectl rollout status deployment/$svc -n togglemaster --timeout=180s 2>/dev/null || echo "(pode demorar mais)"
  done
  echo ""
  kubectl get pods -n togglemaster
  echo ""

  # -------------------------------------------------------------------
  # [10/12] Gerar SERVICE_API_KEY
  # -------------------------------------------------------------------
  echo ">>> [10/12] Gerando SERVICE_API_KEY..."
  cmd_generate_api_key
  echo ""

  # -------------------------------------------------------------------
  # [11/12] Namespace monitoring + New Relic secret
  # -------------------------------------------------------------------
  echo ">>> [11/12] Garantindo namespace monitoring e secrets..."
  kubectl get namespace monitoring > /dev/null 2>&1 || kubectl create namespace monitoring
  echo "  [OK] namespace monitoring"

  local NR_SECRET_FILE="$PROJECT_DIR/gitops/monitoring/newrelic-secret.yaml"
  if [ -f "$NR_SECRET_FILE" ]; then
    kubectl apply -f "$NR_SECRET_FILE"
    echo "  [OK] New Relic secret aplicado"
  else
    echo "  [AVISO] $NR_SECRET_FILE nao encontrado — APM New Relic nao configurado."
    echo "    cp gitops/monitoring/newrelic-secret.yaml.example gitops/monitoring/newrelic-secret.yaml"
  fi
  echo ""

  # -------------------------------------------------------------------
  # [12/12] Instalar Monitoring Stack
  # -------------------------------------------------------------------
  echo ">>> [12/12] Instalando Monitoring Stack (Prometheus + Loki + Grafana + OTel)..."
  cmd_install_monitoring
  echo ""

  echo ""
  echo "============================================"
  echo "  SETUP COMPLETO!"
  echo "============================================"
  echo ""

  local ARGOCD_URL ARGOCD_PASS GRAFANA_URL
  ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")
  ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")
  GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")

  echo "ArgoCD:"
  echo "  URL:   https://$ARGOCD_URL"
  echo "  User:  admin"
  echo "  Pass:  $ARGOCD_PASS"
  echo ""
  echo "Grafana (Monitoring):"
  echo "  URL:   http://$GRAFANA_URL"
  echo "  User:  admin"
  echo "  Pass:  tc4-tm"
  echo ""
  echo "OTel Collector:"
  echo "  gRPC: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
  echo "  HTTP: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
  echo ""
  echo "Verificar pods:"
  echo "  kubectl get pods -n togglemaster"
  echo "  kubectl get pods -n monitoring"
  echo ""
  echo "Testar health:"
  echo "  kubectl port-forward svc/auth-service 8001:8001 -n togglemaster &"
  echo "  curl http://localhost:8001/health"
  echo ""
  echo "Atualizar credenciais AWS (a cada 4h):"
  echo "  ./scripts/tc4-tm.sh --update-aws-credentials"
  echo ""
}

###############################################################################
# --destroy-all
###############################################################################
cmd_destroy_all() {
  local TERRAFORM_DIR="$PROJECT_DIR/terraform"
  local CLUSTER_NAME="togglemaster-cluster"
  local REGION="${AWS_DEFAULT_REGION:-us-east-1}"

  log_info "Verificando credenciais AWS..."
  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "Credenciais AWS inválidas. Configure as variáveis de ambiente:"
    echo "  export AWS_ACCESS_KEY_ID=..."
    echo "  export AWS_SECRET_ACCESS_KEY=..."
    echo "  export AWS_SESSION_TOKEN=..."
    exit 1
  fi
  log_ok "Credenciais AWS válidas"

  log_info "Verificando se cluster EKS '$CLUSTER_NAME' existe..."
  if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
    log_info "Cluster EKS encontrado. Atualizando kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null

    log_info "Buscando Services do tipo LoadBalancer..."
    local LB_SERVICES
    LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | \
      python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('spec', {}).get('type') == 'LoadBalancer':
        ns = item['metadata']['namespace']
        name = item['metadata']['name']
        print(f'{ns}/{name}')
" 2>/dev/null || true)

    if [ -n "$LB_SERVICES" ]; then
      log_warn "Encontrados Services LoadBalancer que bloqueiam o destroy:"
      echo "$LB_SERVICES"
      echo ""
      for svc in $LB_SERVICES; do
        local NS NAME
        NS=$(echo "$svc" | cut -d/ -f1)
        NAME=$(echo "$svc" | cut -d/ -f2)
        log_info "Deletando Service $NS/$NAME..."
        kubectl delete svc "$NAME" -n "$NS" --timeout=60s 2>/dev/null || true
      done

      log_info "Aguardando LoadBalancers serem removidos da AWS (até 120s)..."
      for i in $(seq 1 24); do
        local ELB_COUNT NLB_COUNT TOTAL
        ELB_COUNT=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions | length(@)' --output text 2>/dev/null || echo "0")
        NLB_COUNT=$(aws elbv2 describe-load-balancers --query 'LoadBalancers | length(@)' --output text 2>/dev/null || echo "0")
        TOTAL=$((ELB_COUNT + NLB_COUNT))
        if [ "$TOTAL" -eq 0 ]; then
          log_ok "Todos os LoadBalancers removidos"
          break
        fi
        echo "  Aguardando... ($TOTAL LBs restantes, tentativa $i/24)"
        sleep 5
      done
    else
      log_ok "Nenhum Service LoadBalancer encontrado"
    fi

    log_info "Deletando Ingress resources..."
    kubectl delete ingress --all --all-namespaces --timeout=60s 2>/dev/null || true

    log_info "Deletando namespaces customizados..."
    local CUSTOM_NS
    CUSTOM_NS=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | \
      grep -v -E '^(default|kube-system|kube-public|kube-node-lease|argocd)$' || true)
    for ns in $CUSTOM_NS; do
      log_info "Deletando namespace $ns..."
      kubectl delete ns "$ns" --timeout=120s 2>/dev/null || true
    done

    log_info "Deletando namespace argocd..."
    kubectl delete ns argocd --timeout=120s 2>/dev/null || true

    log_info "Aguardando 30s para ENIs serem liberadas..."
    sleep 30
  else
    log_warn "Cluster EKS '$CLUSTER_NAME' não encontrado. Pulando limpeza K8s."
  fi

  log_info "Verificando LoadBalancers órfãos..."
  local ELBS
  ELBS=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text 2>/dev/null || true)
  if [ -n "$ELBS" ]; then
    for elb in $ELBS; do
      log_warn "Deletando Classic ELB órfão: $elb"
      aws elb delete-load-balancer --load-balancer-name "$elb" 2>/dev/null || true
    done
  fi

  local ELBV2_ARNS
  ELBV2_ARNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || true)
  if [ -n "$ELBV2_ARNS" ]; then
    for arn in $ELBV2_ARNS; do
      local NAME
      NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null)
      log_warn "Deletando ALB/NLB órfão: $NAME"
      local LISTENERS
      LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$arn" --query 'Listeners[*].ListenerArn' --output text 2>/dev/null || true)
      for listener in $LISTENERS; do
        aws elbv2 delete-listener --listener-arn "$listener" 2>/dev/null || true
      done
      aws elbv2 delete-load-balancer --load-balancer-arn "$arn" 2>/dev/null || true
    done
    log_info "Aguardando 30s para LBs serem removidos..."
    sleep 30
  fi

  local TG_ARNS
  TG_ARNS=$(aws elbv2 describe-target-groups --query 'TargetGroups[*].TargetGroupArn' --output text 2>/dev/null || true)
  if [ -n "$TG_ARNS" ]; then
    for tg_arn in $TG_ARNS; do
      local TG_NAME
      TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null)
      log_warn "Deletando Target Group órfão: $TG_NAME"
      aws elbv2 delete-target-group --target-group-arn "$tg_arn" 2>/dev/null || true
    done
  fi
  log_ok "Limpeza de LoadBalancers concluída"

  log_info "Verificando VPC do ToggleMaster..."
  local VPC_ID
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=togglemaster-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

  if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    log_info "VPC encontrada: $VPC_ID. Limpando ENIs órfãs..."

    local ENIS
    ENIS=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
      --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null || true)
    if [ -n "$ENIS" ]; then
      for eni in $ENIS; do
        log_warn "Deletando ENI órfã: $eni"
        aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
      done
    fi

    local ENIS_INUSE
    ENIS_INUSE=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=in-use" \
      --query 'NetworkInterfaces[*].{Id:NetworkInterfaceId,Desc:Description,AttachId:Attachment.AttachmentId}' \
      --output json 2>/dev/null || echo "[]")

    local ENI_COUNT
    ENI_COUNT=$(echo "$ENIS_INUSE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$ENI_COUNT" -gt 0 ]; then
      log_warn "Encontradas $ENI_COUNT ENIs in-use. Tentando desanexar e deletar..."
      echo "$ENIS_INUSE" | python3 -c "
import json, sys
enis = json.load(sys.stdin)
for eni in enis:
    eni_id = eni['Id']
    attach_id = eni.get('AttachId', '')
    desc = eni.get('Desc', '')
    print(f'{eni_id}|{attach_id}|{desc}')
" | while IFS='|' read -r eni_id attach_id desc; do
        if [ -n "$attach_id" ]; then
          log_info "  Desanexando ENI $eni_id ($desc)..."
          aws ec2 detach-network-interface --attachment-id "$attach_id" --force 2>/dev/null || true
          sleep 5
        fi
        log_info "  Deletando ENI $eni_id..."
        aws ec2 delete-network-interface --network-interface-id "$eni_id" 2>/dev/null || true
      done
    fi

    log_info "Limpando Security Groups customizados na VPC..."
    local SG_IDS
    SG_IDS=$(aws ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)

    if [ -n "$SG_IDS" ]; then
      for sg in $SG_IDS; do
        log_info "  Limpando regras do SG $sg..."
        aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" \
          --query 'SecurityGroupRules[*].SecurityGroupRuleId' --output text 2>/dev/null | \
          tr '\t' '\n' | while read -r rule_id; do
            [ -n "$rule_id" ] && aws ec2 revoke-security-group-ingress --group-id "$sg" --security-group-rule-ids "$rule_id" 2>/dev/null || true
            [ -n "$rule_id" ] && aws ec2 revoke-security-group-egress --group-id "$sg" --security-group-rule-ids "$rule_id" 2>/dev/null || true
          done
        log_warn "  Deletando SG $sg..."
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
      done
    fi

    log_ok "Limpeza de VPC concluída"
  else
    log_ok "VPC togglemaster-vpc não encontrada (já deletada)"
  fi

  log_info "Verificando terraform state..."
  (
    cd "$TERRAFORM_DIR"
    terraform init -input=false 2>/dev/null

    local STATE_COUNT
    STATE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')

    if [ "$STATE_COUNT" -gt 0 ]; then
      log_info "Encontrados $STATE_COUNT recursos no terraform state. Executando destroy..."
      terraform state list 2>/dev/null
      echo ""

      local PLAN_OUTPUT LOCK_ID
      PLAN_OUTPUT=$(terraform plan -no-color -lock=false 2>&1 || true)
      LOCK_ID=$(echo "$PLAN_OUTPUT" | grep 'ID:' | head -1 | sed 's/.*ID:[[:space:]]*//' | tr -d '[:space:]' || true)
      if [ -n "$LOCK_ID" ]; then
        log_warn "State locked. Forçando unlock (ID: $LOCK_ID)..."
        terraform force-unlock -force "$LOCK_ID" 2>/dev/null || true
      fi

      terraform destroy -auto-approve -lock-timeout=60s 2>&1
      local DESTROY_EXIT=$?

      if [ $DESTROY_EXIT -eq 0 ]; then
        log_ok "Terraform destroy concluído com sucesso!"
      else
        log_error "Terraform destroy falhou (exit code: $DESTROY_EXIT)"
        log_info "Tentando remover recursos restantes do state..."
        for resource in $(terraform state list 2>/dev/null); do
          log_warn "  Removendo $resource do state..."
          terraform state rm "$resource" 2>/dev/null || true
        done
      fi
    else
      log_ok "Terraform state vazio - nada para destruir"
    fi
  )

  log_info "Restaurando placeholders nos manifestos (para manter repo limpo)..."
  local ACCOUNT_ID GITHUB_USER
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  GITHUB_USER=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||' | sed 's|https://github.com/||' | cut -d/ -f1)

  if [ -n "$ACCOUNT_ID" ]; then
    for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
      local DEPLOY_FILE="$PROJECT_DIR/gitops/$svc/deployment.yaml"
      if grep -q "$ACCOUNT_ID" "$DEPLOY_FILE" 2>/dev/null; then
        sed -i.bak "s|$ACCOUNT_ID|<AWS_ACCOUNT_ID>|g" "$DEPLOY_FILE" && rm -f "$DEPLOY_FILE.bak"
      fi
    done
    log_ok "Placeholders ECR restaurados"
  fi

  log_info "Restaurando tags de imagem para :latest..."
  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    local DEPLOY_FILE_TAG="$PROJECT_DIR/gitops/$svc/deployment.yaml"
    sed -i.bak -E "s|(\.dkr\.ecr\.[^/]+/[^:]+):[a-f0-9]{7,}|\1:latest|g" "$DEPLOY_FILE_TAG" 2>/dev/null
    rm -f "$DEPLOY_FILE_TAG.bak" 2>/dev/null || true
  done
  log_ok "Tags de imagem restauradas para :latest"

  if [ -n "$GITHUB_USER" ]; then
    local ARGOCD_FILE="$PROJECT_DIR/argocd/applications.yaml"
    if grep -q "github.com/$GITHUB_USER" "$ARGOCD_FILE" 2>/dev/null; then
      sed -i.bak "s|$GITHUB_USER|<GITHUB_USER>|g" "$ARGOCD_FILE" && rm -f "$ARGOCD_FILE.bak"
    fi
    log_ok "Placeholders GitHub restaurados"
  fi

  git -C "$PROJECT_DIR" add gitops/*/deployment.yaml argocd/applications.yaml 2>/dev/null
  if ! git -C "$PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    git -C "$PROJECT_DIR" commit -m "Restore manifests placeholders after destroy" --quiet
    git -C "$PROJECT_DIR" push --quiet 2>/dev/null || log_warn "git push falhou — faca push manualmente"
    log_ok "Placeholders commitados e enviados ao repositorio"
  fi

  echo ""
  echo "========================================="
  log_info "VERIFICAÇÃO FINAL"
  echo "========================================="
  echo -n "VPCs não-default: "
  aws ec2 describe-vpcs --filters "Name=is-default,Values=false" --query 'Vpcs | length(@)' --output text 2>/dev/null
  echo -n "EKS clusters: "
  aws eks list-clusters --query 'clusters | length(@)' --output text 2>/dev/null
  echo -n "RDS instances: "
  aws rds describe-db-instances --query 'DBInstances | length(@)' --output text 2>/dev/null
  echo -n "ElastiCache clusters: "
  aws elasticache describe-cache-clusters --query 'CacheClusters | length(@)' --output text 2>/dev/null
  echo -n "ECR repositories: "
  aws ecr describe-repositories --query 'repositories | length(@)' --output text 2>/dev/null
  echo -n "Load Balancers (classic): "
  aws elb describe-load-balancers --query 'LoadBalancerDescriptions | length(@)' --output text 2>/dev/null
  echo -n "Load Balancers (v2): "
  aws elbv2 describe-load-balancers --query 'LoadBalancers | length(@)' --output text 2>/dev/null
  echo -n "NAT Gateways: "
  aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" --query 'NatGateways | length(@)' --output text 2>/dev/null
  echo -n "Elastic IPs: "
  aws ec2 describe-addresses --query 'Addresses | length(@)' --output text 2>/dev/null
  echo ""
  echo "========================================="
  log_ok "Destruição completa finalizada!"
  echo "========================================="
}

###############################################################################
# --inject-fault
###############################################################################
cmd_inject_fault() {
  local SERVICE="${1:-auth-service}"
  local NAMESPACE="togglemaster"

  echo "============================================"
  echo "  FAULT INJECTION - ToggleMaster"
  echo "============================================"
  echo "  Target:    $SERVICE"
  echo "  Namespace: $NAMESPACE"
  echo "  Action:    Scale down to 0 replicas"
  echo "============================================"
  echo ""
  echo "This will cause:"
  echo "  1. Service health checks to fail"
  echo "  2. Prometheus alert to fire (HighErrorRate5xx / PodNotReady)"
  echo "  3. OpsGenie incident to be created"
  echo "  4. Discord notification to be sent"
  echo "  5. Self-Healing to trigger (rollout restart)"
  echo ""

  read -p "Continue? (y/N) " -n 1 -r
  echo ""

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    return 0
  fi

  echo ""
  echo ">>> Current state:"
  kubectl get pods -n "$NAMESPACE" -l app="$SERVICE"
  echo ""

  echo ">>> Injecting fault: scaling $SERVICE to 0 replicas..."
  kubectl scale deployment/"$SERVICE" -n "$NAMESPACE" --replicas=0

  echo ""
  echo ">>> Fault injected! The service is now down."
  echo ""
  echo ">>> Monitoring:"
  echo "  - Watch pods:   kubectl get pods -n $NAMESPACE -w"
  echo "  - Watch alerts: Open Grafana -> Alerting -> Alert Rules"
  echo "  - OpsGenie:     https://app.opsgenie.com/alert"
  echo ""
  echo ">>> To manually restore (if self-healing doesn't trigger):"
  echo "  kubectl scale deployment/$SERVICE -n $NAMESPACE --replicas=2"
  echo ""
  echo ">>> The alert should fire within ~2-5 minutes."
  echo ">>> Self-healing will then restore the service automatically."
}

###############################################################################
# --test-self-healing
###############################################################################
cmd_test_self_healing() {
  local SERVICE="${1:-auth-service}"
  local REPO="dsrdantas/TC4-TM"

  echo "============================================"
  echo "  Self-Healing Test Trigger"
  echo "============================================"
  echo "  Repository: $REPO"
  echo "  Service:    $SERVICE"
  echo "  Alert:      TestAlert (manual)"
  echo "============================================"
  echo ""

  echo "Triggering repository_dispatch event..."

  if command -v gh &>/dev/null; then
    gh api "repos/$REPO/dispatches" \
      -f event_type=self-healing \
      -f "client_payload[service]=$SERVICE" \
      -f "client_payload[alert]=TestAlert-ManualTrigger"
  else
    echo "  [INFO] gh CLI nao encontrado — usando curl direto."
    echo ""

    local GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -z "$GITHUB_TOKEN" ]; then
      echo "ERRO: gh CLI nao instalado e GITHUB_TOKEN nao definido."
      echo ""
      echo "Opcoes:"
      echo "  1) Instalar gh CLI:  brew install gh && gh auth login"
      echo "  2) Exportar token:   export GITHUB_TOKEN=ghp_..."
      echo "     Depois re-executar: ./scripts/tc4-tm.sh --test-self-healing $SERVICE"
      echo ""
      echo "Ou disparar manualmente via GitHub:"
      echo "  https://github.com/$REPO/actions/workflows/self-healing.yaml"
      echo "  (Actions > Self-Healing > Run workflow)"
      exit 1
    fi

    local HTTP_STATUS
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$REPO/dispatches" \
      -d "{\"event_type\":\"self-healing\",\"client_payload\":{\"service\":\"$SERVICE\",\"alert\":\"TestAlert-ManualTrigger\"}}")

    if [ "$HTTP_STATUS" = "204" ]; then
      echo "  [OK] Dispatch enviado (HTTP 204)"
    else
      echo "ERRO: GitHub API retornou HTTP $HTTP_STATUS"
      echo "Verifique se o GITHUB_TOKEN tem permissao 'repo' ou 'workflow'."
      exit 1
    fi
  fi

  echo ""
  echo "Dispatch event sent successfully!"
  echo ""
  echo "Monitor the workflow at:"
  echo "  https://github.com/$REPO/actions/workflows/self-healing.yaml"
  echo ""
  echo "Or via CLI (se gh instalado):"
  echo "  gh run list --workflow=self-healing.yaml --repo=$REPO"
}

###############################################################################
# Roteamento de flags
###############################################################################
FLAG="${1:-}"

case "$FLAG" in
  --setup-full)             shift; cmd_setup_full "$@" ;;
  --terraform-bootstrap)    shift; cmd_terraform_bootstrap "$@" ;;
  --terraform-apply)        shift; cmd_terraform_apply "$@" ;;
  --install-monitoring)     shift; cmd_install_monitoring "$@" ;;
  --generate-secrets)       shift; cmd_generate_secrets "$@" ;;
  --apply-secrets)          shift; cmd_apply_secrets "$@" ;;
  --generate-api-key)       shift; cmd_generate_api_key "$@" ;;
  --update-aws-credentials) shift; cmd_update_aws_credentials "$@" ;;
  --destroy-all)            shift; cmd_destroy_all "$@" ;;
  --inject-fault)           shift; cmd_inject_fault "$@" ;;
  --test-self-healing)      shift; cmd_test_self_healing "$@" ;;
  --help|-h|help)           usage; exit 0 ;;
  "")   echo "ERRO: Nenhuma flag fornecida."; usage; exit 1 ;;
  *)    echo "ERRO: Flag desconhecida: '$FLAG'"; usage; exit 1 ;;
esac
