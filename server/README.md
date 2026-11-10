# Gharbaar server

Phase 1 backend: PostgreSQL database, API, and HTTPS through Caddy.
Runs on the Oracle Always Free Ampere server (2 OCPU, 12 GB).

## Deploy folder
- `deploy/docker-compose.yml` — PostgreSQL and Caddy
- `deploy/Caddyfile` — HTTPS for gharbaar.duckdns.org
- `deploy/secrets/` — create `db_password.txt` on the server only. Never commit it.

## On the server
1. Create the secret: `mkdir -p secrets && openssl rand -base64 32 > secrets/db_password.txt`
2. Start: `docker compose up -d`
