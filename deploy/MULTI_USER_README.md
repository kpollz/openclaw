# OpenClaw Multi-User Deployment Guide

This guide explains how to deploy OpenClaw for multiple users, where each user gets their own isolated instance with separate data, configuration, and ports.

## Quick Start

### 1. Create a User Instance

```bash
cd deploy
bash setup-user.sh john
```

This creates:
- `users/john/` - User directory
- `users/john/.env` - User's environment file
- `users/john/docker-compose.yml` - User's Docker Compose config
- `users/john/data/` - User's data directory
- `users/john/CONNECTION_INFO.txt` - Connection details

### 2. Start the User's Instance

```bash
cd users/john
docker compose up -d
```

### 3. Access Web UI

Open the URL from `CONNECTION_INFO.txt`:
```
URL: http://localhost:18789
Token: <your-token>
```

## User Management

### List All Users

```bash
cd deploy
bash manage-users.sh list
```

Output:
```
Username            Port       Status               Token
--------------------------------------------------------------------------------
john                18789      Running              abc123...
jane                18889      Stopped              def456...
```

### Start/Stop a User Instance

```bash
# Start
bash manage-users.sh start john

# Stop
bash manage-users.sh stop john

# Restart
bash manage-users.sh restart john
```

### View Logs

```bash
bash manage-users.sh logs john
```

### Show Connection URL

```bash
bash manage-users.sh url john
```

### Delete a User Instance

```bash
bash manage-users.sh delete john
```

### Backup a User Instance

```bash
bash manage-users.sh backup john
# Creates: backups/john_20250328_143022.tar.gz
```

## Advanced Setup

### Custom Ports

```bash
bash setup-user.sh john --port 19000
```

### Custom UID/GID for Permissions

```bash
# Find your UID/GID
id -u
id -g

# Create with custom UID/GID
bash setup-user.sh john --uid 1001 --gid 1001
```

This fixes permission issues where files created in the container can't be edited by the host user.

### Multiple Users Example

```bash
# Create instances for 3 users
bash setup-user.sh alice --port 18789
bash setup-user.sh bob --port 18889
bash setup-user.sh charlie --port 18989

# Start all
bash manage-users.sh start alice
bash manage-users.sh start bob
bash manage-users.sh start charlie

# Check status
bash manage-users.sh list
```

## Directory Structure

```
deploy/
├── setup-user.sh          # Create new user instances
├── manage-users.sh        # Manage existing instances
├── template/              # (Future: shared templates)
├── users/                 # All user instances
│   ├── alice/
│   │   ├── .env
│   │   ├── docker-compose.yml
│   │   ├── CONNECTION_INFO.txt
│   │   └── data/
│   │       ├── agents/
│   │       ├── workspace/
│   │       └── ...
│   ├── bob/
│   │   └── ...
│   └── charlie/
│       └── ...
└── backups/              # User backups
    ├── alice_20250328.tar.gz
    └── bob_20250328.tar.gz
```

## Permission Fix Explanation

### The Problem

When Docker containers create files, they're owned by the container's user (typically `node` with UID 1000). If your host user has a different UID, you can't edit these files.

### The Solution

The `setup-user.sh` script:
1. Detects your host UID/GID (defaults to 1000:1000)
2. Passes these to docker-compose via `USER_UID` and `USER_GID`
3. The `docker-compose.yml` runs containers with your UID/GID:
   ```yaml
   user: "${USER_UID:-1000}:${USER_GID:-1000}"
   ```

Files created in the container are now owned by your host user.

## Troubleshooting

### Port Already in Use

```bash
# Check what's using the port
lsof -i :18789
netstat -an | grep 18789

# Use a different port
bash setup-user.sh john --port 19000
```

### Permission Denied Errors

```bash
# Fix with correct UID/GID
bash setup-user.sh john --uid $(id -u) --gid $(id -g)
```

### Container Won't Start

```bash
# Check logs
bash manage-users.sh logs john

# Recreate the instance
bash manage-users.sh delete john
bash setup-user.sh john
```

### API Keys Not Working

Edit the user's `.env` file:
```bash
nano users/john/.env
```

Uncomment and set your API keys:
```env
GAUSS_API_KEY=your-company-key
ZAI_API_KEY=your-zai-key
```

Then restart:
```bash
docker compose restart
```

## Migration from Single-User

If you're currently using the old single-user setup:

1. **Backup existing data:**
   ```bash
   cp -r deploy/data deploy/data.backup
   ```

2. **Create a user instance:**
   ```bash
   bash setup-user.sh myuser
   ```

3. **Copy existing data:**
   ```bash
   cp -r deploy/data.backup/* users/myuser/data/
   ```

4. **Start the new instance:**
   ```bash
   cd users/myuser
   docker compose up -d
   ```

## Security Notes

1. **Gateway Tokens**: Each user gets a unique token. Keep `CONNECTION_INFO.txt` private.

2. **Network Binding**: By default, binds to `lan` (accessible from local network). For public access, use a reverse proxy (nginx/traefik).

3. **API Keys**: Store in `.env` files - these are NOT in git. Add `users/*/` to `.gitignore`.

4. **Data Isolation**: Each user's data is in their own directory. No cross-user access.
