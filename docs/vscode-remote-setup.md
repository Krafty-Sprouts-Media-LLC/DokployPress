# VS Code Remote Setup

Access and edit WordPress files directly using VS Code's Remote SSH and Docker extensions.

## Prerequisites

- VS Code installed
- SSH access to your server
- Server SSH key (if password login is disabled)

## Install Extensions

Install these VS Code extensions:

1. [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
2. [Docker](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-docker)

## Configure SSH

1. Open VS Code
2. Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
3. Type "Remote-SSH: Open SSH Configuration File"
4. Select `~/.ssh/config`
5. Add your server configuration:

```
Host my-server
    HostName YOUR_SERVER_IP
    User root
    Port YOUR_SSH_PORT
    IdentityFile ~/.ssh/your_private_key
```

Replace:
- `my-server` with a friendly name for your server
- `YOUR_SERVER_IP` with your server's IP address
- `YOUR_SSH_PORT` with your SSH port (default is 22)
- `~/.ssh/your_private_key` with the path to your private key

## Connect to Server

1. Press `Cmd+Shift+P` → "Remote-SSH: Connect to Host"
2. Select your server from the list
3. VS Code opens a new window connected to your server

## Install Docker Extension on Remote

Once connected, VS Code will prompt to install extensions on the remote server. Install the Docker extension there.

## Browse Container Files

1. Click the Docker icon in the left sidebar
2. Expand **Containers**
3. Find your WordPress container
4. Right-click → **Attach Visual Studio Code**

This opens a new VS Code window inside the container where you can browse and edit `/var/www/html` (WordPress files) directly.

## Alternative: Browse via Terminal

From the connected VS Code window, open a terminal and use:

```bash
docker exec -it <container_name> bash
```

Then navigate to `/var/www/html` to view/edit files.

## Tips

- Use `Cmd+P` to quickly open files by name
- Install the PHP extension on the remote for syntax highlighting
- Changes are saved directly to the container - no need to sync

## Troubleshooting

### Connection timed out

- Verify your server IP and port are correct
- Check if SSH port is open in your server's firewall
- Test SSH from terminal: `ssh -i ~/.ssh/your_key -p YOUR_PORT root@YOUR_IP`

### Permission denied

- Ensure your SSH key path is correct
- Check key permissions: `chmod 600 ~/.ssh/your_private_key`
- Verify the public key is in the server's `~/.ssh/authorized_keys`

### Docker extension not showing containers

- Ensure your user is in the docker group: `sudo usermod -aG docker $USER`
- Or connect as root
