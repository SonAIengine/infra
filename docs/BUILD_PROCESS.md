# Infra 프로젝트 구축 과정

> 범용 배포 플랫폼을 처음부터 구축한 전체 과정을 기록한 문서

## 1. 배경 및 문제 인식

### 기존 상태

두 개의 프로젝트가 **거의 동일한 배포 파이프라인**을 각자 repo에 복붙해서 사용하고 있었다.

| 프로젝트 | 스택 | DB | 도메인 |
|----------|------|-----|--------|
| dongtan-master-guide | Node.js + React(Nginx) | PostgreSQL + Redis | dongtan.infoedu.co.kr |
| alls-stiker-mall | Node.js + Next.js | MongoDB | alls-kr.shop |

**공통 인프라**: K3s (단일 노드) + Traefik + cert-manager + GitHub Actions (self-hosted runner)

### 기존 배포 방식의 문제점

```
각 앱 repo/.github/workflows/deploy.yml (50줄 복붙)
├── Docker build (server + client)
├── docker save | k3s ctr images import
├── kubectl set image ...
└── kubectl rollout status ...
```

- deploy.yml이 각 repo에 복붙됨 → 변경 시 모든 repo 수정 필요
- K8s 매니페스트도 각 repo의 `k8s/` 디렉토리에 산재
- 새 프로젝트 추가 시 매번 동일한 작업 반복
- 인프라 설정의 단일 진실 공급원(single source of truth) 부재

## 2. 목표 아키텍처 설계

### 핵심 컴포넌트 3가지

1. **Helm Chart** — K8s 매니페스트를 하나의 파라미터화된 차트로 통합
2. **ArgoCD (GitOps)** — Git을 단일 진실 공급원으로, pull 기반 배포
3. **Reusable GitHub Actions** — 빌드/배포 로직을 한 곳에 집중

### 설계한 배포 흐름 (Hybrid GitOps)

```
App Push → GHA(self-hosted) → Docker Build → K3s Import (레지스트리 없는 환경)
                             → Infra Repo values.yaml 태그 업데이트
                             → ArgoCD 감지 → Helm 렌더링 → K8s 적용
```

레지스트리 없는 단일 노드 K3s 환경에 맞춘 현실적 접근.
`docker save | k3s ctr images import`로 직접 로드 + ArgoCD GitOps를 병행한다.

## 3. 기존 매니페스트 분석

### dongtan-master-guide K8s 매니페스트 (k8s/)

| 파일 | 리소스 | 주요 설정 |
|------|--------|-----------|
| namespace.yaml | Namespace | `dongtan` |
| postgres.yaml | PVC + Deployment + Service | postgres:16-alpine, 20Gi, port 5432 |
| redis.yaml | PVC + Deployment + Service | redis:7-alpine, 5Gi, port 6379 |
| server.yaml | Deployment + Service | dongtan-server:latest, port 3001 |
| web.yaml | ConfigMap + Deployment + Service | dongtan-web:latest (nginx), port 80 |
| ingress.yaml | Middleware + Ingress | dongtan.infoedu.co.kr, TLS, Traefik |

**특징**: server는 secretRef로 DB/API 키 주입, web은 nginx ConfigMap 마운트, PostgreSQL + Redis 사용

### alls-stiker-mall K8s 매니페스트 (k8s/)

| 파일 | 리소스 | 주요 설정 |
|------|--------|-----------|
| namespace.yaml | Namespace | `alls` |
| mongodb.yaml | PVC + Deployment + Service | mongo:7, 20Gi, port 27017 |
| server.yaml | PVC + Deployment + Service | alls-server:latest, port 5001, uploads 10Gi |
| client.yaml | Deployment + Service | alls-client:latest (Next.js), port 3051 |
| ingress.yaml | Middleware + Ingress | alls-kr.shop, 다중 경로 라우팅 |

**특징**: MongoDB 사용, uploads PVC 별도 마운트, ingress에서 /api + /socket.io + /uploads → server로 라우팅

### 공통 패턴 추출

두 프로젝트에서 공통으로 사용하는 패턴:

- Namespace 생성
- Server: Deployment + Service (health check, env/secretRef, resources)
- Client: Deployment + Service (선택적 ConfigMap 마운트)
- Database: PVC + Deployment + Service (Recreate 전략, health probe)
- Ingress: Traefik Middleware (HTTPS redirect) + Ingress (TLS, cert-manager)
- 추가 PVC (uploads 등)

**차이점은 values만**: 이미지명, 포트, DB 종류, 도메인, 시크릿명, 리소스 제한

## 4. Helm Chart 구현

### 4-1. 차트 기본 구조 생성

```
charts/web-app/
├── Chart.yaml              # 차트 메타데이터 (v0.1.0)
├── values.yaml             # 모든 설정의 기본값
├── values.schema.json      # 입력값 검증 스키마
└── templates/
    └── _helpers.tpl        # 공통 헬퍼 (namespace, labels, selector)
```

**`_helpers.tpl` 핵심 헬퍼**:
- `web-app.namespace` — values.namespace 또는 Release.Namespace
- `web-app.server.selectorLabels` / `web-app.client.selectorLabels` — 컴포넌트별 셀렉터
- `web-app.serviceName` / `web-app.servicePort` — ingress에서 컴포넌트 참조 해석

### 4-2. 데이터베이스 템플릿

```
templates/databases/
├── postgresql.yaml    # PVC + Deployment + Service (secretRef로 인증)
├── mongodb.yaml       # PVC + Deployment + Service (initDatabase 지원)
└── redis.yaml         # PVC + Deployment + Service (requirepass)
```

`databases.<type>.enabled: true/false`로 선택적 활성화.
각 DB는 PVC(Recreate 전략) + health probe를 포함.

### 4-3. Server/Client 템플릿

```
templates/
├── deployment-server.yaml   # env, envFrom, volumes, healthCheck 모두 values 제어
├── service-server.yaml      # ClusterIP
├── deployment-client.yaml   # 선택적 ConfigMap 마운트 (nginx 설정 등)
└── service-client.yaml      # ClusterIP
```

**설계 포인트**: client의 configMap은 `enabled: false`가 기본. dongtan처럼 nginx 설정이 필요한 경우에만 활성화.
빈 `volumeMounts`/`volumes` 렌더링 방지를 위해 `{{- if or ... }}` 조건 처리.

### 4-4. Ingress + 미들웨어

```yaml
# ingress.yaml — 핵심 설계
paths:
  - path: /
    component: client    # ← "server" 또는 "client" 키워드
```

`component` 필드로 서비스명/포트를 자동 해석:
- `component: server` → `server.name`:`server.port`
- `component: client` → `client.name`:`client.port`

이를 통해 alls의 다중 경로 라우팅도 깔끔하게 지원:
```yaml
paths:
  - path: /socket.io → component: server
  - path: /api       → component: server
  - path: /uploads   → component: server
  - path: /          → component: client
```

### 4-5. PVC + ConfigMap

- `persistence.volumes[]` — DB PVC 외 추가 볼륨 (예: alls의 uploads-data)
- `client.configMap` — 클라이언트 전용 ConfigMap (예: dongtan의 nginx 설정)
- `configMaps[]` — 범용 추가 ConfigMap

## 5. 프로젝트별 Values 작성

### apps/dongtan/values.yaml

```yaml
namespace: dongtan
server:
  name: server
  image: { repository: docker.io/library/dongtan-server, tag: latest }
  port: 3001
  env: [NODE_ENV, PORT, DATABASE_URL(secret), REDIS_URL(secret), ...]
  envFrom: [dongtan-api-keys(optional)]
client:
  name: web
  port: 80
  configMap: { enabled: true, name: web-nginx-config, ... }  # nginx 설정
databases:
  postgresql: { enabled: true, storage: 20Gi, secretName: dongtan-db-secret }
  redis: { enabled: true, storage: 5Gi, secretName: dongtan-db-secret }
ingress:
  rules: [{ host: dongtan.infoedu.co.kr, paths: [/ → client] }]
```

### apps/alls/values.yaml

```yaml
namespace: alls
server:
  name: alls-server
  port: 5001
  volumeMounts: [uploads-storage → /app/uploads]
client:
  name: alls-client
  port: 3051
  configMap: { enabled: false }  # Next.js는 nginx 불필요
databases:
  mongodb: { enabled: true, initDatabase: sticker-mall }
persistence:
  volumes: [{ name: uploads-data, size: 10Gi }]
ingress:
  rules: [{ host: alls-kr.shop, paths: [/socket.io→server, /api→server, /uploads→server, /→client] }]
```

## 6. Helm 검증

### Lint

```bash
$ helm lint charts/web-app -f apps/dongtan/values.yaml
# 1 chart(s) linted, 0 chart(s) failed

$ helm lint charts/web-app -f apps/alls/values.yaml
# 1 chart(s) linted, 0 chart(s) failed
```

### Template 렌더링

`helm template` 결과를 기존 K8s 매니페스트와 비교하여 일치 확인:

**dongtan 렌더링 결과 (검증 완료)**:
- Namespace: `dongtan` ✓
- PostgreSQL: PVC(20Gi) + Deployment(postgres:16-alpine) + Service(5432) ✓
- Redis: PVC(5Gi) + Deployment(redis:7-alpine, requirepass) + Service(6379) ✓
- Server: Deployment(dongtan-server, port 3001, secretRef) + Service ✓
- Web: ConfigMap(nginx) + Deployment(dongtan-web, port 80, configMap mount) + Service ✓
- Ingress: TLS(dongtan-tls) + Middleware(redirect-https) + Rule(/ → web:80) ✓

**alls 렌더링 결과 (검증 완료)**:
- Namespace: `alls` ✓
- MongoDB: PVC(20Gi) + Deployment(mongo:7, initDatabase) + Service(27017) ✓
- Server: Deployment(alls-server, port 5001, uploads mount) + Service ✓
- Client: Deployment(alls-client, port 3051, no configMap) + Service ✓
- PVC: uploads-data(10Gi) ✓
- Ingress: 4개 경로 라우팅 (/socket.io, /api, /uploads → server, / → client) ✓

## 7. ArgoCD + ApplicationSet 구성

### ApplicationSet (apps/ 자동 발견)

```yaml
# cluster/argocd/applicationset.yaml
generators:
  - git:
      directories:
        - path: apps/*
        - path: apps/_template
          exclude: true    # 템플릿은 제외
```

`apps/` 하위 디렉토리를 자동 스캔 → 각 폴더가 ArgoCD Application으로 생성.
**새 프로젝트 추가 = `apps/<name>/values.yaml` 하나 추가하고 push.**

### AppProject

```yaml
# cluster/argocd/projects.yaml
destinations:
  - namespace: "*"        # 모든 네임스페이스 허용
clusterResourceWhitelist:
  - kind: Namespace       # 네임스페이스 생성 허용
```

### ArgoCD 설치 설정

```yaml
# cluster/argocd/install.yaml
server:
  extraArgs: [--insecure]  # TLS는 Traefik에서 종료
dex: { enabled: false }     # SSO 불필요
notifications: { enabled: false }  # 단일 노드 환경
```

## 8. Reusable GitHub Actions Workflow

### infra repo: build-and-push.yml

```yaml
on:
  workflow_call:
    inputs:
      app-name: { required: true }
      namespace: { required: true }
      components: { required: true }  # JSON 배열
    secrets:
      GH_PAT: { required: true }     # infra repo push용
```

**실행 흐름**:
1. Docker build (components JSON에서 이미지/Dockerfile/context 추출)
2. `docker save | k3s ctr images import` (레지스트리 없는 환경)
3. infra repo clone → `apps/<name>/values.yaml`의 image tag를 SHORT_SHA로 업데이트 → push
4. `kubectl set image` (즉시 배포, ArgoCD sync 대기 없이)
5. `kubectl rollout status` 확인

### 앱 repo에서 호출 (연결)

```yaml
# dongtan-master-guide/.github/workflows/deploy.yml
jobs:
  deploy:
    uses: SonAIengine/infra/.github/workflows/build-and-push.yml@main
    with:
      app-name: dongtan
      namespace: dongtan
      components: '[{"name":"server","dockerfile":"...","context":"."}]'
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

기존 50줄 → **10줄**로 축소. 빌드 로직 변경 시 infra repo만 수정하면 전체 반영.

## 9. 클러스터 부트스트랩

### scripts/bootstrap.sh

클러스터 초기 셋업을 자동화:

```
[1/4] cert-manager 설치 → ClusterIssuer 적용 (Let's Encrypt)
[2/4] Traefik 기본 보안 헤더 미들웨어 적용
[3/4] ArgoCD 설치 (Helm)
[4/4] ArgoCD AppProject + ApplicationSet 적용
```

### 추가 운영 스크립트

- `seal-secret.sh` — K8s Secret 생성 헬퍼 (.env 파일 또는 key-value)
- `onboard-app.sh` — 새 앱 스캐폴딩 (`apps/_template/` 복사 + 치환)

## 10. 최종 디렉토리 구조

```
infra/ (32 files)
├── charts/web-app/                    # 범용 Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.schema.json
│   └── templates/
│       ├── _helpers.tpl
│       ├── namespace.yaml
│       ├── deployment-server.yaml
│       ├── deployment-client.yaml
│       ├── service-server.yaml
│       ├── service-client.yaml
│       ├── ingress.yaml
│       ├── middleware-redirect.yaml
│       ├── pvc.yaml
│       ├── configmap.yaml
│       └── databases/
│           ├── postgresql.yaml
│           ├── mongodb.yaml
│           └── redis.yaml
├── apps/
│   ├── dongtan/values.yaml            # PostgreSQL + Redis, nginx
│   ├── alls/values.yaml               # MongoDB, Next.js, uploads
│   └── _template/values.yaml          # 온보딩 템플릿
├── cluster/
│   ├── argocd/
│   │   ├── install.yaml
│   │   ├── applicationset.yaml
│   │   └── projects.yaml
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml
│   └── traefik/
│       └── default-headers.yaml
├── .github/workflows/
│   ├── build-and-push.yml             # 재사용 가능한 빌드/배포
│   └── validate-chart.yml             # 차트 CI (lint + template)
├── scripts/
│   ├── bootstrap.sh
│   ├── seal-secret.sh
│   └── onboard-app.sh
└── docs/
    ├── ARCHITECTURE.md
    ├── ONBOARDING.md
    ├── SECRETS.md
    └── BUILD_PROCESS.md               # ← 이 문서
```

## 11. 커밋 히스토리

| 커밋 | 내용 |
|------|------|
| `ccc23eb` | feat: universal deployment platform with Helm + ArgoCD + Reusable GHA (32 files, 2252 lines) |
| `4f393aa` | fix: update repo URL from sonbs21/infra to SonAIengine/infra |

## 12. 향후 계획

- [ ] 실제 클러스터에 `bootstrap.sh` 실행하여 ArgoCD 설치
- [ ] 앱 repo의 deploy.yml을 reusable workflow 호출 방식으로 전환
- [ ] ArgoCD를 통한 첫 배포 테스트 (dongtan → alls 순)
- [ ] Sealed Secrets 또는 External Secrets Operator 도입 검토
- [ ] Helm chart 테스트 자동화 (ct lint, ct install)
