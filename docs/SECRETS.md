# Secrets Management

## Overview

모든 시크릿은 Kubernetes Secret으로 관리된다. Git에 시크릿을 커밋하지 않는다.

## Secret 생성

### seal-secret.sh 사용

```bash
# .env 파일에서 생성
./scripts/seal-secret.sh <namespace> <secret-name> --from-env-file ./secrets/my.env

# 개별 key-value로 생성
./scripts/seal-secret.sh <namespace> <secret-name> \
  --from-literal KEY1=value1 \
  --from-literal KEY2=value2
```

### kubectl 직접 사용

```bash
kubectl create secret generic <secret-name> \
  -n <namespace> \
  --from-literal=KEY=VALUE
```

## Project Secrets

### dongtan

| Secret Name | Keys | Description |
|------------|------|-------------|
| `dongtan-db-secret` | DB_USER, DB_PASSWORD, DB_NAME, REDIS_PASSWORD | DB 접속 정보 |
| `dongtan-app-secret` | DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_REFRESH_SECRET | 앱 설정 |
| `dongtan-api-keys` | PUBLIC_DATA_API_KEY, KAKAO_*, NAVER_*, GOOGLE_*, ANTHROPIC_API_KEY, ... | 외부 API 키 |
| `dongtan-tls` | tls.crt, tls.key | TLS 인증서 (cert-manager 자동 관리) |

### alls

| Secret Name | Keys | Description |
|------------|------|-------------|
| `alls-db-secret` | MONGO_ROOT_USER, MONGO_ROOT_PASSWORD | MongoDB 접속 정보 |
| `alls-app-secret` | MONGODB_URI, JWT_SECRET | 앱 설정 |
| `alls-tls` | tls.crt, tls.key | TLS 인증서 (cert-manager 자동 관리) |

## GitHub Actions Secrets

앱 repo에 설정 필요:

| Secret | Description |
|--------|-------------|
| `GH_PAT` | infra repo에 push할 수 있는 GitHub Personal Access Token |

## Security Notes

- `.env` 파일은 `.gitignore`에 반드시 추가
- TLS 인증서는 cert-manager가 자동으로 갱신
- GitHub PAT는 최소 권한 (repo scope)으로 생성
- 시크릿 변경 시 pod 재시작 필요 (`kubectl rollout restart deployment/<name> -n <namespace>`)
