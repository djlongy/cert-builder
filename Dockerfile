# ─── TEMPLATE — copy to Dockerfile ─────────────────────────────────
# First-time setup:  cp Dockerfile.example Dockerfile
# Edit ONLY the marked "FORK EDITS GO HERE" region in your copy. The
# base / cert sidecar / USER restore are template logic — leave them.
# Dynamic OCI labels (version, revision, created, base.digest, source)
# are added by scripts/build.sh via `docker build --label`, not here.
# ───────────────────────────────────────────────────────────────────
#
# Build shape:
#   upstream base → cert sidecar (shell-bearing builder, so it works
#   on distroless / chainguard / scratch too) → final stage re-bases
#   FROM base → editable region → restore upstream USER.

# ── Global ARGs ──────────────────────────────────────────────────────
# build.sh passes these via --build-arg from image.env. The defaults
# below only apply if someone runs `docker build .` directly without
# the script.
ARG UPSTREAM_REGISTRY=docker.io/library
ARG UPSTREAM_IMAGE=nginx
ARG UPSTREAM_TAG=1.29.8-alpine
ARG ORIGINAL_USER=root
ARG CERT_BUILDER_IMAGE=docker.io/library/alpine:3.20

# ── Upstream base ────────────────────────────────────────────────────
FROM ${UPSTREAM_REGISTRY}/${UPSTREAM_IMAGE}:${UPSTREAM_TAG} AS base

# ── Cert sidecar (shell-bearing builder) ─────────────────────────────
# Runs in a SEPARATE image so cert prep works regardless of whether
# the upstream base has a shell (chainguard FIPS, distroless static,
# scratch). Produces an updated trust store = alpine system roots +
# the corp CAs in certs/. The final stage COPYs the files over.
#
# Trade-off: this REPLACES the upstream's /etc/ssl/certs/ca-
# certificates.crt + /etc/ssl/cert.pem with alpine's bundle. For
# most images this is fine — alpine's bundle is a superset of Mozilla
# CA list. For FIPS-only trust policies, fork this Dockerfile.
#
# Empty certs/ = sidecar runs but is a no-op (just alpine's defaults).
FROM ${CERT_BUILDER_IMAGE} AS certs-source
USER root

# Two vendored shell scripts (next to this Dockerfile in every per-
# image repo). Extracted from inline RUN so SonarQube / shellcheck
# can scan the bash. Anyone who runs `docker build .` directly gets
# a working build because every COPY source is in `ls`.
#   install-ca-certificates.sh  best-effort install of ca-certificates
#                               (skipped if rebuild tool already present)
#   inject-certs.sh             cat-append corp CA into the trust bundle
COPY install-ca-certificates.sh /tmp/install-ca-certificates.sh
COPY inject-certs.sh            /tmp/inject-certs.sh
COPY certs/                     /tmp/certs/

RUN /tmp/install-ca-certificates.sh \
 && /tmp/inject-certs.sh \
 && rm -f /tmp/install-ca-certificates.sh /tmp/inject-certs.sh

# ── Final image ──────────────────────────────────────────────────────
# Re-bases FROM base so USER stays whatever upstream had. COPY --from
# pulls the prepared trust files out of the builder. Pure file ops —
# no RUN below this point until the editable region, so this works
# for shell-less bases.
FROM base AS final
COPY --from=certs-source /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=certs-source /etc/ssl/cert.pem                  /etc/ssl/cert.pem
COPY --from=certs-source /usr/local/share/ca-certificates   /usr/local/share/ca-certificates
COPY --from=certs-source /etc/pki/ca-trust/source/anchors   /etc/pki/ca-trust/source/anchors

# ═══════════════════════════════════════════════════════════════════
# ▼▼▼  FORK EDITS GO HERE  ▼▼▼
# ═══════════════════════════════════════════════════════════════════
# cert-builder fork: bake the APK_MIRROR into /etc/apk/repositories
# so downstream consumers using this as CERT_BUILDER_IMAGE get an
# airgap-safe apk source without per-build configuration.
#
# This block is the demo of "custom script extension on top of the
# template" — bake-apk-mirror.sh lives in this repo (vendored next
# to the Dockerfile), the template knows nothing about it. The COPY
# + RUN pattern below is the entire extension surface.
USER root
ARG APK_MIRROR=""
ENV APK_MIRROR=${APK_MIRROR}
COPY bake-apk-mirror.sh /tmp/bake-apk-mirror.sh
RUN  /tmp/bake-apk-mirror.sh && rm -f /tmp/bake-apk-mirror.sh
# ═══════════════════════════════════════════════════════════════════
# ▲▲▲  END FORK EDITS  ▲▲▲
# ═══════════════════════════════════════════════════════════════════

# Restore the upstream USER. build.sh auto-detects via `crane config`
# and passes as a build-arg, so this is normally automatic. The
# default "root" only applies for direct `docker build` (no script).
ARG ORIGINAL_USER
USER ${ORIGINAL_USER}
