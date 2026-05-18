#!/bin/bash
# Script para instalar ArgoCD no cluster EKS
# Executar apos o cluster estar ativo

set -e

echo "=== Instalando ArgoCD ==="

# Criar namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Instalar ArgoCD via manifests oficiais
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Aguardando pods do ArgoCD ficarem prontos..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Expor ArgoCD via LoadBalancer (para demonstracao)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

echo ""
echo "=== ArgoCD Instalado ==="
echo ""
echo "Para obter a senha inicial do admin:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Para obter o endereco do ArgoCD:"
echo "  kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
