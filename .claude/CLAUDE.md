# Runway — K8s 배포 플랫폼

## 프로젝트 개요
- **GitHub**: https://github.com/SonAIengine/runway
- **목적**: Helm + ArgoCD + Reusable GHA 기반 범용 K8s 배포 플랫폼
- **방향**: web-app 차트 → MLOps/LLMOps 차트로 확장 예정
- **로컬 경로**: ~/projects/infra/runway

## 디렉토리 구조

```
runway/
├── charts/          # Helm charts
│   └── web-app/     # 범용 웹앱 차트 (server + client + DB)
├── apps/            # 프로젝트별 values.yaml (ArgoCD 자동 발견)
├── cluster/         # 클러스터 공유 리소스 (ArgoCD, cert-manager, Traefik)
├── .github/workflows/  # Reusable CI/CD workflows
├── scripts/         # 운영 스크립트 (bootstrap, onboard, seal-secret)
└── docs/            # 학습 문서 (아래 문서화 규칙 참조)
```

## Git 규칙
- main 직접 push 가능 (개인 프로젝트)
- git config 불필요 — 커밋 시 `-c user.name="SonAIengine" -c user.email="sonsj97@gmail.com"` 사용
- 커밋 메시지: 한글, 구체적 내용 포함 (블로그 소재 활용)

## 기술 스택
| 영역 | 기술 |
|------|------|
| K8s | K3s (single-node) |
| Ingress | Traefik |
| TLS | cert-manager + Let's Encrypt |
| GitOps | ArgoCD (ApplicationSet) |
| Package | Helm |
| CI/CD | GitHub Actions (self-hosted runner) |
| Container | Docker (레지스트리 없이 k3s ctr images import) |

## 문서화 규칙 — 학습 중심 기록

### 핵심 원칙
이 프로젝트는 **공부하면서 만드는 프로젝트**다.
작업이 끝나면 반드시 `docs/`에 학습 문서를 함께 작성한다.

### 문서 작성 시점
- 새 차트를 추가했을 때
- 새 기능/컴포넌트를 구현했을 때
- 삽질하며 해결한 문제가 있을 때
- 설계 결정을 내렸을 때 (왜 A를 선택하고 B를 버렸는지)

### 문서 구조 (docs/ 하위)
```
docs/
├── ARCHITECTURE.md       # 전체 아키텍처 (작업 시 갱신)
├── BUILD_PROCESS.md      # 프로젝트 구축 과정 기록
├── ONBOARDING.md         # 새 앱 온보딩 가이드
├── SECRETS.md            # 시크릿 관리 가이드
└── journal/              # 학습 저널 (작업별 상세 기록)
    └── YYYY-MM-DD-제목.md
```

### 학습 저널 작성 포맷 (`docs/journal/YYYY-MM-DD-제목.md`)

```markdown
# 제목 (예: GPU 워크로드를 위한 Helm 차트 설계)

## 배경
- 왜 이 작업을 하게 됐는지
- 어떤 문제를 풀려고 하는지

## 사전 조사
- 기존 오픈소스 분석 (비교표 포함)
- 참고한 자료/문서 링크

## 설계 결정
- 어떤 선택지가 있었는지
- 왜 이 방식을 선택했는지 (trade-off 분석)
- 버린 대안과 그 이유

## 구현 과정
- 단계별로 뭘 했는지
- 핵심 코드/설정 스니펫 (복붙이 아니라 설명과 함께)
- 삽질한 부분과 해결 과정

## 배운 것
- 이번 작업에서 새로 알게 된 개념/기술
- "아 이래서 이렇게 하는구나" 싶은 깨달음
- 다음에 비슷한 작업 할 때 기억할 점

## 다음 단계
- 이 작업의 후속으로 할 일
```

### Claude 작업 흐름
1. **작업 시작**: 요구사항 파악 → 사전 조사
2. **구현**: 코드/설정 작성 + 테스트
3. **문서화**: `docs/journal/`에 학습 저널 작성 (구현과 동시에 또는 직후)
4. **아키텍처 갱신**: 구조가 바뀌었으면 `ARCHITECTURE.md` 업데이트
5. **커밋**: 코드 + 문서를 함께 커밋 (문서만 별도 커밋하지 않음)

### 문서 작성 톤
- **교과서가 아니라 작업 일지** — "~했다", "~를 알게 됐다" 식의 1인칭
- 삽질 과정도 솔직하게 기록 (실패한 시도도 가치 있음)
- 핵심 개념은 짧게 설명하되, 공식 문서 링크 첨부
- 코드 스니펫은 전체 파일이 아니라 핵심 부분만 발췌 + 주석
