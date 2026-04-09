{{/*
============================================================
_helpers.tpl — Shared template helpers
============================================================
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "celery-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "celery-platform.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "celery-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "celery-platform.labels" -}}
helm.sh/chart: {{ include "celery-platform.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: django-celery-platform
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels for a specific component.
Usage: {{ include "celery-platform.selectorLabels" (dict "component" "worker-fast" "context" .) }}
*/}}
{{- define "celery-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "celery-platform.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Worker environment variables shared across all worker pods.
*/}}
{{- define "celery-platform.workerEnv" -}}
- name: PYTHONPATH
  value: /app
- name: DJANGO_SETTINGS_MODULE
  value: {{ .Values.django.settingsModule | quote }}
- name: CONTAINER_ENV
  value: "true"
- name: RESULT_BACKEND
  value: {{ .Values.resultBackend | quote }}
- name: REDIS_HOST
  {{- if .Values.redis.external.enabled }}
  value: {{ .Values.redis.external.url | quote }}
  {{- else }}
  value: {{ include "celery-platform.fullname" . }}-redis
  {{- end }}
- name: REDIS_PORT
  value: {{ .Values.redis.port | quote }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "celery-platform.fullname" . }}-secrets
      key: redis-password
{{- if or (eq .Values.brokerMode "rabbitmq") (eq .Values.brokerMode "hybrid") }}
- name: RABBITMQ_HOST
  {{- if .Values.rabbitmq.external.enabled }}
  value: {{ .Values.rabbitmq.external.url | quote }}
  {{- else }}
  value: {{ include "celery-platform.fullname" . }}-rabbitmq
  {{- end }}
- name: RABBITMQ_PORT
  value: {{ .Values.rabbitmq.port | quote }}
- name: RABBITMQ_USER
  value: {{ .Values.rabbitmq.user | quote }}
- name: RABBITMQ_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "celery-platform.fullname" . }}-secrets
      key: rabbitmq-password
{{- end }}
{{- if eq .Values.brokerMode "kafka" }}
- name: KAFKA_HOST
  {{- if .Values.kafka.external.enabled }}
  value: {{ .Values.kafka.external.bootstrapServers | quote }}
  {{- else }}
  value: {{ include "celery-platform.fullname" . }}-kafka
  {{- end }}
- name: KAFKA_PORT
  value: {{ .Values.kafka.port | quote }}
{{- end }}
- name: TZ
  value: UTC
{{- end }}

{{/*
Determine if RabbitMQ should be enabled based on mode and brokerMode.
*/}}
{{- define "celery-platform.rabbitmqEnabled" -}}
{{- if and (ne .Values.mode "minimal") (or (eq .Values.brokerMode "rabbitmq") (eq .Values.brokerMode "hybrid")) }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Determine if Kafka should be enabled based on brokerMode.
*/}}
{{- define "celery-platform.kafkaEnabled" -}}
{{- if eq .Values.brokerMode "kafka" }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Determine if observability should be enabled based on mode.
*/}}
{{- define "celery-platform.observabilityEnabled" -}}
{{- if and .Values.observability.enabled (ne .Values.mode "minimal") }}
{{- true }}
{{- end }}
{{- end }}
