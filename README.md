# togglemaster-platform-legacy

Ambiente **local de testes** do ToggleMaster. Sobe os cinco microsserviços, três PostgreSQL e um Redis com Docker Compose.

Serve para validar comportamento antes de levar qualquer coisa ao cluster. Não provisiona infraestrutura e não faz deploy: isso vive em [`togglemaster-iac`](https://github.com/fiap-tech-challenge-devops/togglemaster-iac) e [`togglemaster-gitops`](https://github.com/fiap-tech-challenge-devops/togglemaster-gitops).

## Dois modos

| Modo | Imagem | Quando usar |
|---|---|---|
| **Desenvolvimento** (padrão) | Build do `Dockerfile` de cada serviço irmão | Enquanto você altera código. Ciclo de segundos, sem depender da esteira |
| **ECR** (override) | Imagem publicada pela esteira de CI | Antes de ir ao cluster, para validar o artefato real — o mesmo que o Argo CD leva |

O segundo modo existe porque o que roda nele é exatamente o que a esteira construiu, escaneou e publicou. Um bug que aparece ali é da imagem real, não do seu Docker.

---

## Pré-requisitos

- Docker Desktop (ou Docker Engine + Compose v2)
- AWS CLI autenticada, com permissão de leitura no ECR
- Os repositórios dos microsserviços clonados **lado a lado** com este — os bancos montam o `db/init.sql` de cada serviço:

  ```
  <workspace>/
  ├── togglemaster-platform-legacy/   ← você está aqui
  ├── auth-service/
  ├── flag-service/
  ├── targeting-service/
  ├── evaluation-service/
  └── analytics-service/
  ```

## Subindo — modo desenvolvimento

```bash
cp .env.example .env        # só na primeira vez

docker compose up -d --build
docker compose logs -f
```

Depois de alterar o código de um serviço, reconstrua só ele:

```bash
docker compose up -d --build flag-service
```

## Subindo — modo ECR

```bash
# 1. Resolve a tag mais recente de cada imagem, grava no .env e faz login no ECR
bash scripts/resolve-image-tags.sh [profile] [região]

# 2. Baixa e sobe sem construir nada
docker compose -f docker-compose.yml -f docker-compose.ecr.yml pull
docker compose -f docker-compose.yml -f docker-compose.ecr.yml up -d --no-build
```

O script existe porque os repositórios ECR são **IMMUTABLE** e as tags são o SHA completo do commit: não há `latest` para apontar. Ele consulta a imagem mais recente de cada repositório e escreve as tags no `.env`.

Para fixar uma versão específica — comparar duas builds, por exemplo — edite as tags no `.env` à mão.

## Testando

```bash
# Health de todos
for p in 8001 8002 8003 8004 8005; do curl -s localhost:$p/health; echo; done

# 1. Cria uma chave de API
curl -X POST http://localhost:8001/admin/keys \
  -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" \
  -d '{"name":"evaluation-service-key"}'

# 2. Põe a chave em EVALUATION_SERVICE_API_KEY no .env e recria o serviço
docker compose up -d evaluation-service

# 3. Cria uma flag, uma regra e avalia
curl -X POST http://localhost:8002/flags \
  -H "Authorization: Bearer tm_key_..." \
  -H "Content-Type: application/json" \
  -d '{"name":"enable-new-dashboard","enabled":true}'

curl "http://localhost:8004/evaluate?user_id=demo&flag_name=enable-new-dashboard" \
  -H "Authorization: Bearer tm_key_..."
```

O `/evaluate` é o caminho mais completo: passa por Redis, chama `flag-service` e `targeting-service` e publica um evento na fila.

## AWS opcional

Com `AWS_SQS_URL` vazio, o `evaluation-service` loga `[SQS_DISABLED]` e o `analytics-service` fica sem fila. Para exercitar a cadeia assíncrona inteira, preencha as variáveis de AWS no `.env`.

## Encerrando

```bash
docker compose down        # para e remove os contêineres
docker compose down -v     # idem, apagando os dados dos bancos
```

---

## Sobre o nome

Este repositório foi o ponto de entrada do projeto nas Fases 1 e 2, quando também guardava manifests Kubernetes e Terraform. Esse conteúdo migrou para os repositórios dedicados, e o que sobrou — o ambiente local — é o que ele é hoje.

A pasta `docs/` mantém o registro histórico daquela etapa.
