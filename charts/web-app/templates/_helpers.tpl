{{/*
Chart name
*/}}
{{- define "web-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name (release-name based)
*/}}
{{- define "web-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Namespace - prefer explicit value, fallback to release namespace
*/}}
{{- define "web-app.namespace" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "web-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "web-app.labels" -}}
helm.sh/chart: {{ include "web-app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
Server labels and selector
*/}}
{{- define "web-app.server.labels" -}}
{{ include "web-app.labels" . }}
app: {{ .Values.server.name }}
{{- end }}

{{- define "web-app.server.selectorLabels" -}}
app: {{ .Values.server.name }}
{{- end }}

{{/*
Client labels and selector
*/}}
{{- define "web-app.client.labels" -}}
{{ include "web-app.labels" . }}
app: {{ .Values.client.name }}
{{- end }}

{{- define "web-app.client.selectorLabels" -}}
app: {{ .Values.client.name }}
{{- end }}

{{/*
Resolve service name for ingress backend
Usage: {{ include "web-app.serviceName" (dict "component" "server" "Values" .Values) }}
*/}}
{{- define "web-app.serviceName" -}}
{{- if eq .component "server" }}
{{- .Values.server.name }}
{{- else if eq .component "client" }}
{{- .Values.client.name }}
{{- else }}
{{- .component }}
{{- end }}
{{- end }}

{{/*
Resolve service port for ingress backend
*/}}
{{- define "web-app.servicePort" -}}
{{- if eq .component "server" }}
{{- .Values.server.port }}
{{- else if eq .component "client" }}
{{- .Values.client.port }}
{{- else }}
{{- .port | default 80 }}
{{- end }}
{{- end }}
