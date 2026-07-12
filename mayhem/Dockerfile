# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image
# (ghcr.io/mayhemheroes/base). amqp091-go is a pure-Go project; the base is C/C++-only,
# so a pinned Go toolchain plus the legacy go-fuzz tooling (go-fuzz-build -libfuzzer,
# the OSS-Fuzz compile_go_fuzzer path — the harness in fuzz.go is the legacy
# `func Fuzz(data []byte) int` form behind the gofuzz build tag) is installed here as a
# USER root step.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] -t amqp091-go-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: the base exports SANITIZER_FLAGS (ASan+UBSan, halting) as the default.
# The OSS-Fuzz Go path is ASan-only for the libFuzzer link; build.sh handles the Go specifics.
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# Pin the Go toolchain version AND its tarball sha256 (reproducible fetch). Pin go-fuzz by a
# module pseudo-version (NOT @latest) so the module cache is deterministic.
ARG GO_VERSION=1.25.1
ARG GO_SHA256=7716a0d940a0f6ae8e1f3b3f4f36299dc53e31b16840dbd171254312c41ca12e
ARG GO_FUZZ_VERSION=v0.0.0-20240924070022-e577bee5275c

# ── Go toolchain @ a FIXED, lockable, $HOME-independent prefix ──────────────────────────────────
# SPEC §6.2 item 8 + §6.5: the commit build and the PATCH re-run run under DIFFERENT $HOMEs.
# Pinning GOROOT/GOPATH/GOMODCACHE/GOCACHE under /opt/toolchains ensures the module cache
# populated during this first (online) image build is found again when build.sh re-runs offline.
ENV GOROOT=/opt/toolchains/go \
    GOPATH=/opt/toolchains/go-path \
    GOMODCACHE=/opt/toolchains/go-path/pkg/mod \
    GOCACHE=/opt/toolchains/go-path/build-cache \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=mod \
    PATH=/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:/usr/local/bin:/usr/bin:/bin

USER root
RUN install -d /opt/toolchains/go-path \
    && apt-get update -qq && apt-get install -yq --no-install-recommends wget ca-certificates git \
    && rm -rf /var/lib/apt/lists/* \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tgz \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && tar -C /opt/toolchains -xzf /tmp/go.tgz && rm -f /tmp/go.tgz \
    && go version \
    # go-fuzz + go-fuzz-build (the legacy libFuzzer build path). Installing them also seeds the
    # go-fuzz module (incl. go-fuzz-dep) into GOMODCACHE, which build.sh needs offline.
    && go install "github.com/dvyukov/go-fuzz/go-fuzz@${GO_FUZZ_VERSION}" \
    && go install "github.com/dvyukov/go-fuzz/go-fuzz-build@${GO_FUZZ_VERSION}" \
    && chmod -R a+rX /opt/toolchains/go \
    # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must read the
    # toolchain and read/refresh the module cache, so hand the GOPATH to 2000.
    && chown -R 2000:2000 /opt/toolchains/go-path

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git history)
# is copied to /mayhem; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $GOMODCACHE (online, this first build) and builds the libFuzzer target.
RUN bash mayhem/build.sh

# Run amqp091-go's own Go test suite at build time (a failing suite fails the image build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
