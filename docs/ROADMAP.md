# Runway Roadmap — K8s-Native AI Platform

> 웹앱 배포 플랫폼에서 MLOps/LLMOps 통합 플랫폼으로의 확장 로드맵

## 비전

**"Opinionated AI Stack for K8s"** — 10개 이상의 도구를 직접 조합하는 대신, 검증된 오픈소스의 최적 조합을 Helm chart 하나로 선언적 배포.

```
기존: Kubeflow + KServe + Istio + Knative + MLflow + Langfuse + Kueue + ... (각각 설치/설정)
Runway: values.yaml 하나 작성 → ArgoCD가 전체 스택 배포
```

## 현재 상태 (Phase 0 ✅)

범용 웹앱 배포 플랫폼 완성:

| 컴포넌트 | 상태 |
|----------|------|
| `charts/web-app/` | ✅ server + client + DB (PostgreSQL/MongoDB/Redis) |
| `apps/dongtan/`, `apps/alls/` | ✅ 프로젝트별 values |
| `cluster/argocd/` | ✅ ApplicationSet 자동 발견 |
| `.github/workflows/` | ✅ Reusable GHA (빌드/배포) |
| `scripts/` | ✅ bootstrap, onboard, seal-secret |

---

## 경쟁 분석: 왜 Runway가 필요한가

### 현재 생태계의 핵심 문제 — 파편화

| 영역 | 도구들 | 문제 |
|------|--------|------|
| 모델 서빙 | KServe, KubeAI, KAITO, llm-d, BentoML | KServe는 Istio+Knative 필수로 설치 복잡 |
| ML 워크플로우 | Kubeflow, Flyte, Metaflow | Kubeflow 설치에 반나절, 컴포넌트 과다 |
| 실험 추적 | MLflow, Langfuse | K8s 네이티브가 아닌 별도 서버 |
| AI Gateway | Envoy AI GW, LiteLLM, Bifrost | K8s 서빙과 통합된 솔루션 부재 |
| RAG | ??? | **K8s-native RAG 배포 솔루션 없음** |
| GPU 관리 | Kueue, Volcano, DRA | MIG/MPS/time-slicing 조합이 복잡 |
| 관측성 | Prometheus + 커스텀 | AI 전용 메트릭/대시보드 부재 |

### 주요 경쟁자 분석

| 프로젝트 | Stars | 강점 | 약점 |
|----------|-------|------|------|
| **Kubeflow** | 15.5k | 가장 넓은 ML lifecycle | 설치 복잡, UI 구식 |
| **KServe** | 5.2k | CNCF Incubating, LLMInferenceService | Istio+Knative 의존성 |
| **KubeAI** | 1.2k | 제로 의존성, prefix-aware LB | 학습/RAG 미지원 |
| **KAITO** | 1.0k | GPU 노드 자동 프로비저닝, RAGEngine | Azure 종속 |
| **llm-d** | 2.6k | 최첨단 disaggregated serving | vLLM 전용, 초기 단계 |
| **MLflow** | 24.6k | 실험 추적 de facto 표준 | K8s 네이티브 아님 |
| **Langfuse** | - | 오픈소스 LLM 관측/평가 | 서빙과 통합 안 됨 |

### Runway의 기술적 차별점

1. **K8s-native RAG Stack**: 통합 배포 솔루션이 시장에 **없음** — first mover
2. **GPU 추상화**: MIG/MPS/time-slicing을 `gpu.sharing: mig-3g.20gb` 한 줄로
3. **Envoy AI Gateway 통합**: K8s SIG 표준 (Gateway API Inference Extension) 선행 적용
4. **Scale-to-Zero GPU**: KEDA + GPU idle 메트릭으로 비용 최적화
5. **Opinionated Stack**: "뭘 써야 하지?"가 아니라 "이 조합이 최적이야"를 제시
6. **의존성 최소화**: KServe처럼 Istio+Knative 강제하지 않음 (KubeAI 철학)

---

## Phase 1: AI Model Serving (3주)

> vLLM + Envoy AI Gateway를 Helm chart로 표준화

### 목표

KServe의 복잡성 없이 모델 서빙을 선언적으로 배포. GPU 스케줄링, scale-to-zero, API fallback까지 values.yaml 하나로.

### 사용 예시

```yaml
# apps/llama3-70b/values.yaml
model:
  name: meta-llama/Llama-3.3-70B-Instruct
  engine: vllm
  quantization: awq

gpu:
  count: 2
  sharing: mig-3g.20gb       # mig-{profile} | time-slicing | mps
  scaleToZero: true           # KEDA 기반

serving:
  replicas: 1-4               # HPA min-max
  maxConcurrency: 256
  cachingStrategy: prefix     # KV cache prefix 재사용

gateway:
  enabled: true
  rateLimit:
    tokensPerMinute: 100000
  fallback:
    model: gpt-4o-mini        # 로컬 GPU 부족 시 외부 API fallback
```

### 구현 항목

```
charts/ai-serving/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── deployment-vllm.yaml      # vLLM 서빙 (GPU, readiness probe)
│   ├── service.yaml              # gRPC + HTTP
│   ├── hpa.yaml                  # GPU 메트릭 기반 오토스케일링
│   ├── keda-scaledobject.yaml    # scale-to-zero
│   ├── pvc-model.yaml            # 모델 스토리지
│   ├── gateway.yaml              # Envoy AI Gateway sidecar
│   └── configmap-engine.yaml     # vLLM 엔진 설정
cluster/
└── gpu-operator/                 # NVIDIA GPU Operator + MIG 프로파일
```

### 핵심 기술 포인트

| 기술 | 역할 | 참고 |
|------|------|------|
| **vLLM** | LLM 추론 엔진, PagedAttention | H100 기준 ~12,500 tok/s |
| **Envoy AI Gateway** | 토큰 기반 rate limiting, fallback | 1-3ms 오버헤드 |
| **KEDA** | scale-to-zero 오토스케일링 | GPU idle 시간 40% 감소 |
| **prefix-aware LB** | KV cache 히트율 극대화 | KubeAI 방식, TTFT 95% 감소 |
| **MIG/MPS 추상화** | GPU 공유 프로파일 선언 | A100: 최대 7개 격리 인스턴스 |

### 학습 키워드

- vLLM 아키텍처 (PagedAttention, continuous batching)
- KV cache 관리 (prefix caching, 계층적 offloading)
- Envoy AI Gateway 설정 (Inference Extension)
- KEDA ScaledObject for GPU
- NVIDIA MIG 프로파일 설정

---

## Phase 2: RAG Stack (3주)

> **시장에 없는 것을 만든다** — K8s-native RAG 원클릭 배포

### 목표

VectorDB + Embedding + Retriever + Ingestion을 하나의 Helm chart로. 현재 이걸 해주는 오픈소스가 **없다**.

### 사용 예시

```yaml
# apps/docs-rag/values.yaml
rag:
  embedding:
    model: BAAI/bge-m3
    engine: infinity            # Infinity Embedding 서버
    batchSize: 512

  vectordb:
    type: qdrant                # qdrant | pgvector | milvus
    storage: 50Gi
    replicas: 1

  retriever:
    topK: 10
    reranker: BAAI/bge-reranker-v2-m3
    strategy: hybrid            # dense + sparse

  ingestion:
    schedule: "0 */6 * * *"     # 6시간마다
    sources:
      - type: s3
        bucket: documents
      - type: web
        urls: ["https://docs.example.com"]
    chunking:
      strategy: semantic        # semantic | fixed | recursive
      maxTokens: 512

  evaluation:
    enabled: true
    framework: ragas
    schedule: "0 0 * * 1"       # 매주 월요일
```

### 구현 항목

```
charts/rag-stack/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment-embedding.yaml     # Embedding API 서버
│   ├── deployment-vectordb.yaml      # Qdrant/PGVector/Milvus 선택적
│   ├── deployment-retriever.yaml     # Retriever + Reranker API
│   ├── cronjob-ingestion.yaml        # 문서 수집/청킹/임베딩 파이프라인
│   ├── cronjob-evaluation.yaml       # RAGAS 자동 품질 평가
│   ├── service-*.yaml
│   └── pvc-*.yaml
```

### 핵심 기술 포인트

| 기술 | 역할 | 참고 |
|------|------|------|
| **Infinity** | 고성능 Embedding 서버 | 동적 배칭, ONNX 최적화 |
| **Qdrant** | 벡터 DB | Rust 기반, 고성능, K8s Operator 존재 |
| **BGE-M3** | 다국어 임베딩 | dense + sparse + colbert 통합 |
| **RAGAS** | RAG 품질 평가 | context precision/recall/faithfulness |
| **Semantic Chunking** | 문서 분할 | 의미 단위 분할로 검색 품질 향상 |

### 학습 키워드

- 임베딩 모델 비교 (BGE-M3 vs E5 vs Cohere)
- 청킹 전략 (semantic vs fixed vs recursive)
- 벡터 검색 최적화 (HNSW 파라미터 튜닝, hybrid search)
- RAGAS 메트릭 해석 및 개선
- Reranker의 역할과 효과

---

## Phase 3: Observability + AI Metrics (2주)

> Langfuse + Prometheus + Grafana를 K8s에 통합, AI 전용 대시보드

### 사용 예시

```yaml
# cluster/monitoring/values.yaml
monitoring:
  prometheus:
    enabled: true
    gpuMetrics: true            # DCGM exporter
  grafana:
    enabled: true
    dashboards:
      - ai-serving              # TTFT, ITL, 처리량, GPU 사용률
      - rag-quality             # RAGAS 점수 추이
      - cost-tracking           # 모델별/팀별 토큰 비용
  langfuse:
    enabled: true
    storage: clickhouse
```

### 구현 항목

```
cluster/monitoring/
├── prometheus/
│   ├── install.yaml             # kube-prometheus-stack values
│   └── dcgm-exporter.yaml      # GPU 메트릭 수집
├── grafana/
│   └── dashboards/
│       ├── ai-serving.json      # TTFT, ITL, 처리량, GPU VRAM, 큐 깊이
│       ├── rag-quality.json     # RAGAS 점수 추이, 검색 히트율
│       └── cost-tracking.json   # 모델별/팀별 토큰 비용 chargeback
└── langfuse/
    └── install.yaml             # Langfuse Helm chart values
```

### 핵심 기술 포인트

| 기술 | 역할 |
|------|------|
| **DCGM Exporter** | GPU 사용률, VRAM, 온도, 전력 메트릭 |
| **Langfuse** | LLM 트레이싱, 프롬프트 관리, 평가 |
| **ClickHouse** | Langfuse 백엔드 (고속 분석 쿼리) |
| **커스텀 메트릭** | TTFT, ITL, 토큰/초, 캐시 히트율 |

### 학습 키워드

- DCGM GPU 메트릭 체계
- Prometheus 커스텀 메트릭 설계
- Grafana 대시보드 JSON 모델
- Langfuse 아키텍처 (ClickHouse 인수 이후 변화)
- 토큰 비용 추적 모델 설계

---

## Phase 4: ML Training Pipeline (3주)

> Kubeflow 전체가 아닌, 학습 Job + MLflow + 모델 레지스트리만 경량으로

### 사용 예시

```yaml
# apps/finetune-llama3/values.yaml
training:
  type: lora                    # lora | qlora | full
  baseModel: meta-llama/Llama-3.3-8B-Instruct
  dataset:
    source: s3://datasets/my-data
    format: alpaca

  gpu:
    count: 4
    strategy: deepspeed-zero3

  tracking:
    mlflow: true
    experiment: llama3-finetune

  output:
    registry: mlflow
    autoDeploy: false           # true면 ai-serving 차트로 자동 배포
```

### 구현 항목

```
charts/ml-training/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── job-training.yaml         # K8s Job (GPU, DeepSpeed, 볼륨 마운트)
│   ├── deployment-mlflow.yaml    # MLflow 트래킹 서버
│   ├── service-mlflow.yaml
│   ├── pvc-checkpoints.yaml      # 체크포인트 스토리지
│   └── pvc-datasets.yaml         # 데이터셋 스토리지
```

### 핵심 기술 포인트

| 기술 | 역할 |
|------|------|
| **MLflow** | 실험 추적 + 모델 레지스트리 (v3 GenAI 관측) |
| **DeepSpeed ZeRO** | 분산 학습 메모리 최적화 |
| **LoRA/QLoRA** | 파라미터 효율적 파인튜닝 |
| **K8s Job** | 학습 워크로드 실행 + GPU 할당 |

### 학습 키워드

- DeepSpeed ZeRO Stage 1/2/3 차이
- LoRA vs QLoRA vs Full fine-tuning 트레이드오프
- MLflow 모델 레지스트리 → 서빙 연동
- K8s Job 실패 처리 (backoffLimit, checkpoint resume)
- 분산 학습 토폴로지 (DDP vs FSDP vs DeepSpeed)

---

## Phase 5: Agent Runtime (2주)

> gwanjong-mcp, mcp-pipeline 경험 → K8s-native Agent 실행 환경

### 사용 예시

```yaml
# apps/support-agent/values.yaml
agent:
  runtime: langchain
  tools:
    - type: mcp
      server: gwanjong-mcp
    - type: api
      openapi: https://api.example.com/openapi.json

  llm:
    ref: llama3-70b             # ai-serving 차트의 모델 참조

  tracing:
    langfuse: true

  sandbox:
    enabled: true
    networkPolicy: restricted   # K8s SIG Agent Sandbox 패턴
```

### 구현 항목

```
charts/agent-runtime/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment-agent.yaml     # Agent 런타임 (LangChain/LlamaIndex)
│   ├── configmap-tools.yaml      # 도구 레지스트리 (MCP, API)
│   ├── networkpolicy.yaml        # Agent Sandbox 보안 격리
│   └── service.yaml
```

### 핵심 기술 포인트

| 기술 | 역할 |
|------|------|
| **MCP on K8s** | 도구 서버를 K8s 서비스로 배포 |
| **Agent Sandbox** | K8s SIG Apps 산하 보안 표준 |
| **NetworkPolicy** | Agent의 네트워크 접근 제한 |
| **Langfuse Tracing** | Agent 실행 추적/디버깅 |

### 학습 키워드

- Agent 오케스트레이션 패턴 (ReAct, Plan-and-Execute)
- MCP 서버 K8s 배포 패턴
- K8s NetworkPolicy 설계
- Agent 평가 (tool call 정확도, task completion rate)

---

## 최종 디렉토리 구조

```
runway/
├── charts/
│   ├── web-app/              # Phase 0 ✅ — 범용 웹앱
│   ├── ai-serving/           # Phase 1 — vLLM + Envoy AI Gateway
│   ├── rag-stack/            # Phase 2 — Embedding + VectorDB + Retriever
│   ├── ml-training/          # Phase 4 — K8s Job + MLflow
│   └── agent-runtime/        # Phase 5 — Agent 실행 환경
├── apps/
│   ├── dongtan/              # ✅ 웹앱
│   ├── alls/                 # ✅ 웹앱
│   ├── _template/            # ✅ 온보딩 템플릿
│   ├── llama3-70b/           # 모델 서빙 예시
│   ├── docs-rag/             # RAG 파이프라인 예시
│   └── finetune-llama3/      # 파인튜닝 Job 예시
├── cluster/
│   ├── argocd/               # ✅ ApplicationSet
│   ├── cert-manager/         # ✅ Let's Encrypt
│   ├── traefik/              # ✅ Ingress
│   ├── monitoring/           # Phase 3 — Prometheus + Grafana + Langfuse
│   └── gpu-operator/         # Phase 1 — NVIDIA GPU Operator + MIG
├── docs/
│   ├── ARCHITECTURE.md       # 전체 아키텍처 (Phase별 갱신)
│   ├── BUILD_PROCESS.md      # Phase 0 구축 과정
│   ├── ONBOARDING.md         # 앱 온보딩 가이드
│   ├── SECRETS.md            # 시크릿 관리
│   ├── ROADMAP.md            # ← 이 문서
│   └── journal/              # Phase별 학습 저널
│       ├── 2026-03-XX-ai-serving-설계.md
│       ├── 2026-0X-XX-rag-stack-구현.md
│       └── ...
├── scripts/
│   ├── bootstrap.sh          # ✅ 클러스터 초기 셋업
│   ├── onboard-app.sh        # ✅ 앱 스캐폴딩
│   └── seal-secret.sh        # ✅ 시크릿 생성
└── .github/workflows/
    ├── build-and-push.yml    # ✅ 재사용 빌드/배포
    └── validate-chart.yml    # ✅ 차트 CI (lint + template)
```

## 실행 순서

**Phase 1 → 2 → 3 → 4 → 5**

| Phase | 기간 | 의존성 |
|-------|------|--------|
| 1. AI Serving | 3주 | 없음 (독립) |
| 2. RAG Stack | 3주 | Phase 1의 Embedding 서버 활용 가능 |
| 3. Observability | 2주 | Phase 1,2의 메트릭 수집 대상 |
| 4. ML Training | 3주 | Phase 1의 서빙으로 학습된 모델 배포 |
| 5. Agent Runtime | 2주 | Phase 1(LLM) + Phase 2(RAG) 연동 |

## 기술 스택 요약

| 레이어 | 선택 기술 | 선택 근거 |
|--------|----------|----------|
| 추론 엔진 | vLLM | 생태계 성숙도, llm-d 호환, 커뮤니티 |
| AI Gateway | Envoy AI Gateway | K8s SIG 표준, 1-3ms 오버헤드 |
| 임베딩 | Infinity | 동적 배칭, ONNX, 고성능 |
| 벡터 DB | Qdrant (기본) | Rust 기반 고성능, K8s Operator |
| 실험 추적 | MLflow v3 | de facto 표준, GenAI 관측 |
| LLM 관측 | Langfuse | 오픈소스, 자체 호스팅, ClickHouse |
| GPU 모니터링 | DCGM Exporter | NVIDIA 공식, Prometheus 연동 |
| 오토스케일링 | KEDA | scale-to-zero, 커스텀 메트릭 |
| 분산 학습 | DeepSpeed | ZeRO 메모리 최적화 |

## 참고 자료

### K8s AI 생태계
- [llm-d](https://github.com/llm-d/llm-d) — K8s-native 분산 추론
- [KubeAI](https://github.com/substratusai/kubeai) — 경량 AI 추론 오퍼레이터
- [KAITO](https://github.com/kaito-project/kaito) — K8s AI Toolchain Operator
- [KServe](https://github.com/kserve/kserve) — 모델 서빙 표준
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) — K8s SIG 표준

### 서빙 & 최적화
- [vLLM](https://github.com/vllm-project/vllm) — PagedAttention 기반 추론 엔진
- [Envoy AI Gateway](https://aigateway.envoyproxy.io/) — AI-aware 프록시
- [Bifrost](https://github.com/maximhq/bifrost) — Go 기반 고성능 LLM 게이트웨이

### RAG & 평가
- [Qdrant](https://github.com/qdrant/qdrant) — 벡터 DB
- [Infinity](https://github.com/michaelfeil/infinity) — 임베딩 서버
- [RAGAS](https://github.com/explodinggradients/ragas) — RAG 평가 프레임워크

### 관측 & 추적
- [Langfuse](https://github.com/langfuse/langfuse) — LLM 관측/평가
- [MLflow](https://github.com/mlflow/mlflow) — 실험 추적/모델 레지스트리

### GPU 관리
- [KEDA](https://github.com/kedacore/keda) — 이벤트 기반 오토스케일링
- [GPU Operator](https://github.com/NVIDIA/gpu-operator) — NVIDIA GPU 관리
- [Kueue](https://github.com/kubernetes-sigs/kueue) — K8s 잡 큐잉/쿼타
