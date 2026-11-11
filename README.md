# FOUNDATIONS: Helm Charts

A foundational building block in the **FOUNDATIONS** infrastructure-as-code series.

## Golden Path Helm Chart

A reusable Helm chart for deploying a service with common Kubernetes resources already supported and ready to configure.

## How it works

Every resource is:

- **Gated** with `enabled: true` or `enabled: false`.
- **Loopable** by adding another named entry under the resource type.

```yaml
workloads:
  deployment:
    app1:
      enabled: true
    app2:
      enabled: false
```

The chart supports multiple resources of the same type, but it is best used for one service per Helm release. This keeps deployments, configuration, scaling, and rollbacks independent.

The included `app1` and `app2` pattern is intended for special cases where two services must be released together, or the same service needs two separate Deployments.

## Values sections

Keep values under the existing section that owns the resource:

| Section | Resources |
| --- | --- |
| `workloads` | Deployments, DaemonSets, StatefulSets |
| `security` | ServiceAccounts and RBAC |
| `autoScaling` | HPAs and PDBs |
| `network` | Services and Ingresses |
| `config` | Environment variables, ConfigMaps, ExternalSecrets |
| `jobs` | Jobs and CronJobs |
| `storage` | Persistent storage resources |

Keep the ownership comment and blank line between sections when adding values:

```yaml
# Network owns Services and Ingresses.
network:
  service: {}
  ingress: {}

# Config owns shared environment variables, ConfigMaps, and ExternalSecrets.
config:
  env: {}
  externalSecrets: {}
  configMaps: {}
```

## Values override order

Values are loaded in this order:

```text
chart/values.yaml
        ↓
chart/region/<region>.yaml
        ↓
chart/environments/<environment>.yaml
```

Later files override earlier files.

- `values.yaml` contains complete resource definitions and shared defaults.
- Region files contain regional values such as image repositories and timezone.
- Environment files contain only environment-specific overrides such as image tags, hostnames, certificates, WAF Web ACLs, and secret names.

Named resource maps merge by key. Lists such as `env`, `hosts`, `ports`, and `volumes` are replaced when overridden.

## Public and private Ingress examples

The chart includes two disabled Ingress examples:

- `app1` uses an internal ALB.
- `app2` uses an internet-facing ALB.

Each environment file contains example hostnames and ExternalDNS annotations. Optional ACM and WAFv2 annotations are included as comments.

Enable only the resources required by that environment:

```yaml
workloads:
  deployment:
    app2:
      enabled: true

network:
  service:
    app2:
      enabled: true
  ingress:
    app2:
      enabled: true
```

## Before deploying

The example ECR registry account ID (`123456789012`), image paths, hostnames, and secret references are placeholders. Replace them with values for your infrastructure before deploying.

## Render the chart

Choose a region and environment with `region` and `env`:

```bash
region=uk env=dev helmfile template
```

The defaults are `uk` and `dev` when the variables are not provided.
