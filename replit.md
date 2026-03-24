# BashClaw

A pure-shell AI agent runtime and framework. Lightweight, universal, and highly portable — built with Bash 3.2+ and requires only `jq`, `curl`, and `socat`.

## Architecture

- **Runtime**: Bash shell scripts (no Node.js/Python required for core)
- **HTTP Server**: `socat`-based pure-Bash HTTP gateway
- **UI**: Static vanilla JS/HTML/CSS dashboard (`ui/`)
- **Entry point**: `./bashclaw` (main CLI)
- **Config**: `~/.bashclaw/bashclaw.json`
- **State dir**: `~/.bashclaw/`

## Project Structure

- `bashclaw` — Main CLI executable
- `lib/` — Core library modules (agent, config, session, tools, etc.)
- `gateway/http_handler.sh` — HTTP request handler (spawned per connection by socat)
- `ui/` — Web dashboard (index.html, app.js, style.css)
- `channels/` — Messaging integrations (Telegram, Discord, Slack, Feishu)
- `mcp/` — Model Context Protocol server
- `python_tools/` — Optional Python code analysis tools
- `tests/` — Shell-based test suite

## Running

The gateway starts on port 5000 via socat:

```bash
./bashclaw gateway -p 5000
```

Dashboard available at: `http://localhost:5000`

## Configuration

Config file: `~/.bashclaw/bashclaw.json`

Set API keys in `~/.bashclaw/.env`:
```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

## System Dependencies

- `socat` — HTTP server (installed via Nix)
- `jq` — JSON processing (available by default)
- `curl` — API calls (available by default)

## Workflow

- **Start application**: `bash /home/runner/workspace/bashclaw gateway -p 5000`
- Port: 5000 (webview)
