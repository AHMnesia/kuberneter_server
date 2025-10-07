{{- define "suma-webhook.fullname" -}}
{{- printf "%s" .Chart.Name -}}
{{- end -}}

{{- define "suma-webhook.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "suma-webhook.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}
