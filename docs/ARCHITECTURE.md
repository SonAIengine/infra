# Architecture

## Overview

이 infra 프로젝트는 **Helm Chart + ArgoCD(GitOps) + Reusable GitHub Actions** 기반의 범용 배포 플랫폼이다.

```
App Push → GHA(self-hosted) → Docker Build → K3s Import
                             → Infra Repo values.yaml 태그 업데이트
                             → ArgoCD 감지 → Helm Chart 렌더링 → K8s 적용
```

## Directory Structure

```
infra/
├── charts/web-app/     # 범용 Helm chart (server + client + DB)
├── apps/               # 프로젝트별 values.yaml
├── cluster/            # 클러스터 공유 리소스 (ArgoCD, cert-manager, Traefik)
├── .github/workflows/  # 재사용 가능한 CI/CD workflows
├── scripts/            # 운영 스크립트
└── docs/               # 문서
```

## Components

### Helm Chart (`charts/web-app/`)

하나의 차트로 server + client + database를 모두 관리한다.

- **Server**: Node.js 백엔드 (Deployment + Service)
- **Client**: React/Next.js 프론트엔드 (Deployment + Service + optional ConfigMap)
- **Databases**: PostgreSQL, MongoDB, Redis 중 선택 (PVC + Deployment + Service)
- **Ingress**: Traefik IngressRoute + HTTPS redirect middleware
- **PVC**: 추가 볼륨 (예: uploads)

### ArgoCD + ApplicationSet

- `apps/` 디렉토리의 하위 폴더를 자동 스캔
- 각 폴더가 하나의 ArgoCD Application으로 생성됨
- auto-sync + self-heal 활성화

### Reusable GitHub Actions

- `build-and-push.yml`: Docker build → K3s import → infra repo 태그 업데이트
- 앱 repo에서 `workflow_call`로 3줄 호출

## Infrastructure Stack

| Component | Technology |
|-----------|-----------|
| Kubernetes | K3s (single-node) |
| Ingress | Traefik |
| TLS | cert-manager + Let's Encrypt |
| GitOps | ArgoCD |
| Package | Helm |
| CI/CD | GitHub Actions (self-hosted runner) |
| Container | Docker (local import, no registry) |

## Deployment Flow

1. 개발자가 앱 repo에 push
2. GitHub Actions (self-hosted) 트리거
3. Docker multi-stage build → 이미지 생성
4. `docker save | k3s ctr images import` → K3s에 직접 로드
5. infra repo의 `apps/<name>/values.yaml` 이미지 태그 업데이트
6. ArgoCD가 변경 감지 → Helm chart 렌더링 → K8s 적용
7. 즉시 배포를 위해 `kubectl set image`도 병행 (hybrid approach)
