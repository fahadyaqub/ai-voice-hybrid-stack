# Optional local build for OpenClaw manager service.
# Default deployment uses pinned GHCR image for reliability on 8GB machines.
FROM node:20-bookworm-slim

ARG OPENCLAW_REPO=https://github.com/openclaw/openclaw.git
ARG OPENCLAW_REF=main

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${OPENCLAW_REF}" "${OPENCLAW_REPO}" app \
  || git clone --depth 1 "${OPENCLAW_REPO}" app

WORKDIR /src/app
RUN npm ci --omit=dev || npm install --omit=dev

EXPOSE 3400
CMD ["npm", "run", "start"]
