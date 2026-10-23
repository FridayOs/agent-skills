# Agent Skills

Reusable skills for AI agents, maintained by FridayOs. Each skill is a folder
with a `SKILL.md` (the instructions an agent loads), plus optional `scripts/`
and `references/`. The format is the open Agent Skills format, so the same
skill works in **Paperclip**, **Claude Code**, **Codex** and other compatible
clients.

## Skills

| Skill | What it does | Needs |
|---|---|---|
| [`youtube-data-api-skill`](skills/youtube-data-api-skill/SKILL.md) | Read public YouTube data: search, video and channel stats, uploads, playlists, comments, trending | `YOUTUBE_API_KEY`, `bash`, `curl`, `jq` |

## Install

### Paperclip

1. **Skills → + New → Import from GitHub** (or **Import from path or URL**) →
   `https://github.com/FridayOs/agent-skills`
2. Click **Find skills**, then select the skills to import. They are added to
   the company library, pinned to the current commit. Use **Refresh** later to
   pull updates.
3. Open the agent's **Skills** tab and enable the skill.
4. If the skill needs a key, create a company secret and bind it to the agent
   as `env.<NAME>`, for example `env.YOUTUBE_API_KEY`. Never paste keys into
   issues or comments.

### skills CLI (Claude Code, Codex, …)

```bash
npx skills add https://github.com/FridayOs/agent-skills --skill youtube-data-api-skill
```

### Manual

Copy a skill folder into your agent's skills directory, then export the env
vars it needs:

```bash
git clone https://github.com/FridayOs/agent-skills
cp -r agent-skills/skills/youtube-data-api-skill ~/.claude/skills/
export YOUTUBE_API_KEY=…
```

## Layout

```
skills/
└── <skill-name>/
    ├── SKILL.md        # frontmatter (name, description) + instructions
    ├── scripts/        # helpers the instructions call (executable)
    └── references/     # longer docs, loaded only when needed
```

## Adding a skill

- **Folder and name:** the folder name equals `name:` in the frontmatter, in
  lowercase-kebab-case.
- **`description`:** write it as *Use when… Don't use when…*. Agents only see
  the name and description until they decide to load the skill.
- **`SKILL.md`:** keep it short and task-focused. Move long tables and
  examples to `references/`.
- **Secrets:** read them from env vars only. Never commit a key, never put one
  in a URL or a log, and document the variable in the skill's Setup section.
  Inside Paperclip, a helper script can also read the agent's granted secret
  from `$PAPERCLIP_API_URL/api/agents/me/secrets/<name>/value`.
- **Risky actions:** prefer read-only operations. Skills that publish, spend
  or delete must say when to stop and ask a person.
- **Scripts:** must be executable (`chmod +x`), fail with a clear message and
  exit code, and need only common tools (`bash`, `curl`, `jq`).
- **Testing:** test against a mock or a sandbox before pushing. Update the
  table above.

Product-specific skills live in their own repos, for example
[`FridayOs/lifestudio-skills`](https://github.com/FridayOs/lifestudio-skills).
