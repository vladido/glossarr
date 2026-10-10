# Glossarr

A fork of [Gros-Jambon-Fr/Glossarr](https://github.com/Gros-Jambon-Fr/Glossarr), based on upstream v1.3.0: a Sonarr metadata translation proxy with bounded Skyhook retries and original-field preservation on translation errors. The MIT license and upstream attribution are preserved.

[Полная русская версия / Full Russian README](README.ru.md)

## Installation

Container image: `ghcr.io/vladido/glossarr:latest` ([GHCR](https://github.com/vladido/glossarr/pkgs/container/glossarr)).

Pin an available `sha-<commit>` tag or digest for a fixed version; preserve the previous digest before updating.

Create a separate installation directory and save the following YAML as `docker-compose.yml` (complete example from [docker-compose.yml](docker-compose.yml)):

```yaml
services:
  glossarr:
    image: ghcr.io/vladido/glossarr:latest
    container_name: glossarr
    restart: unless-stopped
    ports:
      - "443:3443"   # HTTPS — Sonarr traffic
      - "3000:3000"  # HTTP  — healthcheck
    env_file:
      - .env
    environment:
      - CERT_DIR=/certs
    volumes:
      - ./certs:/certs:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

Compose uses the default Docker project network, with no external network. `certs/` is mounted read-only; preserve it together with `.env`. Ports `443` and `3000` are published on all host interfaces: restrict access with a firewall, especially to the HTTP health port. Do not add the `skyhook.sonarr.tv` override to Glossarr itself — it must reach the real Skyhook.

Requires Docker with Compose, Bash, curl, openssl, and an API key for the selected source. After saving Compose, download and inspect only the certificate and CA-trust scripts:

```sh
curl -fL https://raw.githubusercontent.com/vladido/glossarr/main/generate-certs.sh -o generate-certs.sh
curl -fL https://raw.githubusercontent.com/vladido/glossarr/main/trust-glossarr-ca.sh -o trust-glossarr-ca.sh
chmod 755 trust-glossarr-ca.sh
```

Review both scripts before execution. For reproducibility, replace `main` with your selected commit or tag in the URLs. Certificate generation replaces existing keys: do not rerun it without a backup.

### 1. Generate TLS certificates

Run the provided script to generate a custom CA and a server certificate for `skyhook.sonarr.tv`:

```bash
umask 077
bash generate-certs.sh
```

This creates a `certs/` directory containing:

| File | Description |
|---|---|
| `certs/ca.key` | CA private key; do not mount into Sonarr |
| `certs/ca.crt` | The CA certificate — mount this into Sonarr so it trusts Glossarr |
| `certs/server.crt` | The server certificate used by Glossarr |
| `certs/server.key` | The server private key |

> Certificates are valid for 10 years. Rerunning the script replaces both CA and server keys: preserve a protected backup first, then update the trusted CA in Sonarr. Generate certificates before startup: Compose mounts `certs` read-only.

### 2. Configure environment variables

```bash
umask 077
touch .env
chmod 600 .env
```

Edit `.env` with your values. At minimum, set your API key(s) and language:

```env
TVDB_API_KEY=your_tvdb_api_key
TMDB_API_KEY=your_tmdb_api_key
LANGUAGE=eng
```

See the [Configuration](#configuration) section for all available options.

### 3. Start Glossarr

```bash
docker compose config --quiet
docker compose pull
docker compose up -d
```

Glossarr listens on:
- Port `3000` — HTTP (healthcheck)
- Host port `443` → container port `3443` — HTTPS for Sonarr. The supplied Compose does not set `GLOSSARR_PORT`; leave it at `3443` while using mapping `443:3443`.

### 4. Integrate with Sonarr

Add the following to your Sonarr `docker-compose.yml`:

```yaml
extra_hosts:
  - "skyhook.sonarr.tv:<your_host_ip>"
volumes:
  - /path/to/glossarr/certs/ca.crt:/custom-cont-init.d/glossarr-ca.crt:ro
  - /path/to/glossarr/trust-glossarr-ca.sh:/custom-cont-init.d/trust-glossarr-ca.sh:ro
```

Replace `<your_host_ip>` with the IP address of the host running Glossarr (the machine where port 443 is exposed).

After changing Compose, recreate only Sonarr:

```bash
docker compose up -d --force-recreate sonarr
```

Sonarr will now route all Skyhook requests through Glossarr.

> **Note:** The `custom-cont-init.d` mechanism is supported by [linuxserver/sonarr](https://docs.linuxserver.io/images/docker-sonarr/). If you use a different image, trust the CA according to that image's documentation.

> **Port 443 conflict:** If port 443 is already in use on your host (e.g. by a reverse proxy), see [Advanced: TCP passthrough](#advanced-tcp-passthrough).


## Differences from upstream v1.3.0

- **Bounded Skyhook retries:** search and show-detail requests make up to three attempts, with a 5-second timeout per attempt and 250/500 ms delays. Upstream makes these requests once without this timeout. This contract does not cover other proxied routes or all external translation APIs.
- **Original response on a general translation error:** the original JSON is saved after Skyhook responds successfully. If show-detail or search translation processing throws, Sonarr receives that original response with HTTP 200 rather than HTTP 502. HTTP 502 is retained when Skyhook itself is unavailable.
- **Season and episode isolation:** an individual translation failure preserves that item's original fields without discarding translated show fields or successful neighboring items. TMDB ID and TVDB season-list resolution errors are also handled independently, allowing original fields to remain without failing the entire response.

TVDB/TMDB translation, field modes, AniList/Kitsu support, and the TLS/DNS integration are inherited from upstream, not new features of this fork. This is not a new upstream Glossarr release; the MIT license and upstream attribution are preserved. The instructions below document its shared features and configuration.

## Features

- Translates **show**, **season**, and **episode** metadata (title + overview)
- Supports **TVDB** and **TMDB** as translation sources, with automatic field-level fallback
- Granular per-field control: `always`, `never`, or `native` (translate only if the show's original language matches yours)
- Dual-source support: fetch from both TVDB and TMDB in parallel, merge field by field
- **Anime support** via [AniList](https://anilist.co) and/or [Kitsu](https://kitsu.io) — dedicated sources with their own language setting, auto-detected via the [anime-lists](https://github.com/Fribb/anime-lists) mapping
- Zero npm dependencies — Node.js 20 or newer
- Transparent passthrough for all other Skyhook routes

## Interface and scope

Glossarr is an HTTP(S) proxy, not a web application: it has no GUI or settings page. `logo.png` is a logo, not an interface screenshot. Configuration is environment-based; results appear in Sonarr metadata after a series refresh. The proxy does not translate media files, subtitles, or audio, or manage downloads.

There are no npm dependencies, but Node.js, the container image, TLS, and external APIs remain dependencies. Keep API keys and private keys outside Git; trust only the intended CA in Sonarr.

## How it works

Sonarr connects to `skyhook.sonarr.tv` over HTTPS to fetch metadata. Glossarr intercepts this traffic by:

1. Overriding DNS resolution for `skyhook.sonarr.tv` inside Sonarr's container (via `extra_hosts`)
2. Serving a TLS endpoint using a self-signed certificate issued by a custom CA
3. Making Sonarr trust that CA

Glossarr then forwards the request to the real Skyhook, enriches the response with translations, and returns it transparently.

## Prerequisites

- Docker & Docker Compose
- A free [TVDB API key](https://thetvdb.com/api-information) — required if using TVDB
- A free [TMDB Read Access Token](https://www.themoviedb.org/settings/api) — required if using TMDB
- `openssl` — to generate TLS certificates

## Anime support

Glossarr has first-class support for anime. It automatically detects anime shows using the [Fribb/anime-lists](https://github.com/Fribb/anime-lists) mapping — a community-maintained project that maps TVDB IDs to AniList, Kitsu, AniDB, MAL, and more. All credit for this mapping goes to its contributors.

When a show is detected as anime, Glossarr can route it through dedicated anime sources instead of TVDB/TMDB:

- **[AniList](https://anilist.co)** — free, no API key required, supports English and Japanese
- **[Kitsu](https://kitsu.io)** — free, no API key required, supports English and Japanese

Both sources are fetched at the show level. Seasons and episodes continue to use TVDB/TMDB (AniList and Kitsu do not provide episode-level translations), but with the anime language applied.

**Fallback chain for anime show title and overview:**

1. `ANIME_PRIMARY_SOURCE` in `ANIME_LANGUAGE`
2. `ANIME_SECONDARY_SOURCE` in `ANIME_LANGUAGE`
3. TVDB/TMDB in `LANGUAGE` (global fallback)
4. Available AniList/Kitsu defaults (English). When a source is unavailable or returns no value, the existing Skyhook field remains.

> If `ANIME_PRIMARY_SOURCE` and `ANIME_SECONDARY_SOURCE` are not set, all shows — including anime — use the standard `PRIMARY`/`SECONDARY` sources. Anime detection has no effect.

The anime mapping is downloaded from GitHub at container startup and cached in memory. To refresh it, restart the container.

## Configuration

All configuration is done via environment variables passed to the Glossarr container.

### API Keys

| Variable | Required | Description |
|---|---|---|
| `TVDB_API_KEY` | If using TVDB | TVDB v4 API key |
| `TMDB_API_KEY` | If using TMDB | TMDB Read Access Token |

### Language

| Variable | Default | Description |
|---|---|---|
| `LANGUAGE` | `fra` | Target language as ISO 639-2 code (`fra`, `eng`, `spa`, `deu`, `ita`, `jpn`, `kor`…) |

### Translation sources

| Variable | Default | Values | Description |
|---|---|---|---|
| `PRIMARY_TRANSLATION_SOURCE` | `tvdb` | `tvdb`, `tmdb` | Primary source for translations |
| `SECONDARY_TRANSLATION_SOURCE` | _(none)_ | `tvdb`, `tmdb` | Fallback source if a field is missing from the primary |

When both sources are configured, Glossarr fetches from both in parallel and merges results field by field — title and overview are resolved independently.

### Translation modes

Each field can be controlled independently:

| Variable | Default | Description |
|---|---|---|
| `SHOW_TITLE_MODE` | `native` | Show title |
| `SHOW_OVERVIEW_MODE` | `always` | Show overview |
| `SEASON_TITLE_MODE` | `native` | Season name |
| `SEASON_OVERVIEW_MODE` | `always` | Season overview |
| `EPISODE_TITLE_MODE` | `native` | Episode title |
| `EPISODE_OVERVIEW_MODE` | `always` | Episode overview |

Available modes:

| Mode | Behavior |
|---|---|
| `always` | Always replace with the translated value |
| `never` | Never replace — keep the original Skyhook value |
| `native` | Replace only if the show's original language matches your configured `LANGUAGE` |

> **Example:** With `LANGUAGE=fra` and `SHOW_TITLE_MODE=native`, a French show like *Les Revenants* will have its title translated, but *Breaking Bad* will keep its original title.

### Anime sources

Glossarr can detect anime automatically using the [Fribb/anime-lists](https://github.com/Fribb/anime-lists) mapping (loaded at startup) and route them through dedicated sources — [AniList](https://anilist.co) and/or [Kitsu](https://kitsu.io) — instead of TVDB/TMDB.

Both sources are free and require no API key.

| Variable | Default | Values | Description |
|---|---|---|---|
| `ANIME_PRIMARY_SOURCE` | _(none)_ | `anilist`, `kitsu` | Primary source for anime translations |
| `ANIME_SECONDARY_SOURCE` | _(none)_ | `anilist`, `kitsu` | Fallback anime source if a field is missing from the primary |
| `ANIME_LANGUAGE` | _(uses `LANGUAGE`)_ | `eng`, `jpn` | Language for anime sources. AniList and Kitsu only support English and Japanese — for any other language, Glossarr falls back to TVDB/TMDB automatically. |

**How it works:**

- If a show's TVDB ID is found in the anime-lists mapping, it is considered anime.
- Anime shows use the `ANIME_*` sources and language for **all fields** (show, seasons, episodes).
- If `ANIME_LANGUAGE` is not supported by AniList/Kitsu (e.g. `fra`), those sources return nothing and Glossarr falls back to TVDB/TMDB with the global `LANGUAGE`.
- If no anime sources are configured, all shows (including anime) use the standard `PRIMARY`/`SECONDARY` sources.
- Available AniList/Kitsu defaults can be used; empty values and failures do not erase existing Skyhook fields.

> **Example:** With `LANGUAGE=fra`, `ANIME_PRIMARY_SOURCE=anilist`, `ANIME_LANGUAGE=eng` — regular shows get French metadata from TVDB/TMDB, anime gets English metadata from AniList.

### TLS

| Variable | Default | Description |
|---|---|---|
| `CERT_DIR` | _(none)_ | Path inside the container to the directory containing `server.crt` and `server.key`. Set automatically by the provided `docker-compose.yml`. |
| `GLOSSARR_PORT` | `3443` | HTTPS port Glossarr listens on. Set to `443` to expose Glossarr directly on the standard HTTPS port (useful when no reverse proxy is involved). |

## Health check

```
GET /health
```

```json
{ "status": "ok", "language": "fra", "primary": "tvdb", "secondary": "tmdb", "anime_primary": "anilist", "anime_secondary": null, "anime_language": "eng" }
```

## Verifying results and troubleshooting

```sh
curl http://127.0.0.1:3000/health
docker compose logs --tail 100 glossarr
```

Node.js 20+ is included in the image. No host Node.js or npm dependency installation is needed. `/health` checks the process and reports configuration; it does **not** test Skyhook/TVDB/TMDB availability or actual translation.

In Sonarr, open an existing series and refresh its metadata. Compare show, season, and episode title/overview separately; `processed` log messages do not prove a field changed. This updates Sonarr metadata, so choose an appropriate series first.

| Symptom | Check |
|---|---|
| Sonarr TLS error | DNS `extra_hosts`, Glossarr address/port, `skyhook.sonarr.tv` SAN, and installed CA |
| No translation, successful request | Source translation availability, ID mapping, `LANGUAGE`, and field modes |
| `502` | Real Skyhook availability; inspect logs |
| One season/episode fails | That item's original fields remain; other items may translate |
| `.env` changes have no effect | Recreate Glossarr; a restart does not reload Compose environment |

Skyhook search/show-detail routes use up to three attempts, a 5-second timeout per attempt, and 250/500 ms delays. These are code defaults, not environment settings. Other routes use a separate catch-all request; this retry contract does not apply to them. A general translation failure returns the original Skyhook response; an individual-item failure preserves that item.

## Updates, rollback, and backup

Pull the published image with `docker compose pull`, then `docker compose up -d`. Check `/health`, TLS from Sonarr, and refreshed metadata. To roll back, pin a previous tag/digest while preserving settings and CA. To disable the proxy entirely, first remove Sonarr's `skyhook.sonarr.tv` override and recreate Sonarr, then stop Glossarr; otherwise metadata requests still target the stopped proxy.

Keep a protected backup of `.env`, Compose, and `certs/`, including private `ca.key`. Never commit them to Git. There is no application database; the anime mapping is cached in memory.


## Advanced: TCP passthrough

If port 443 is already in use on your host (e.g. by Traefik or nginx), you can configure your reverse proxy to forward TCP traffic for `skyhook.sonarr.tv` directly to Glossarr's HTTPS port, without TLS termination.

**Example with Traefik** (`dynamic.yml`):

```yaml
tcp:
  routers:
    skyhook:
      entryPoints:
        - websecure
      rule: HostSNI(`skyhook.sonarr.tv`)
      service: skyhook
      tls:
        passthrough: true
  services:
    skyhook:
      loadBalancer:
        servers:
          - address: glossarr:3443
```

In this case, remove the `ports: ["443:3443"]` mapping from Glossarr's `docker-compose.yml` and make sure Glossarr is on the same Docker network as Traefik.

## License

MIT — see [LICENSE](LICENSE)

## Developers: optional source build

With Git and Docker, build a local development image and set `image` in a local Compose copy to `glossarr:dev`. The configuration, secrets and network requirements above also apply to development.

```sh
git clone https://github.com/vladido/glossarr.git
cd glossarr
docker build -t glossarr:dev .
```
