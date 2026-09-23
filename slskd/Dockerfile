FROM debian:bookworm-slim

# Pin to a specific slskd GitHub release. Bump this to track new releases:
# https://github.com/slskd/slskd/releases
ARG SLSKD_VERSION="0.26.0"
ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        unzip \
        libssl3 \
        wireguard-tools \
        dante-server \
        iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Map Docker's TARGETARCH to slskd's release asset naming (.NET RIDs) and
# fetch the self-contained, single-file build for that architecture.
RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64) SLSKD_ARCH="linux-x64" ;; \
        arm64) SLSKD_ARCH="linux-arm64" ;; \
        arm)   SLSKD_ARCH="linux-arm" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    echo "Downloading slskd ${SLSKD_VERSION} (${SLSKD_ARCH})"; \
    curl -fsSL -o /tmp/slskd.zip \
        "https://github.com/slskd/slskd/releases/download/${SLSKD_VERSION}/slskd-${SLSKD_VERSION}-${SLSKD_ARCH}.zip"; \
    mkdir -p /app; \
    unzip -q /tmp/slskd.zip -d /app; \
    chmod +x /app/slskd; \
    rm -f /tmp/slskd.zip

# Avoid needing libicu for culture-specific behaviour we don't use.
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
# slskd writes its config (slskd.yml), logs and SQLite db under APP_DIR.
# Pointing this at /data means it all lives on the add-on's persistent volume.
ENV APP_DIR=/data

COPY run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 5030/tcp 50300/tcp

ENTRYPOINT [ "/run.sh" ]