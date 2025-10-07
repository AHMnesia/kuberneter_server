{{- define "suma-office.fullname" -}}
{{- printf "%s" .Chart.Name -}}
{{- end -}}

{{- define "suma-office.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "suma-office.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
{{- end -}}

{{- define "suma-office.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ default (include "suma-office.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
