# New App Onboarding Guide

## Quick Start

### 1. 앱 스캐폴딩

```bash
./scripts/onboard-app.sh my-app my-app.example.com
```

### 2. values.yaml 수정

`apps/my-app/values.yaml`을 열어 프로젝트에 맞게 설정:

```yaml
namespace: my-app

server:
  image:
    repository: docker.io/library/my-app-server
  port: 3001
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: my-app-secret
          key: DATABASE_URL

databases:
  postgresql:
    enabled: true
    secretName: my-app-db-secret
```

### 3. 시크릿 생성

```bash
./scripts/seal-secret.sh my-app my-app-db-secret \
  --from-literal DB_USER=myuser \
  --from-literal DB_PASSWORD=mypass \
  --from-literal DB_NAME=mydb

./scripts/seal-secret.sh my-app my-app-secret \
  --from-literal DATABASE_URL=postgresql://myuser:mypass@postgres:5432/mydb
```

### 4. 검증

```bash
# Lint
helm lint charts/web-app -f apps/my-app/values.yaml

# 렌더링 확인
helm template my-app charts/web-app -f apps/my-app/values.yaml
```

### 5. 배포

```bash
git add apps/my-app/
git commit -m "feat: onboard my-app"
git push
```

ArgoCD가 자동으로 감지하여 배포한다.

## App Repo Setup

앱 repo의 `.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  push:
    branches: [main]
    paths-ignore: ["*.md", "docs/**"]

jobs:
  deploy:
    uses: SonAIengine/runway/.github/workflows/build-and-push.yml@main
    with:
      app-name: my-app
      namespace: my-app
      components: '[{"name":"server","dockerfile":"./Dockerfile","context":"."},{"name":"client","dockerfile":"./client/Dockerfile","context":"./client"}]'
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

## Checklist

- [ ] `apps/<name>/values.yaml` 작성
- [ ] Kubernetes secrets 생성
- [ ] `helm template` 렌더링 검증
- [ ] DNS A 레코드 설정 (도메인 → 서버 IP)
- [ ] 앱 repo에 reusable workflow 연결
- [ ] Dockerfile 준비 (server, client)
