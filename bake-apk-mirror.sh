#!/usr/bin/env sh
# ─── VENDORED — copy verbatim into cert-builder repo ──────────────
# Per-fork custom script. Demonstrates the container-image-template's
# extension surface: drop a script next to your Dockerfile, COPY +
# RUN it in the Dockerfile's FORK EDITS region. No template-side
# changes needed.
# ──────────────────────────────────────────────────────────────────
#
# bake-apk-mirror.sh — rewrite /etc/apk/repositories to point at an
# internal APK mirror, BEFORE any apk call runs. Bakes the mirror
# config into the cert-builder image so downstream consumers using
# CERT_BUILDER_IMAGE=<this image> automatically get the airgap-safe
# apk source without having to set APK_MIRROR themselves.
#
# Reads from env:
#   APK_MIRROR    Base URL of the alpine archive mirror. Same shape
#                 as upstream's dl-cdn.alpinelinux.org/alpine. The
#                 script appends "/v<MAJOR>.<MINOR>/main" + "/community"
#                 auto-derived from /etc/alpine-release, so one
#                 APK_MIRROR value covers every alpine version.
#                 Empty / unset → no-op (use upstream alpine repos).
#                 Example:
#                   https://artifactory.example.com/artifactory/alpine
#                 expands inside an alpine:3.20 build to:
#                   https://artifactory.example.com/artifactory/alpine/v3.20/main
#                   https://artifactory.example.com/artifactory/alpine/v3.20/community
#
# Idempotent. Safe to re-run.

set -eu

if [ -z "${APK_MIRROR:-}" ]; then
  echo "→ bake-apk-mirror.sh: APK_MIRROR unset — no-op (using upstream)"
  exit 0
fi

if [ ! -f /etc/alpine-release ]; then
  echo "WARN: not an alpine image (no /etc/alpine-release) — skipping" >&2
  exit 0
fi

ALPINE_VER="$(cut -d. -f1,2 /etc/alpine-release)"
echo "→ bake-apk-mirror.sh: rewriting /etc/apk/repositories"
echo "  APK_MIRROR=${APK_MIRROR}"
echo "  alpine version: v${ALPINE_VER}"

printf '%s/v%s/main\n%s/v%s/community\n' \
  "${APK_MIRROR}" "${ALPINE_VER}" \
  "${APK_MIRROR}" "${ALPINE_VER}" \
  > /etc/apk/repositories

cat /etc/apk/repositories
echo "✓ /etc/apk/repositories baked"
