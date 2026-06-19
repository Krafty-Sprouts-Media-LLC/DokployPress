# File Access — SSH, Docker Volumes, and Optional SFTP

WordPress files in this stack live in a **Docker named volume**, not in a `www` folder on the VPS. How you reach them depends on **how you connect**.

---

## Method 1 — SSH / WinSCP to the VPS (what you already found)

Connect WinSCP (or SSH) to your **VPS on port 22** with your server login. WordPress files for each deploy are under:

```
/var/lib/docker/volumes/<stack-slug>_data/_data/
```

**After replacing the pre-filled `STACK_SLUG` before first Deploy** (recommended):

Dokploy sets `STACK_SLUG=mysite-ksmwpstack-8zv3p5` on create (same as the ID under the stack name). Replace with `STACK_SLUG=mysite` before Deploy, then files are at:

```
/var/lib/docker/volumes/mysite_data/_data/
```

**If you leave the pre-filled value**, volumes use that long prefix:

```
/var/lib/docker/volumes/mysite-ksmwpstack-8zv3p5_data/_data/
```

In WinSCP you may browse to `/var/lib/docker/volumes/mysite_data/` first — open the **`_data` subfolder** for the WordPress root (`wp-admin`, `wp-content`, `wp-includes`).

> After **Create**, open **Environment**, **replace** the auto `STACK_SLUG` with your short project name, then **Deploy**. See [README](../README.md#stack-naming).

Related volumes for the same project:

| Volume folder | Contents |
|---------------|----------|
| `..._data` | WordPress files |
| `..._db_data` | MariaDB database files |
| `..._redis_data` | Redis data |

### Find your volume names

On the VPS:

```bash
docker volume ls | grep _data
```

Or in Dokploy, check **Environment** for `STACK_SLUG` — the WordPress volume is `{STACK_SLUG}_data`. Without `STACK_SLUG`, use the compose project name from `docker volume ls`.

> **Inside the WordPress container** the same files appear as `/var/www/html`. That path is only meaningful inside the container, not on the VPS host.

---

## Method 2 — Optional SFTP container (off by default)

The stack can also run a dedicated **SFTP container** that mounts the same `wordpress_data` volume. This is **optional** and **disabled unless you enable it**.

Use this if you want SFTP credentials separate from VPS SSH, or a migration plugin asks for SFTP host/port/user/pass.

### Turn SFTP ON

Dokploy → Compose service → **Environment**:

```env
COMPOSE_PROFILES=tools
SFTP_USER=wpuser
SFTP_PASSWORD=YourSecurePassword123!
SFTP_PORT=2222
```

Click **Redeploy**. Confirm an **`sftp`** container is running.

> If `SFTP_PORT` is not set on an older deploy, Docker/Dokploy may publish the SFTP container on a random host port. Check the service's published port in Dokploy or with `docker inspect`, then use that host port in your SFTP client.

### Connect WinSCP to the SFTP container

| Setting | Value |
|---------|-------|
| Protocol | SFTP |
| Host | VPS IP |
| Port | `SFTP_PORT` (default `2222`; not the VPS SSH port `22`) |
| User | `SFTP_USER` |
| Password | `SFTP_PASSWORD` |

Browse until you see `wp-content`, `wp-admin`, etc. The exact folder names WinSCP displays depend on the SFTP image layout — use whatever path shows your site files.

### SFTP paths are not VPS paths

The SFTP container mounts the WordPress volume at:

```text
/home/<sftp-user>/public_html
```

Because the SFTP user is chrooted to `/home/<sftp-user>`, SFTP clients see that same folder as:

```text
/public_html
```

Use `/public_html` as the WordPress root in WinSCP or migration tools. For example, a generic plugin directory would be:

```text
/public_html/wp-content/plugins/example-plugin/
```

Do not use the VPS Docker volume path when connected to the SFTP container. That path is only valid when you are logged in to the VPS host by SSH.

### Turn SFTP OFF

Remove `tools` from `COMPOSE_PROFILES` (or delete the variable) and redeploy. WordPress data is unchanged.

---

## Migration plugins (Migrate Guru, etc.)

**We do not prescribe a remote path.** You enter whatever path your connection method requires:

- **SSH / volume access** — use the Docker volume path you verified (e.g. `..._data/_data/`)
- **SFTP container** — use the path where you see `wp-content` in WinSCP after connecting to the SFTP port

Configure host, port, username, password, and directory in the migration plugin according to **your** setup.

For SFTP container connections, the WordPress root is `/public_html`. For VPS SSH connections, use the Docker volume path on the VPS host.

---

## Optional SFTP variables

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROFILES` | — | Set to `tools` to start SFTP |
| `SFTP_USER` | `wpuser` | SFTP username |
| `SFTP_PASSWORD` | — | SFTP password (set in Dokploy) |
| `SFTP_PORT` | `2222` | Public VPS port forwarded to the SFTP container |
| `SFTP_UID` | `33` | File owner UID (`www-data`) |
