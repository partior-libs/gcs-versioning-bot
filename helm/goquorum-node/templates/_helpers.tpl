{{/*
Expand the name of the chart.
*/}}
{{- define "goquorum-node.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "goquorum-node.fullname" -}}
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
{{- define "goquorum-node.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "goquorum-node.labels" -}}
helm.sh/chart: {{ include "goquorum-node.chart" . }}
{{ include "goquorum-node.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "goquorum-node.selectorLabels" -}}
app.kubernetes.io/name: {{ include "goquorum-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "goquorum-node.quorumSaName" -}}
{{include "goquorum-node.fullname" .}}-quorum-sa
{{- end }}

{{/*
Create the name of the quorum service account to use
*/}}
{{- define "goquorum-node.quorumServiceAccountName" -}}
{{- if .Values.node.quorum.serviceAccount.create }}
{{- default (include "goquorum-node.quorumSaName" .) .Values.node.quorum.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.node.quorum.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "goquorum-node.tesseraSaName" -}}
{{include "goquorum-node.fullname" .}}-tessera-sa
{{- end }}

{{/*
Create the name of the tessera service account to use
*/}}
{{- define "goquorum-node.tesseraServiceAccountName" -}}
{{- if .Values.node.tessera.serviceAccount.create }}
{{- default (include "goquorum-node.tesseraSaName" .) .Values.node.tessera.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.node.tessera.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the quorum storage class to use
*/}}
{{- define "goquorum-node.quorumStorageClassName" -}}
{{- default "quorum-storageclass" .Values.node.quorum.storageClass.name }}
{{- end }}

{{/*
Create the name of the tessera storage class to use
*/}}
{{- define "goquorum-node.tesseraStorageClassName" -}}
{{- default "tessera-storageclass" .Values.node.tessera.storageClass.name }}
{{- end }}

{{/*
TLS cert path
*/}}
{{- define "goquorum-node.tlscrt" -}}
{{ .Values.global.tlsPath }}/cert.pem
{{- end }}

{{/*
TLS key path
*/}}
{{- define "goquorum-node.tlskey" -}}
{{ .Values.global.tlsPath }}/key.pem
{{- end }}