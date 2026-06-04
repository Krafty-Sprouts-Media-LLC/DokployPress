# SFTP Setup (Optional)

Add SFTP access to manage WordPress files using any SFTP client (FileZilla, WinSCP, Cyberduck, etc.).

## Prerequisites

- WordPress stack deployed and running
- Know your WordPress volume name (see FileBrowser docs)

## Deploy SFTP Server

1. In Dokploy, create a new **Compose** service
2. Use **Raw Compose** and paste:

```yaml
services:
  sftp:
    image: atmoz/sftp:latest
    command: "${SFTP_USER:-wpuser}:${SFTP_PASSWORD}:1000"
    environment:
      - SFTP_USER=${SFTP_USER:-wpuser}
      - SFTP_PASSWORD=${SFTP_PASSWORD}
    volumes:
      - wordpress_files:/home/${SFTP_USER:-wpuser}/wordpress
    ports:
      - "22"
    networks:
      - dokploy-network
    restart: unless-stopped

networks:
  dokploy-network:
    external: true

volumes:
  wordpress_files:
    external: true
    name: YOUR_PROJECT_NAME_data  # <-- Replace with actual volume name
```

3. Go to **Environment** tab and add:
   ```
   SFTP_USER=wpuser
   SFTP_PASSWORD=YourSecurePassword123!
   ```

4. Replace `YOUR_PROJECT_NAME_data` with your actual WordPress volume name
5. Click **Deploy**

## Connect via SFTP

Use your SFTP client with:

| Setting | Value |
|---------|-------|
| Host | Your server IP or domain |
| Port | Check Dokploy for the mapped port (or use 22 if direct) |
| Protocol | SFTP |
| Username | wpuser (or your SFTP_USER) |
| Password | Your SFTP_PASSWORD |

Files are located at `/wordpress/` in your SFTP session.

## Alternative: SSH Key Authentication

For key-based authentication instead of password:

```yaml
services:
  sftp:
    image: atmoz/sftp:latest
    command: "wpuser::1000"
    volumes:
      - wordpress_files:/home/wpuser/wordpress
      - ./ssh_keys/id_rsa.pub:/home/wpuser/.ssh/keys/id_rsa.pub:ro
    ports:
      - "22"
    networks:
      - dokploy-network
    restart: unless-stopped

networks:
  dokploy-network:
    external: true

volumes:
  wordpress_files:
    external: true
    name: YOUR_PROJECT_NAME_data
```

Mount your public key to `/home/wpuser/.ssh/keys/`.

## Multiple Users

```yaml
command: "user1:password1:1000 user2:password2:1001"
```

Each user gets their own home directory. Mount WordPress files to specific users as needed.

## Port Mapping

By default, Dokploy will assign a random port. To use a fixed port:

1. In Dokploy, go to **Advanced** settings
2. Add a port mapping: `2222:22` (external:internal)
3. Connect using port 2222

## Security Recommendations

1. Use strong passwords or SSH keys
2. Consider restricting SFTP access to specific IPs using firewall rules
3. Regularly rotate credentials
4. Monitor access logs

## Troubleshooting

### Connection refused

- Check if the container is running
- Verify the port mapping in Dokploy
- Ensure firewall allows the SFTP port

### Permission denied

- Verify username and password
- Check volume mount permissions
- Ensure the volume name is correct

### Can't write files

The SFTP user needs write permissions. The atmoz/sftp image creates the user with UID 1000, which should match WordPress container's www-data in most cases.
