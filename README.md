# cert-builder

Produces a **pre-baked alpine image trusted with the homelab corp CA
+ airgap-safe apk repos** — built and scanned by the
[`container-image-template`](https://git.example.com/org/container-image-template)
DevSecOps pipeline.

Downstream container builds (prometheus, redis, …) point at this
image via `CERT_BUILDER_IMAGE` in their own `image.env`. The cert
sidecar stage of those builds then runs against an image whose trust
store + apk source are pre-configured, with no per-build setup.

## What's here

| File | Purpose |
|---|---|
| `image.env` | Live per-fork config. Push backend = Artifactory, IMAGE_NAME=cert-builder. **EDIT** |
| `Dockerfile` | Vendored from template's `Dockerfile.example`. Edit only the `FORK EDITS` region |
| `bake-apk-mirror.sh` | **Custom fork script** — demonstrates the template's extension surface (vendored next to Dockerfile, COPY+RUN in the FORK EDITS region) |
| `inject-certs.sh` | Vendored verbatim from the template (cert sidecar) |
| `install-ca-certificates.sh` | Vendored verbatim from the template |
| `certs/` | `corp-ca.crt` curled here at CI time, removed after build (never committed) |
| `.gitlab-ci.yml` | GitLab pipeline — clones template, fetches corp CA, build + scan + ingest |

## How the extension story works

The container-image-template doesn't know anything about
`bake-apk-mirror.sh` — that file is **vendored into this repo** and
referenced by the Dockerfile's FORK EDITS region. The template's
build.sh runs `docker build` against this repo's context; the COPY
finds `bake-apk-mirror.sh` because it's right next to the Dockerfile,
exactly like `inject-certs.sh` works:

```dockerfile
# In the Dockerfile FORK EDITS region:
USER root
ARG APK_MIRROR=""
ENV APK_MIRROR=${APK_MIRROR}
COPY bake-apk-mirror.sh /tmp/bake-apk-mirror.sh
RUN  /tmp/bake-apk-mirror.sh && rm -f /tmp/bake-apk-mirror.sh
```

No template-side changes needed. Drop any script next to your
Dockerfile, COPY + RUN, done. The "extension surface" of the
container-image-template is just the Dockerfile FORK EDITS region.

## Pipeline flow

```
prescan (syft sbom of alpine baseline)
  ↓
build (curl corp CA → docker build → push → wipe corp CA)
  ↓
postscan: syft sbom + grype vuln + trivy sbom + trivy vuln
  ↓
ingest: sbom-post + vuln-post → Splunk HEC + Artifactory archive
```

Pushed image: `docker.artifactory.example.com/cert-builder:3.20-<gitShort>`.

## Required CI variables (Settings → CI/CD → Variables)

| Variable | Purpose |
|---|---|
| `ARTIFACTORY_PASSWORD` | masked — push secret for `team-docker-dev` |
| `CORP_CA_URL` | URL to the corp CA PEM in Artifactory (e.g. `https://artifactory.example.com/artifactory/team-generic-dev/ca/corp-ca.crt`) |
| `SPLUNK_HEC_URL` / `SPLUNK_HEC_TOKEN` | ingest stage Splunk sink (token masked) |
| `ARTIFACTORY_SBOM_ARCHIVE_REPO` | ingest stage Artifactory SBOM archive |
| `ARTIFACTORY_VULN_ARCHIVE_REPO` | ingest stage Artifactory vuln archive |
| `ALLOW_TRIVY_RUN` | `yes-i-understand-trivy-is-banned` — second gate for the trivy kill-switch |

## Corp CA rotation

1. Update `<vault-secret-path>` in Vault.
2. Re-PUT the new PEM to `team-generic-dev/ca/corp-ca.crt`:
   ```bash
   ART_PASS=$(VAULT_ADDR=https://vault.example.com:8200 \
     vault kv get -field=cicd_password <vault-secret-path>)
   VAULT_ADDR=https://vault.example.com:8200 \
     vault kv get -field=certificate <vault-secret-path> > /tmp/ca.crt
   curl -u "svc-cicd:${ART_PASS}" -T /tmp/ca.crt \
     "https://artifactory.example.com/artifactory/team-generic-dev/ca/corp-ca.crt"
   rm -f /tmp/ca.crt
   ```
3. Push any commit to this repo (or trigger a pipeline) — cert-builder
   image rebuilds against the new CA.
4. Downstream consumers using `CERT_BUILDER_IMAGE=team-docker-dev.
   artifactory.example.com/cert-builder:<tag>` pick it up on their next build.

## Local build

The template repo's build.sh works against this repo when invoked
with `--project-root`:

```bash
git clone https://git.example.com/org/container-image-template.git ../template
# fetch corp CA (or any test PEM)
curl -o certs/corp-ca.crt "$CORP_CA_URL"
bash ../template/scripts/build.sh --project-root "$(pwd)"
rm -f certs/corp-ca.crt
```
