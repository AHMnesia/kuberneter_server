{{- define "monitoring.fullname" -}}
{{- printf "%s" .Chart.Name -}}
{{- end -}}

{{- define "monitoring.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "monitoring.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "monitoring.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ default (include "monitoring.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
