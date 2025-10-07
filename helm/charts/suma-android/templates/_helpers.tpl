{{- define "suma-android.fullname" -}}
{{- printf "%s" .Chart.Name -}}
{{- end -}}

{{- define "suma-android.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "suma-android.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}
