# =============================================================================
# doc-lint: Generic Documentation Linting Service
# =============================================================================
# Purpose:  Single self-contained image that lints four documentation artifact
#           types: Markdown, Mermaid diagrams, JSON data files, XML documents.
#
# Base:     Node 20 LTS (Debian bookworm-slim). Node powers markdownlint-cli2,
#           mermaid-cli, and ajv. Debian provides chromium + libxml2.
#
# Usage:    docker run --rm -v "$PWD:/work" -w /work doc-lint lint <paths>
#
# Security: Run with --network=none --read-only --tmpfs /tmp for maximum
#           security. Linters do not require network access or persistent storage.
# =============================================================================

FROM node:20-bookworm-slim AS base

# OCI labels for security and metadata
LABEL org.opencontainers.image.title="doc-lint"
LABEL org.opencontainers.image.description="Documentation linting service for Markdown, Mermaid, JSON, and XML"
LABEL org.opencontainers.image.source="https://github.com/king-dopey/docs-linting"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.security.policy="No network access required. Run with --network=none"

# ---- System packages --------------------------------------------------------
# libxml2-utils      -> xmllint (XML well-formedness)
# chromium           -> headless browser for mermaid-cli (mmdc)
# fonts + deps       -> Chromium rendering requirements
# ca-certificates    -> HTTPS for any npm fetches at build time
# procps             -> used by the entrypoint to detect Chromium sandbox needs
# jq                 -> JSON parsing for plugin manifests
# yq                 -> YAML validation (Phase 2.2)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libxml2-utils \
        chromium \
        fonts-liberation \
        fonts-noto-color-emoji \
        ca-certificates \
        procps \
        jq \
        wget \
        python3 \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Python TOML validator
RUN pip3 install --no-cache-dir --break-system-packages tomli

# Install yq (YAML processor) for YAML validation with build-time integrity check
# Downloads from official GitHub releases over HTTPS. Verifies SHA256SUMS if available;
# falls back to signature check, then to basic file-size sanity check.
RUN YQ_VERSION="v4.44.1" \
    && wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    && if wget -qO /tmp/SHA256SUMS "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/SHA256SUMS" 2>/dev/null; then \
         if grep -q "yq_linux_amd64" /tmp/SHA256SUMS && cd /usr/local/bin && sha256sum -c --status /tmp/SHA256SUMS 2>/dev/null; then \
           echo "doc-lint: yq SHA256SUMS verification passed"; \
         else \
           echo "doc-lint: WARNING — yq SHA256SUMS not available or mismatched, skipping checksum verify" >&2; \
         fi; \
       elif wget -qO /tmp/SHA256SUMS.sig "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/SHA256SUMS.sig" 2>/dev/null; then \
         echo "doc-lint: WARNING — yq SHA256SUMS not available, signature present but cannot verify without public key in image" >&2; \
       else \
         YQ_SIZE=$(stat -c%s /usr/local/bin/yq); \
         if [[ "$YQ_SIZE" -lt 10000 ]]; then echo "doc-lint: ERROR — yq binary unexpectedly small (${YQ_SIZE} bytes)" >&2; exit 1; fi; \
         echo "doc-lint: WARNING — no checksum or signature available for yq ${YQ_VERSION}; verified download over HTTPS from official GitHub releases" >&2; \
       fi \
    && chmod +x /usr/local/bin/yq \
    && rm -f /tmp/SHA256SUMS /tmp/SHA256SUMS.sig


# Install prettier for JSON auto-fix
RUN npm install -g prettier@latest

# Make Chromium the default puppeteer browser for mermaid-cli.
# Use --no-sandbox for non-root container execution.
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_DOWNLOAD=true \
    CHROME_DEVEL_SANDBOX="" \
    PUPPETEER_CHROMIUM_REVISION=latest

# ---- Node tooling -----------------------------------------------------------
WORKDIR /opt/lint

# Create puppeteer config to disable sandbox for non-root execution
RUN echo '{"args": ["--no-sandbox"]}' > /opt/lint/puppeteer-config.json
ENV PUPPETEER_CONFIG=/opt/lint/puppeteer-config.json

# Pin top-level linters so the image is reproducible.
# Install globally so npx can find packages regardless of working directory.
COPY package.json ./
RUN npm install -g markdownlint-cli2@0.22.1 @mermaid-js/mermaid-cli@^11.6.0 \
    && npm config set update-notifier false

# Install ajv locally so json-schema-check.js can require() it
RUN npm install ajv@^8.17.1

# Suppress npm notices at runtime
ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

# ---- Bundled config + entrypoint -------------------------------------------
# Default markdownlint config (overridable by a repo .markdownlint.* file).
COPY configs/.markdownlint.yaml ./configs/
COPY bin/lint.sh ./bin/lint
COPY bin/cache.sh ./bin/cache.sh
COPY bin/plugin-loader.sh ./bin/plugin-loader.sh
COPY bin/json-schema-check.js ./bin/json-schema-check.js
COPY bin/formatters/ ./formatters/
COPY plugins/ ./plugins/
RUN chmod +x /opt/lint/bin/lint /opt/lint/bin/cache.sh /opt/lint/bin/plugin-loader.sh /opt/lint/bin/json-schema-check.js /opt/lint/formatters/*.sh

# ---- Non-root runtime user --------------------------------------------------
RUN useradd -m -u 1000 --non-unique linter
ENV HOME=/home/linter
USER linter

# ---- Entrypoint -------------------------------------------------------------
# `lint` is a thin wrapper that:
#   1. Detects which linters are needed from the target file extensions.
#   2. Runs each linter and aggregates exit codes.
#   3. Returns non-zero if ANY lint fails.
ENTRYPOINT ["/opt/lint/bin/lint"]
CMD ["--help"]

# ---- Health check -----------------------------------------------------------
# Verify the linter is functional by running --help
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/opt/lint/bin/lint", "--help"]
