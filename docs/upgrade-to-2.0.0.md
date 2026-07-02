<!--
Production upgrade guide: DokployPress 2.0.0 (dokploypress-*) from legacy 1.x (dokploy-wp-*).

@package DokployPress
@subpackage Documentation
-->

# Upgrade to DokployPress 2.0.0

> **Unofficial WordPress stack for Dokploy — by Krafty Sprouts Media.** Not affiliated with or endorsed by Dokploy.

Use this checklist when moving a live site from `dokploy-wp-*` (1.x) to `dokploypress-*` (2.0.0). **No data migration** — Docker volumes and `STACK_SLUG` stay the same.

## Before you start

1. **Full server backup** (volumes, Dokploy config, env vars).
2. Wait for GitHub Actions to publish `dokploypress-*:2.0.0` on GHCR.
3. Note your current `STACK_SLUG` — **do not change it**.

## Upgrade steps (Dokploy)

### GitHub provider settings

| Field | Value |
|-------|--------|
| **Repository** | `DokployPress` |
| **Branch** | `main` |
| **Compose Path** | `./blueprints/dokploypress/docker-compose.yml` |

Click **Preview Compose** — you should see `image: ghcr.io/.../dokploypress-wordpress:2.0.0` (not `build:`).

### 1. Update image lines only

In your Compose service, change **only** these three `image:` values:

```yaml
# Before (1.x)
image: ghcr.io/krafty-sprouts-media-llc/dokploy-wp-nginx:1.14.5
image: ghcr.io/krafty-sprouts-media-llc/dokploy-wp-wordpress:1.14.5
image: ghcr.io/krafty-sprouts-media-llc/dokploy-wp-plugin-installer:1.14.5

# After (2.0.0)
image: ghcr.io/krafty-sprouts-media-llc/dokploypress-nginx:2.0.0
image: ghcr.io/krafty-sprouts-media-llc/dokploypress-wordpress:2.0.0
image: ghcr.io/krafty-sprouts-media-llc/dokploypress-plugin-installer:2.0.0
```

Keep service names (`nginx`, `wordpress`, `db`, `redis`, …) and all environment variables unchanged.

### 2. Redeploy

Click **Deploy** / **Redeploy** in Dokploy.

### 3. Verify

- Site loads at your public domain.
- WordPress container logs show `[KSM]` startup lines without DB errors.
- `docker exec -it <wordpress-container> wp redis status --allow-root`
- `docker exec -it <wordpress-container> wp millicache status --allow-root`
- If multisite: confirm `WORDPRESS_MULTISITE_CONFIG` and `WORDPRESS_PUBLIC_URL` are still set.

## Multisite note

If Network Setup is in progress, ensure `WORDPRESS_MULTISITE_CONFIG` contains your six `define()` lines and `WP_MULTISITE_MODE=subdomain` (or `subfolder`) is still set. See [hosting-guide.md](hosting-guide.md#wordpress-multisite).

## Rollback

Pin back to the previous `dokploy-wp-*` tags and redeploy. Volumes are unchanged.

## New deployments

Use the **DokployPress** template from this repo (`meta.json` id: `dokploypress`) — images are `dokploypress-*` by default.
