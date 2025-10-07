{{- define "suma-pmo.fullname" -}}
{{- printf "%s" .Chart.Name -}}
{{- end -}}

{{- define "suma-pmo.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "suma-pmo.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}
