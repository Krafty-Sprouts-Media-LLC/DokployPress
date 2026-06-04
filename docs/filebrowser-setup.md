# FileBrowser Setup (Optional)

FileBrowser can be added as a separate compose service to manage WordPress files via a web interface.

## Prerequisites

- WordPress stack deployed and running
- Know your WordPress volume name (see below)

## Find Your WordPress Volume Name

The WordPress volume is named `{project-name}_data`. To find it:

1. In Dokploy, check your compose project name
2. Or run on your server: `docker volume ls | grep _data`

Example: If your project is `mysite-wordpressredisstack`, the volume is `mysite-wordpressredisstack_data`

## Deploy FileBrowser

1. In Dokploy, create a new **Compose** service
2. Use **Raw Compose** and paste:

```yaml
services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    command: --root /srv --address 0.0.0.0 --port 80 --database /database/filebrowser.db
    user: "0:0"
    volumes:
      - wordpress_files:/srv:rw
      - filebrowser_db:/database
    ports:
      - "80"
    networks:
      - dokploy-network
    restart: unless-stopped

networks:
  dokploy-network:
    external: true

volumes:
  wordpress_files:
    external: true
    name: YOUR_PROJECT_NAME_data # <-- Replace with actual volume name
  filebrowser_db:
```

3. Replace `YOUR_PROJECT_NAME_data` with your actual volume name
4. Click **Deploy**
5. Add a domain (e.g., `files.yourdomain.com`) pointing to filebrowser, port 80

## Getting Your Password

On first deploy, FileBrowser generates a random admin password. **Check the container logs immediately after deploying** - you'll see:

```
Generated random admin password for quick setup: xOGWRHB0t8fq
```

Login with username `admin` and the generated password. **This password is only shown once.**

### If You Missed the Password

Delete the database volume and redeploy:

```bash
docker volume rm <project-name>_filebrowser_db
```

Then redeploy and check logs for the new password

## Troubleshooting

### Volume not found

Make sure:

1. The WordPress stack is deployed and running
2. The volume name matches exactly (case-sensitive)
3. You're using `external: true` for the volume

### Permission denied

The FileBrowser container runs as root by default, which should have access to the WordPress files. If you still get permission errors, check the WordPress container's file ownership.
