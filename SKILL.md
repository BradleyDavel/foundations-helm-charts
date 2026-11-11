---
name: golden-path-helm-chart
description: Create or maintain golden-path Helm charts using clear values ownership, layered overrides, and gated repeatable resources. Use for this repository and when applying these design principles to Helm charts elsewhere.
---

# Create and Maintain Golden Path Helm Charts

Keep Helm charts generic, predictable, and focused on one service per Helm release.

## Apply the right level of strictness

When working in this repository, preserve its exact values sections, file layout, and override order.

When working elsewhere, inspect the chart's existing conventions first. Apply the concepts in this skill without renaming established sections or restructuring working values unless the user asks for that migration. For a new chart, use this repository's structure as the recommended starting point.

## Preserve the values sections

In this repository, do not rename, remove, merge, or relocate these top-level sections unless the user explicitly requests a structural change:

- `workloads`: Deployments, DaemonSets, and StatefulSets.
- `security`: ServiceAccounts and RBAC resources.
- `autoScaling`: HPAs and PDBs.
- `network`: Services and Ingresses.
- `config`: shared environment variables, ConfigMaps, and ExternalSecrets.
- `jobs`: Jobs and CronJobs.
- `storage`: persistent storage resources.

Place every new resource collection under the section that owns it. Preserve the ownership comment and blank line between sections in values files.

In another chart, keep its existing section names but preserve the same separation of concerns. Do not place networking, security, storage, jobs, configuration, and workloads into an unrelated catch-all section.

## Respect values ownership and precedence

This repository's Helmfile loads values in this order:

```text
chart/values.yaml
        ↓
chart/region/<region>.yaml
        ↓
chart/environments/<environment>.yaml
```

Later files override earlier files. Keep configuration in the earliest layer that correctly owns it:

- `chart/values.yaml` owns complete resource definitions and shared defaults.
- `chart/region/<region>.yaml` owns regional differences such as image repositories, registries, and timezone.
- `chart/environments/<environment>.yaml` owns only environment-specific overrides such as image tags, enablement, hostnames, ExternalDNS annotations, ACM certificates, WAF Web ACLs, environment variables, and secret or parameter names.

Do not copy probes, security contexts, resources, ports, scheduling, commands, or other shared configuration into environment files. Change the base definition in `values.yaml` when the value should apply everywhere.

Named maps merge by key. Lists such as `env`, `hosts`, `ports`, `volumes`, and `volumeMounts` replace the complete inherited list, so include every required list item when overriding one.

For another chart, identify its real values-loading order before editing. Keep shared defaults in its base values, regional differences in its regional layer when one exists, and environment-only differences in its environment layer. Do not create region or environment files merely to imitate this repository when the other chart uses a different valid layering model.

## Add resources consistently

For every new Kubernetes resource under `chart/templates` in this repository, or the equivalent templates directory in another chart:

1. Name the template after the resource it creates using lowercase kebab-case, for example `deployment.yaml`, `cron-job.yaml`, or `role-binding.yaml`.
2. Keep its Kubernetes `apiVersion` in the template rather than values.
3. Add a named-map collection under the correct values section.
4. Range over that collection so multiple named entries can render independently.
5. Gate every entry with its own `enabled` value.
6. Use the map key as the logical resource name and follow the existing naming and metadata helpers.
7. Ensure one disabled entry does not prevent other entries of the same resource type from rendering.

Follow an existing template with similar scope instead of introducing a competing loop or naming pattern. When creating a new chart, use named maps as the default repeatable structure.

## Keep looping within its intended boundary

Looping exists to support multiple resources needed by one service. It is not an umbrella-chart mechanism for collecting unrelated services into one release. Apply this boundary in this repository and in other charts that adopt the pattern.

Use multiple Deployment entries only for exceptional cases where:

- two tightly coupled services must always be maintained and released together; or
- the same service needs separate Deployments, such as public and private variants.

If services can be deployed, scaled, rolled back, or owned independently, use separate Helm releases. Do not solve that case by adding more entries to one chart.

## Validate changes

In this repository, render the affected region and environment combination with Helmfile:

```bash
region=uk env=dev helmfile template
```

When adding a loopable resource, also render at least two enabled entries and confirm that disabling either entry affects only that entry.

In another repository, use its established Helm or Helmfile validation command. Verify the same observable behavior without introducing this repository's commands or file layout where they do not apply.
