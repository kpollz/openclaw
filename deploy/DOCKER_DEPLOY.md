# OpenClaw Docker Deployment

Triển khai OpenClaw nội bộ bằng Docker, bỏ qua bước onboard wizard.

## Vấn đề gốc

Khi chạy OpenClaw bằng Docker, bước `onboard` wizard (CLI interactive) bị skip, dẫn đến:

| Thiếu gì | Hậu quả |
|-----------|---------|
| `wizard` section trong `openclaw.json` | Gateway coi như chưa setup, thiếu config |
| `models.providers` | Không có LLM nào để chọn trong Web UI |
| `agents/main/agent/models.json` | Model catalog rỗng |
| `agents.defaults.model.primary` | Không biết dùng model nào làm mặc định |
| Device pairing | Mỗi browser phải được admin approve thủ công |

## Giải pháp

Tạo sẵn config files (pre-baked) thay thế cho wizard:

```
deploy/
├── .env.template       # Template biến môi trường
├── openclaw.json       # Config chính (copy vào data/)
├── models.json         # Model catalog (copy vào data/agents/main/agent/)
├── setup.sh            # Script tự động setup
└── DOCKER_DEPLOY.md    # File này
```

## Quick Start

```bash
# 1. Build image (1 lần)
docker build -t openclaw:local -f Dockerfile .

# 2. Setup
cd deploy
bash setup.sh

# 3. Edit API keys
nano .env
# Uncomment và set ít nhất 1 API key

# 4. Start
docker compose -f ../docker-compose.yml --env-file .env up -d openclaw-gateway

# 5. Mở browser
# http://localhost:18789 → paste token từ .env
```

## Các thay đổi so với upstream

### 1. `docker-compose.yml`

Thêm environment variables cho LLM providers:

```yaml
GAUSS_API_KEY: ${GAUSS_API_KEY:-}
ZAI_API_KEY: ${ZAI_API_KEY:-}
GEMINI_API_KEY: ${GEMINI_API_KEY:-}
OPENAI_API_KEY: ${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
OPENROUTER_API_KEY: ${OPENROUTER_API_KEY:-}
```

**Tại sao**: OpenClaw container chỉ nhận env vars được khai báo explicitly trong `docker-compose.yml`. Env var từ `.env` chỉ dùng cho variable substitution, không tự truyền vào container.

### 2. `deploy/openclaw.json`

Config chính, thay thế cho kết quả của wizard. Các điểm quan trọng:

```jsonc
{
  // Đánh lừa gateway rằng onboard đã chạy
  "wizard": {
    "lastRunCommand": "onboard",
    "lastRunMode": "local"
  },

  // Khai báo providers EXPLICIT - OpenClaw KHÔNG tự phát hiện
  // Google/OpenAI/Anthropic chỉ từ env var
  "models": {
    "mode": "merge",
    "providers": {
      "gauss": { "baseUrl": "...", "api": "openai-completions", ... },
      "zai": { ... },
      "google": { ... }
    }
  },

  // Model mặc định
  "agents": {
    "defaults": {
      "model": { "primary": "gauss/gauss-2.3" }
    }
  },

  // Bỏ device pairing - chỉ cần token là vào được Web UI
  "gateway": {
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
```

### 3. `deploy/models.json`

Model catalog thực tế cho agent runtime (khác với `openclaw.json`):

- `openclaw.json` → config source, gateway đọc để **generate** models.json
- `models.json` → runtime catalog, agent đọc để **biết** có model nào
- Cả 2 phải **sync** nhau. Nếu chỉ có 1 mà thiếu cái kia → model không hiện

**Quan trọng**: `apiKey` trong models.json có thể là:
- Env var name (string `"GEMINI_API_KEY"`) → gateway resolve từ env
- Literal key → dùng trực tiếp (không khuyến khích, dễ leak)

## Cơ chế model discovery của OpenClaw

```
openclaw.json (models.providers)
        │
        ▼
ensureOpenClawModelsJson()  ← chạy khi gateway start
        │
        ▼
models.json (agents/main/agent/)  ← model catalog thực
        │
        ▼
ModelRegistry (pi-coding-agent SDK)
        │
        ▼
models.list API  →  Web UI hiện danh sách
```

**Điểm then chốt**: Provider lớn (Google, OpenAI, Anthropic) **KHÔNG** tự phát hiện từ env var. Chỉ provider nhỏ (openrouter, nvidia, minimax...) mới auto-discover. Provider lớn cần khai báo explicit trong `openclaw.json → models.providers` với đầy đủ: `baseUrl`, `api`, `models[]`.

## Thêm LLM provider mới

### Provider OpenAI-compatible (Gauss, vLLM, Ollama...)

```jsonc
// Trong openclaw.json → models.providers:
"my-provider": {
  "baseUrl": "http://your-server:8000/v1",
  "apiKey": "MY_PROVIDER_API_KEY",    // tên env var
  "api": "openai-completions",
  "models": [
    {
      "id": "model-id",               // dùng trong API call
      "name": "Display Name",         // hiển thị trên Web UI
      "reasoning": false,
      "input": ["text"],
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
      "contextWindow": 32768,
      "maxTokens": 8192
    }
  ]
}
```

Rồi thêm tương tự vào `models.json` (thêm `"api": "openai-completions"` cho mỗi model).

### Checklist thêm provider

1. Thêm vào `openclaw.json → models.providers`
2. Thêm vào `models.json → providers`
3. Thêm env var vào `docker-compose.yml` environment
4. Set env var trong `.env`
5. Restart: `docker compose --env-file deploy/.env restart openclaw-gateway`

## Tích hợp Gauss Proxy

Gauss proxy (`gauss-openai-proxy`) chạy trên host, serve OpenAI-compatible API:

```
Browser → OpenClaw Gateway (Docker :18789)
                │
                ▼
         Agent Runtime
                │
                ▼ (OpenAI API format)
         Gauss Proxy (Host :8000)
                │
                ▼ (Company LLM format)
         Company LLM Server
```

Trong Docker, `host.docker.internal` trỏ về host machine:
- Proxy URL: `http://host.docker.internal:8000/v1`
- Trên Linux cần thêm `extra_hosts` trong docker-compose nếu không resolve được

## Troubleshooting

| Vấn đề | Nguyên nhân | Giải pháp |
|--------|------------|-----------|
| Model list trống | Thiếu `models.json` hoặc thiếu provider trong `openclaw.json` | Chạy lại `setup.sh` |
| Config invalid | `openclaw.json` thiếu `baseUrl` hoặc `models` array | Kiểm tra schema đầy đủ |
| Token mismatch | Browser cache token cũ | Clear site data, nhập lại |
| Permission denied | Container user (node) không có quyền | Chạy fix permissions trong `setup.sh` |
| Cannot connect to Gauss proxy | `host.docker.internal` không resolve | Thêm `extra_hosts: ["host.docker.internal:host-gateway"]` |
