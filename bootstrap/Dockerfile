FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    openssh-client \
    rsync \
    jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY bootstrap/remote_bootstrap.sh /usr/local/bin/remote_bootstrap.sh
RUN chmod +x /usr/local/bin/remote_bootstrap.sh

ENTRYPOINT ["/usr/local/bin/remote_bootstrap.sh"]
