FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080

# Install desktop, VNC, noVNC, audio and Electron dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    wget \
    jq \
    xvfb \
    fluxbox \
    x11vnc \
    novnc \
    websockify \
    net-tools \
    libfuse2 \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    libx11-xcb1 \
    libxss1 \
    xdg-utils \
    supervisor \
    xterm \
    && rm -rf /var/lib/apt/lists/*

# Download and install AgentGrid
ARG TARGETARCH
RUN set -ex; \
    ARCH=$(dpkg --print-architecture); \
    echo "Installing AgentGrid for architecture: $ARCH"; \
    mkdir -p /tmp/agentgrid-dl; \
    if [ "$ARCH" = "amd64" ]; then \
        DOWNLOAD_URL="https://agentgrid.sh/api/download/linux-deb"; \
        FALLBACK_URL="https://github.com/agent-grid/agent-grid-releases/releases/download/v2.9.2/AgentGrid-2.9.2-amd64.deb"; \
    else \
        DOWNLOAD_URL="https://github.com/agent-grid/agent-grid-releases/releases/download/v2.9.2/AgentGrid-2.9.2-arm64.deb"; \
        FALLBACK_URL="$DOWNLOAD_URL"; \
    fi; \
    curl -f -L -o /tmp/agentgrid-dl/agentgrid.deb "$DOWNLOAD_URL" || curl -f -L -o /tmp/agentgrid-dl/agentgrid.deb "$FALLBACK_URL"; \
    dpkg -i /tmp/agentgrid-dl/agentgrid.deb || apt-get update && apt-get install -f -y; \
    rm -rf /tmp/agentgrid-dl

# Set up launcher
RUN echo '#!/bin/bash\nexport DISPLAY=:1\nexec /opt/AgentGrid/agentgrid --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage "$@"' > /usr/local/bin/agentgrid-runner \
    && chmod +x /usr/local/bin/agentgrid-runner \
    && ln -sf /usr/local/bin/agentgrid-runner /usr/local/bin/agentgrid

# Supervisor config for Xvfb, Fluxbox, x11vnc, noVNC
RUN mkdir -p /etc/supervisor/conf.d
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create startup entrypoint script
RUN echo '#!/bin/bash\nset -e\nexec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

EXPOSE 6080

ENTRYPOINT ["/entrypoint.sh"]
