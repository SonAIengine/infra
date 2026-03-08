# Architecture

## Overview

Runway는 **Helm Chart + ArgoCD(GitOps) + Reusable GitHub Actions** 기반의 K8s 배포 플랫폼이다. 범용 웹앱 배포에서 시작하여 MLOps/LLMOps 통합 플랫폼으로 확장 중.

### 핵심 철학: Opinionated AI Stack

```
개발자가 할 일:    values.yaml 하나 작성
Runway가 하는 일:  ArgoCD → Helm 렌더링 → K8s 리소스 생성 → 배포/스케일링/모니터링
```

## Directory Structure

```
runway/
├── charts/                  # Helm charts
│   ├── web-app/             # ✅ 범용 웹앱 (server + client + DB)
│   ├── ai-serving/          # 🔜 vLLM + Envoy AI Gateway
│   ├── rag-stack/           # 🔜 Embedding + VectorDB + Retriever
│   ├── ml-training/         # 🔜 K8s Job + MLflow
│   └── agent-runtime/       # 🔜 Agent 실행 환경
├── apps/                    # 프로젝트별 values.yaml (ArgoCD 자동 발견)
├── cluster/                 # 클러스터 공유 리소스
│   ├── argocd/              # ✅ ApplicationSet
│   ├── cert-manager/        # ✅ Let's Encrypt
│   ├── traefik/             # ✅ Ingress
│   ├── monitoring/          # 🔜 Prometheus + Grafana + Langfuse
│   └── gpu-operator/        # 🔜 NVIDIA GPU Operator
├── .github/workflows/       # ✅ 재사용 CI/CD workflows
├── scripts/                 # ✅ 운영 스크립트
└── docs/                    # 문서 + 학습 저널
```

## Charts

### `web-app/` — 범용 웹앱 (✅ 완성)

하나의 차트로 server + client + database를 모두 관리한다.

- **Server**: Node.js 백엔드 (Deployment + Service)
- **Client**: React/Next.js 프론트엔드 (Deployment + Service + optional ConfigMap)
- **Databases**: PostgreSQL, MongoDB, Redis 중 선택 (PVC + Deployment + Service)
- **Ingress**: Traefik IngressRoute + HTTPS redirect middleware
- **PVC**: 추가 볼륨 (예: uploads)

### `ai-serving/` — AI 모델 서빙 (🔜 Phase 1)

vLLM + Envoy AI Gateway를 Helm chart로 표준화.

- **vLLM**: GPU 서빙 Deployment (PagedAttention, continuous batching)
- **AI Gateway**: Envoy sidecar (토큰 rate limiting, fallback, 라우팅)
- **GPU 추상화**: MIG/MPS/time-slicing을 values 한 줄로 선언
- **Scale-to-Zero**: KEDA 기반 GPU idle 스케일링
- **Prefix-aware LB**: KV cache 히트율 극대화

### `rag-stack/` — RAG 파이프라인 (🔜 Phase 2)

K8s-native RAG 원클릭 배포 — 시장에 없는 솔루션.

- **Embedding**: Infinity 서버 (동적 배칭, ONNX)
- **VectorDB**: Qdrant/PGVector/Milvus 선택적 배포
- **Retriever**: Hybrid search + Reranker API
- **Ingestion**: CronJob 기반 문서 수집/청킹/임베딩
- **Evaluation**: RAGAS 자동 품질 평가

### `ml-training/` — ML 학습 파이프라인 (🔜 Phase 4)

Kubeflow 전체가 아닌, 경량 학습 Job + MLflow.

- **Training Job**: K8s Job (GPU, DeepSpeed, LoRA/QLoRA)
- **MLflow**: 실험 추적 + 모델 레지스트리
- **자동 연동**: 학습 완료 → 모델 등록 → ai-serving으로 배포

### `agent-runtime/` — Agent 실행 환경 (🔜 Phase 5)

K8s-native Agent 실행 + 보안 격리.

- **Agent Runtime**: LangChain/LlamaIndex 기반
- **Tool Registry**: MCP 서버/API 도구 관리
- **Sandbox**: NetworkPolicy 기반 보안 격리
- **Tracing**: Langfuse 연동

## Cluster Components

### ArgoCD + ApplicationSet (✅ 완성)

- `apps/` 디렉토리의 하위 폴더를 자동 스캔
- 각 폴더가 하나의 ArgoCD Application으로 생성됨
- auto-sync + self-heal 활성화

### Reusable GitHub Actions (✅ 완성)

- `build-and-push.yml`: Docker build → K3s import → runway repo 태그 업데이트
- 앱 repo에서 `workflow_call`로 10줄 호출

### Monitoring (🔜 Phase 3)

- **Prometheus**: kube-prometheus-stack + DCGM GPU exporter
- **Grafana**: AI 서빙/RAG 품질/비용 추적 대시보드
- **Langfuse**: LLM 트레이싱/프롬프트 관리/평가

## Infrastructure Stack

| Component | Technology | Status |
|-----------|-----------|--------|
| Kubernetes | K3s (single-node) | ✅ |
| Ingress | Traefik | ✅ |
| TLS | cert-manager + Let's Encrypt | ✅ |
| GitOps | ArgoCD (ApplicationSet) | ✅ |
| Package | Helm | ✅ |
| CI/CD | GitHub Actions (self-hosted) | ✅ |
| Container | Docker (k3s ctr import) | ✅ |
| AI Gateway | Envoy AI Gateway | 🔜 |
| GPU | NVIDIA GPU Operator + MIG | 🔜 |
| Monitoring | Prometheus + Grafana + Langfuse | 🔜 |
| Autoscaling | KEDA (scale-to-zero) | 🔜 |

## Deployment Flow

### 웹앱 (현재)

```
App Push → GHA(self-hosted) → Docker Build → K3s Import
                             → runway repo values.yaml 태그 업데이트
                             → ArgoCD 감지 → Helm Chart 렌더링 → K8s 적용
```

### AI 모델 서빙 (Phase 1 이후)

```
values.yaml 작성 (모델명, GPU 수, 스케일링 설정)
  → git push
  → ArgoCD 감지
  → ai-serving chart 렌더링
    ├── vLLM Deployment (GPU 할당, 모델 로딩)
    ├── Envoy AI Gateway (rate limit, fallback)
    ├── KEDA ScaledObject (scale-to-zero)
    └── HPA (부하 기반 스케일링)
  → 엔드포인트 Ready
```
