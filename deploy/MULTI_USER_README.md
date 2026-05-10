# OpenClaw Multi-User Deployment Guide (with Sandbox)

Deploy isolated OpenClaw instances for multiple users, where each user gets their own data, ports, and optional Docker sandbox for tool isolation.

**Goal:** One command per user, then `docker compose up -d`.

---

## Prerequisites (One-Time Server Setup)

Run this **once per server** before creating any user instances. It builds the two required Docker images (~3–5 minutes).

```bash
cd deploy
bash setup-server.sh
```

What it builds:
- **`openclaw:local`** — Gateway image with Docker CLI inside (required to spawn sandbox containers)
- **`openclaw-sandbox:bookworm-slim`** — Sandbox base image

> Without `OPENCLAW_INSTALL_DOCKER_CLI=1`, sandbox containers cannot be spawned and agent tool calls will fail.

Verify both images exist:

```bash
docker images | grep -E 'openclaw|openclaw-sandbox'
```

Expected output:
```
openclaw              local        ...
openclaw-sandbox      bookworm-slim ...
```

---

## Quick Start (Per User)

### Step 1: Create a User Instance

```bash
cd deploy
bash setup-user.sh john --sandbox
```

This creates:
- `users/john/` — User directory
- `users/john/.env` — User's environment file
- `users/john/docker-compose.yml` — With Docker socket mount + sandbox config
- `users/john/data/` — User's data directory
- `users/john/CONNECTION_INFO.txt` — Connection details

What `--sandbox` does automatically:
- Mounts host `/var/run/docker.sock` into the gateway container
- Adds the host Docker group ID (`999` on Docker Desktop; auto-detected on Linux)
- Injects `agents.defaults.sandbox` config into `openclaw.json`

### Step 2: Add API Keys

Edit the user's `.env`:

```bash
nano users/john/.env
```

Uncomment and set at least one provider:

```env
# Example: using Z.AI GLM-5 (default)
ZAI_API_KEY=your-zai-key

# Or NVIDIA
NVIDIA_API_KEY=nvapi-...

# Or multiple providers
GAUSS_API_KEY=your-company-key
GEMINI_API_KEY=your-gemini-key
OPENAI_API_KEY=sk-...
```

> **Tip:** The setup script copies `openclaw.json` with `zai/glm-5` as the default model. If you use a different provider, update the model in `users/john/data/openclaw.json` under `agents.defaults.model.primary`.

### Step 3: Start the Instance

```bash
cd users/john
docker compose up -d
```

**First boot note:** The gateway installs bundled plugin runtime dependencies (`acpx`, `bonjour`, `browser`) on first startup. This takes **90–150 seconds**. The HTTP server starts only after this completes. Do not restart during this time.

### Step 4: Access Web UI

Open the URL from `CONNECTION_INFO.txt`:

```
URL:    http://localhost:18789
Token:  <your-token>
```

---

## User Management

Use `manage-users.sh` from the `deploy/` directory:

### List All Users

```bash
bash manage-users.sh list
```

Output:
```
Username            Port       Status               Token
--------------------------------------------------------------------------------
john                18789      Running              abc123...
jane                18889      Stopped              def456...
```

### Start / Stop / Restart

```bash
bash manage-users.sh start john
bash manage-users.sh stop john
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

---

## Directory Structure

```
deploy/
├── setup-user.sh          # Create new user instances
├── manage-users.sh        # Manage existing instances
├── openclaw.json          # Base config template
├── models.json            # Base models template
├── .env.template          # Reference env template
├── users/                 # All user instances
│   ├── john/
│   │   ├── .env
│   │   ├── docker-compose.yml
│   │   ├── CONNECTION_INFO.txt
│   │   └── data/
│   │       ├── openclaw.json
│   │       ├── agents/
│   │       ├── workspace/
│   │       └── ...
│   └── jane/
│       └── ...
└── backups/               # User backups
    ├── john_20250328.tar.gz
    └── jane_20250328.tar.gz
```

---

## Advanced Setup

### Custom Ports

```bash
bash setup-user.sh john --port 19000 --sandbox
```

### Create User Without Sandbox (Default Behavior)

```bash
bash setup-user.sh john
```

Same as before, but without Docker socket mount or sandbox config.

### Multiple Users Example

```bash
# Create instances for 3 users
bash setup-user.sh alice --sandbox --port 18789
bash setup-user.sh bob   --sandbox --port 18889
bash setup-user.sh charlie --sandbox --port 18989

# Start all
bash manage-users.sh start alice
bash manage-users.sh start bob
bash manage-users.sh start charlie

# Check status
bash manage-users.sh list
```

---

## Verification Steps

After `docker compose up -d`, verify the instance is healthy:

### 1. Check Container Status

```bash
cd users/john
docker compose ps
```

Expected: `STATUS` should be `healthy` (after ~30s) or at least `Up`.

### 2. Check Gateway Logs

```bash
docker compose logs -f --tail 50
```

Look for:
```
Gateway listening on http://0.0.0.0:18789
```

If you see plugin installation messages, wait for them to complete (90–150s).

### 3. Test HTTP Endpoint

```bash
curl http://localhost:18789/healthz
```

Expected: `{"status":"ok"}` (response time ~80–200ms).

### 4. Verify Models Load

```bash
docker compose run --rm openclaw-gateway \
  node dist/index.js models list
```

Or via the built-in CLI service:
```bash
docker compose run --rm openclaw-cli models list
```

### 5. Verify Sandbox (if enabled)

In the gateway container, confirm the `docker` binary is available:

```bash
docker compose exec openclaw-gateway docker --version
```

Expected: `Docker version ...`

Also verify the sandbox config was injected:

```bash
docker compose exec openclaw-gateway \
  cat /root/.openclaw/openclaw.json | jq '.agents.defaults.sandbox'
```

Expected:
```json
{
  "mode": "non-main",
  "scope": "agent",
  "workspaceAccess": "none",
  "backend": "docker"
}
```

### 6. Test a Tool Call (End-to-End)

1. Open the Web UI (`http://localhost:<PORT>`).
2. Enter the token from `CONNECTION_INFO.txt`.
3. Ask the agent: `"Please read the file /etc/os-release"`.
4. If sandbox is working, the agent will spawn a container, run the command, and return the result.

---

## Troubleshooting

### Port Already in Use

```bash
# Check what's using the port
lsof -i :18789
netstat -an | grep 18789

# Use a different port
bash setup-user.sh john --port 19000 --sandbox
```

### Container Won't Start / Hangs at "starting..."

**Symptom:** Logs show `starting...` indefinitely.

**Cause:** Corrupted or stale config from a previous failed run.

**Fix:**
```bash
bash manage-users.sh stop john
rm -rf users/john/data/openclaw.json.*.rejected users/john/data/openclaw.json.bak
bash manage-users.sh start john
```

If still stuck, wipe and recreate:
```bash
bash manage-users.sh delete john
bash setup-user.sh john --sandbox
# Re-add your API keys to .env, then start
```

### HTTP Requests Timeout (Windows Only)

**Symptom:** `curl` hangs or takes >10s; gateway process shows `D` (disk sleep) state.

**Cause:** Windows bind mount to WSL2 causes the Node.js event loop to block on filesystem access.

**Fix:** Use a Docker named volume instead of a bind mount for `/home/node/.openclaw`. If you need host visibility, set up a periodic sync via `scripts/docker/export-data.ps1`.

> This does **not** affect Linux/macOS servers.

### API Keys Not Working / SecretRefResolutionError

**Symptom:** Logs show `SecretRefResolutionError` or config auto-restore loops.

**Cause:** The `openclaw.json` contains `${NVIDIA_API_KEY}` style references but the env var is missing.

**Fix:** Write the API key directly into `users/john/data/openclaw.json` under the provider's `apiKey` field, or ensure the key is exported in `.env`.

### Sandbox Container Fails to Spawn

**Symptom:** Agent tool calls fail with Docker-related errors.

**Checks:**
1. Gateway image was built with `--build-arg OPENCLAW_INSTALL_DOCKER_CLI=1`
2. `docker compose exec openclaw-gateway docker --version` works
3. `/var/run/docker.sock` is mounted inside the container
4. The user running the gateway is in the Docker group (`group_add` in compose file)

---

## Platform Notes

### Linux Server (Recommended)

- Bind mounts work well for data directories
- Docker GID is auto-detected via `stat -c '%g' /var/run/docker.sock`
- Best performance and stability

### Windows + Docker Desktop (WSL2)

- **Bind mount disk sleep:** Use named volumes or accept occasional ~10s stalls
- **Docker GID:** Fixed at `999` (Docker Desktop default)
- **File encoding:** If editing `.env` or `docker-compose.yml` on Windows, save as **UTF-8 without BOM** (PowerShell `Out-File -Encoding utf8` creates BOM which breaks Docker Compose)
- **Data visibility:** Named volumes hide data from host. Use `./openclaw-data` local mirror + `scripts/docker/export-data.ps1` if needed

### macOS + Docker Desktop

- Docker GID is typically `999`
- Bind mounts are stable (no disk sleep issue)

---

## Security Notes

1. **Gateway Tokens:** Each user gets a unique token. Keep `CONNECTION_INFO.txt` private.

2. **Docker Socket Access:** Enabling `--sandbox` mounts the host Docker socket into the gateway container. This gives the container significant privileges (ability to spawn arbitrary containers). Only enable sandbox for trusted users.

3. **Sandbox Isolation:** The sandbox blocks bind mounts for sensitive paths (`/etc`, `/proc`, `/sys`, `/dev`, `~/.ssh`, `~/.aws`, `~/.docker`) and blocks `network: "host"`.

4. **Network Binding:** By default, binds to `lan` (accessible from local network). For public access, use a reverse proxy (nginx/traefik) and do not expose gateway ports directly.

5. **API Keys:** Stored in `.env` files — these are NOT in git. The `deploy/users/` directory is already gitignored.

6. **Data Isolation:** Each user's data is in their own directory (`users/<name>/data/`). No cross-user access by default.

---

## Migration from Single-User

If you're currently using the old single-user setup:

1. **Backup existing data:**
   ```bash
   cp -r deploy/data deploy/data.backup
   ```

2. **Create a user instance:**
   ```bash
   bash setup-user.sh myuser --sandbox
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
