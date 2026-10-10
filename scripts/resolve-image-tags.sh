#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Resolve a tag mais recente de cada imagem no ECR e grava no .env, junto com o
# registry. Também faz o docker login.
#
# As tags do ECR são o SHA completo do commit e os repositórios são IMMUTABLE,
# então não existe "latest": a tag precisa ser descoberta.
#
# Uso:   bash scripts/resolve-image-tags.sh [profile] [região]
# Ex.:   bash scripts/resolve-image-tags.sh VitaoAWS us-east-1
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")/.." || exit 1

PROFILE="${1:-}"
REGION="${2:-us-east-1}"
PROFILE_ARG=""
[ -n "$PROFILE" ] && PROFILE_ARG="--profile $PROFILE"

SERVICES="auth-service flag-service targeting-service evaluation-service analytics-service"

ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_ARG --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo ">> Conta ${ACCOUNT_ID} / região ${REGION}"

[ -f .env ] || { cp .env.example .env; echo ">> .env criado a partir do .env.example"; }

# Reescreve uma chave no .env sem duplicar
set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

set_env "ECR_REGISTRY" "$REGISTRY"

for svc in $SERVICES; do
  tag=$(aws ecr describe-images $PROFILE_ARG \
    --region "$REGION" \
    --repository-name "togglemaster/${svc}" \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' \
    --output text 2>/dev/null || echo "None")

  if [ "$tag" = "None" ] || [ -z "$tag" ]; then
    echo "!! ${svc}: nenhuma imagem encontrada no ECR" >&2
    continue
  fi

  key="$(echo "$svc" | tr 'a-z-' 'A-Z_')_TAG"
  set_env "$key" "$tag"
  echo "   ${svc} -> ${tag}"
done

echo ">> docker login no ECR"
aws ecr get-login-password $PROFILE_ARG --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo ">> pronto. Suba com: docker compose up -d"
