{{/*
ai-serving 차트 공통 헬퍼
web-app 차트의 패턴을 따름
*/}}

{{/*
차트 풀네임 (63자 제한)
*/}}
{{- define "ai-serving.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
네임스페이스: 명시 값 우선, fallback Release namespace
*/}}
{{- define "ai-serving.namespace" -}}
{{- if .Values.namespace }}
{{- .Values.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
차트 라벨
*/}}
{{- define "ai-serving.chartLabel" -}}
{{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
공통 라벨
*/}}
{{- define "ai-serving.labels" -}}
helm.sh/chart: {{ include "ai-serving.chartLabel" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
셀렉터 라벨
*/}}
{{- define "ai-serving.selectorLabels" -}}
app: {{ include "ai-serving.fullname" . }}
app.kubernetes.io/component: model-serving
{{- end }}

{{/*
서빙할 모델명 (served-model-name 또는 model.name fallback)
*/}}
{{- define "ai-serving.servedModelName" -}}
{{- if .Values.model.servedModelName }}
{{- .Values.model.servedModelName }}
{{- else }}
{{- .Values.model.name }}
{{- end }}
{{- end }}

{{/*
vLLM CLI 인자 생성
*/}}
{{- define "ai-serving.vllmArgs" -}}
- {{ .Values.model.name | quote }}
- "--host=0.0.0.0"
- "--port={{ .Values.serving.port }}"
{{- if .Values.model.quantization }}
- "--quantization={{ .Values.model.quantization }}"
{{- end }}
- "--max-model-len={{ .Values.model.maxModelLen }}"
- "--gpu-memory-utilization={{ .Values.gpu.memoryUtilization }}"
- "--max-num-seqs={{ .Values.serving.maxConcurrency }}"
- "--served-model-name={{ include "ai-serving.servedModelName" . }}"
{{- if gt (int .Values.gpu.count) 1 }}
- "--tensor-parallel-size={{ .Values.gpu.count }}"
{{- end }}
{{- if .Values.gpu.enforceEager }}
- "--enforce-eager"
{{- end }}
{{- if .Values.model.trustRemoteCode }}
- "--trust-remote-code"
{{- end }}
- "--disable-log-requests"
{{- range .Values.model.extraArgs }}
- {{ . | quote }}
{{- end }}
{{- end }}
