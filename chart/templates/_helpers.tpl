{{- define "template-service.name" -}}
{{- .Chart.Name -}}
{{- end -}}
{{- define "template-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "template-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "template-service.labels" -}}
{{ include "template-service.selectorLabels" . }}
{{- end -}}
{{/* Names come from map keys. Reject generated-name collisions. */}}
{{- define "template-service.resourceName" -}}
{{- $key := required "Each resource entry requires a unique name" .item.name -}}
{{- $name := .item.resourceName | default "" -}}
{{- if not $name -}}
{{- $base := include "template-service.name" .root -}}
{{- $name = ternary $base (printf "%s-%s" $base $key) (eq $key "main") -}}
{{- end -}}
{{- if gt (len $name) 63 -}}{{ fail (printf "Resource name %q exceeds 63 characters; shorten resourceName or the name in Chart.yaml" $name) }}{{- end -}}
{{- $name -}}
{{- end -}}
{{/* Resolve map keys, respecting resourceName overrides and external names. */}}
{{- define "template-service.referenceName" -}}
{{- if .externalName -}}{{ .externalName }}
{{- else -}}
{{- $name := .name | default "main" -}}
{{- if not (hasKey .items $name) -}}{{ fail (printf "Unknown resource reference %q; use its map key or an explicit external resource name" $name) }}{{- end -}}
{{- $found := mergeOverwrite (deepCopy (index .items $name)) (dict "name" $name) -}}
{{- include "template-service.resourceName" (dict "root" .root "item" $found) -}}
{{- end -}}
{{- end -}}
{{- define "template-service.metadata" -}}
name: {{ include "template-service.resourceName" . }}
{{- if not (.clusterScoped | default false) }}
namespace: {{ .root.Release.Namespace }}
{{- end }}
labels:
  {{- include "template-service.labels" .root | nindent 2 }}
{{- with .item.annotations }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
{{/* Each entry owns its pod settings and repository. */}}
{{- define "template-service.podTemplate" -}}
{{- $w := .item -}}
{{- $image := $w.image | default dict -}}
{{- $repository := required (printf "%s.%s.image.repository is required" .kind .item.name) $image.repository -}}
{{- $podLabels := omit ($w.podLabels | default dict) "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/component" -}}
metadata:
  {{- with $w.podAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- with $podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- include "template-service.labels" .root | nindent 4 }}
    app.kubernetes.io/component: {{ printf "%s-%s" .kind .item.name | quote }}
spec:
  {{- if $w.serviceAccountName }}
  serviceAccountName: {{ $w.serviceAccountName }}
  {{- else if $w.serviceAccount }}
  serviceAccountName: {{ include "template-service.referenceName" (dict "root" .root "items" .root.Values.security.serviceAccount "name" $w.serviceAccount) }}
  {{- end }}
  {{- if hasKey $w "automountServiceAccountToken" }}
  automountServiceAccountToken: {{ $w.automountServiceAccountToken }}
  {{- end }}
  {{- if or (eq .kind "job") (eq .kind "cronjob") }}
  restartPolicy: {{ $w.restartPolicy | default "Never" }}
  {{- end }}
  {{- with $w.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- range $field := list "imagePullSecrets" "initContainers" "volumes" "nodeSelector" "affinity" "tolerations" "topologySpreadConstraints" }}
  {{- with index $w $field }}
  {{ $field }}:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- if hasKey $w "terminationGracePeriodSeconds" }}
  terminationGracePeriodSeconds: {{ $w.terminationGracePeriodSeconds }}
  {{- end }}
  containers:
    - name: {{ .item.name }}
      image: {{ printf "%s:%s" $repository ($image.tag | default .root.Chart.AppVersion) | quote }}
      imagePullPolicy: {{ $image.pullPolicy | default "IfNotPresent" }}
      {{- range $field := list "command" "args" "ports" "envFrom" "volumeMounts" "resources" "securityContext" "lifecycle" }}
      {{- with index $w $field }}
      {{ $field }}:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      {{- if or .root.Values.config.env $w.env }}
      {{- $localEnv := dict }}
      {{- range $w.env }}{{- $_ := set $localEnv .name true }}{{- end }}
      env:
        {{- range $key, $value := .root.Values.config.env }}
        {{- if not (hasKey $localEnv $key) }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
        {{- with $w.env }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
      {{- range $field := list "livenessProbe" "readinessProbe" "startupProbe" }}
      {{- with index $w $field }}
      {{ $field }}:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
    {{- with $w.additionalContainers }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end -}}

{{/* Validate generated resource identities and scaling settings. */}}
{{- define "template-service.validate" -}}
{{- $root := . -}}
{{- $lists := dict "workloads.deployment" .Values.workloads.deployment "workloads.daemonset" .Values.workloads.daemonset "workloads.statefulset" .Values.workloads.statefulset "security.serviceAccount" .Values.security.serviceAccount "security.role" .Values.security.role "security.roleBinding" .Values.security.roleBinding "security.clusterRole" .Values.security.clusterRole "security.clusterRoleBinding" .Values.security.clusterRoleBinding "network.service" .Values.network.service "network.ingress" .Values.network.ingress "autoScaling.hpa" .Values.autoScaling.hpa "autoScaling.pdb" .Values.autoScaling.pdb "config.externalSecrets" .Values.config.externalSecrets "config.configMaps" .Values.config.configMaps "storage.persistentVolumeClaims" .Values.storage.persistentVolumeClaims "jobs.job" .Values.jobs.job "jobs.cronJob" .Values.jobs.cronJob -}}
{{- range $path, $items := $lists -}}
{{- $resources := dict -}}
{{- range $key, $config := $items -}}
{{- with mergeOverwrite (deepCopy $config) (dict "name" $key) -}}
{{- if .enabled -}}
{{- $name := include "template-service.resourceName" (dict "root" $root "item" .) -}}
{{- if hasKey $resources $name -}}{{ fail (printf "%s generates duplicate resource name %q" $path $name) }}{{- end -}}
{{- $_ := set $resources $name true -}}
{{- if and (eq $path "jobs.cronJob") (gt (len $name) 52) -}}{{ fail "CronJob resource names must be at most 52 characters; shorten resourceName or the name in Chart.yaml" }}{{- end -}}
{{- if eq $path "autoScaling.hpa" -}}
{{- if gt (int .minReplicas) (int .maxReplicas) -}}{{ fail "HPA minReplicas must not exceed maxReplicas" }}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{- define "template-service.workloadName" -}}
{{- $kind := .item.workloadKind | default "Deployment" | lower -}}
{{- include "template-service.referenceName" (dict "root" .root "items" (index .root.Values.workloads $kind) "name" .item.workload "externalName" .item.workloadName) -}}
{{- end -}}

{{- define "template-service.workloadSelector" -}}
{{ include "template-service.selectorLabels" .root }}
app.kubernetes.io/component: {{ printf "%s-%s" (.item.workloadKind | default "Deployment" | lower) (.item.workload | default "main") | quote }}
{{- end -}}

{{- define "template-service.autoscaled" -}}
{{- $enabled := false -}}
{{- range .root.Values.autoScaling.hpa -}}
{{- if and .enabled (not .workloadName) (eq (.workloadKind | default "Deployment") $.kind) (eq (.workload | default "main") $.item.name) -}}{{- $enabled = true -}}{{- end -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{/* Names in roleRef and ServiceAccount subjects refer to chart map keys.
externalName references a resource or account managed outside this chart. */}}
{{- define "template-service.binding" -}}
{{- $roles := .root.Values.security.role -}}
{{- if eq .item.roleRef.kind "ClusterRole" -}}{{- $roles = .root.Values.security.clusterRole -}}{{- end -}}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: {{ .item.roleRef.kind }}
  name: {{ include "template-service.referenceName" (dict "root" .root "items" $roles "name" .item.roleRef.name "externalName" .item.roleRef.externalName) }}
subjects:
  {{- range .item.subjects }}
  - kind: {{ .kind }}
    {{- if eq .kind "ServiceAccount" }}
    name: {{ include "template-service.referenceName" (dict "root" $.root "items" $.root.Values.security.serviceAccount "name" .name "externalName" .externalName) }}
    namespace: {{ .namespace | default $.root.Release.Namespace }}
    apiGroup: ""
    {{- else }}
    name: {{ (.externalName | default .name) | quote }}
    apiGroup: rbac.authorization.k8s.io
    {{- end }}
  {{- end }}
{{- end -}}
