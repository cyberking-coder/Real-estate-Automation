# Agent Reach

[Agent Reach](https://github.com/Panniantong/Agent-Reach) gives the AI agent working on this
repo the ability to read the open internet - web pages, YouTube transcripts, RSS, GitHub, and
(once configured) Twitter/X, Reddit, LinkedIn and others.

It is **agent tooling, not a project dependency**. No n8n workflow imports it, nothing in
`workflows/` calls it, and it installs into `$HOME`, never into this repo. Think of it the same
way as having `gh` on your PATH.

## Install

```bash
bash scripts/install-agent-reach.sh
```

The script is idempotent, so re-run it whenever you rebuild the machine or a container.

## What it installs

| Piece | Where | Why |
|---|---|---|
| `agent-reach` CLI | `~/.local/bin` (via `uv`/`pipx`, else a venv) | the installer, health checker and router |
| `yt-dlp` | `~/.local/bin` | YouTube metadata and subtitles |
| `mcporter` + Exa entry | `npm -g`, `~/.mcporter/mcporter.json` | whole-web semantic search over MCP |
| `SKILL.md` | `~/.claude/skills/agent-reach/` | teaches the agent which command serves which platform |
| yt-dlp `--js-runtimes node` | `~/.config/yt-dlp/config` | YouTube's player challenges need a JS runtime |

Check the result at any time:

```bash
agent-reach doctor            # per-channel status
agent-reach doctor --json     # same, with the backend actually serving each platform
```

## Channels that are on by default

Web (via Jina Reader), YouTube, RSS, GitHub, V2EX, and Exa search. They need no credentials.

## Channels that need you

Twitter/X, Reddit, Facebook, Instagram, Xiaohongshu, LinkedIn, Xueqiu and Xiaoyuzhou all need a
login session or an API key, so they are **not** installed by default. Ask the agent for the one
you want - "set up Twitter for me" - and it will walk you through the credential step, or run:

```bash
agent-reach install --env=auto --system --channels=twitter
```

Use a throwaway account for anything cookie-based. A cookie is a full login, and platforms do ban
accounts that call them from scripts. Credentials live in `~/.agent-reach/config.yaml`, mode 600,
and are never sent anywhere.

## Running inside Claude Code on the web

A cloud session's outbound traffic goes through the agent proxy, and the default network policy
denies everything except the package registries. Agent Reach installs cleanly there, but every
channel that has to reach a site - `r.jina.ai`, `youtube.com`, `v2ex.com` - fails its CONNECT with
a 403 until the environment's network policy allows those hosts. Exa additionally needs a one-time
browser OAuth approval, which a headless container cannot complete. On a normal laptop neither
applies. See https://code.claude.com/docs/en/claude-code-on-the-web for the network policy options.

## Removing it

```bash
agent-reach uninstall     # config, tokens, skill files, MCP entries
uv tool uninstall agent-reach
```
