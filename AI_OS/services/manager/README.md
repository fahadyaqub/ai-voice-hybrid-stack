# OpenClaw Manager Build (Optional)

Default path in this stack uses a pinned prebuilt image via `OPENCLAW_IMAGE`.

Use this Dockerfile only if you explicitly need source builds:

```bash
cd AI_OS/services/manager
docker build --build-arg OPENCLAW_REF=main -t ai-os-openclaw:local .
```

Then set `OPENCLAW_IMAGE=ai-os-openclaw:local` in `.env`.
