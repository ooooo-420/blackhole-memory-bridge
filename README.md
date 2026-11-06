# Black Hole Memory Bridge

I use both Claude Code and Codex, and every time I switched tools I had to explain my progress again. This project saves both sides' conversations automatically and hands over the other side's new records on your next message. There is also a black hole desktop pet.

[Portfolio](https://ooooo-420.github.io/blackhole-memory-bridge/)

## How it works

1. When you send a message, a hook records your words and attaches the other side's new records.
2. When a turn ends, a hook saves your words and the AI's reply to that tool's own log.
3. A new conversation receives the latest 3 records and the branch list. A running conversation receives only the other side's new records.

Hooks handle the memory, so it does not depend on the black hole. The black hole shows status, pauses delivery, warns about broken connections, and plays the swallow animation when opening the other AI.

## Trade-offs

- **No detection of whether the other side is idle.** The first design pushed memory when the other side was idle, but that signal was unreliable and could interrupt a conversation. Handover now happens when you speak.
- **Delivery continues while the black hole is closed.** I considered save-only while closed, but forgetting to open it would break continuity. To pause, use the right-click menu.
- **Filter before delivery, keep every raw record.** Only obvious probe messages are skipped. Nothing is filtered by length, because a short "OK, add the safeguard" can be a decision.
- **Desktop icon positions are read without touching explorer's memory.** It uses the Windows shell interface, so it does not behave like process injection.

## Pitfalls

- Dragging the pet stuttered. I first blamed too many particles, but each frame took only about 2 ms. The real issue was a timer firing only about every 47 ms; fixing it raised the rate from about 21 to about 60 fps.
- PowerShell's `[Math]::Min(1, 0.047)` returns 0 because it picks the integer overload, which froze the transition animation.
- One project's `package.json` set `"type": "module"`. The hook failed outright while the conversation looked normal, which is why the connection warning exists.

## Current limits

- It has only run on Windows, in my own environment. There is no general installer.
- Records are stored locally in plain text, so do not paste passwords into these projects.
- New Codex hooks must be trusted manually in Codex before they run.
- The swallow animation when opening Claude, and windows that start maximized, are untested.
- Some code comments and the pet's interface are still in Chinese.

## Files

| Path | Purpose |
|---|---|
| `index.html` | Portfolio page |
| `bridge/bridge.js` | Saving, delivery and health checks |
| `bridge/package.json` | Keeps the project's ES module setting from breaking the bridge |
| `config/claude-settings.json` | Goes to the project's `.claude/settings.json` |
| `config/codex-hooks.json` | Goes to the project's `.codex/hooks.json` |
| `pet/黑洞桌寵.ps1` | Desktop black hole |
| `pet/projects.example.json` | Projects the black hole watches; copy to `projects.json` and fill in the paths |
| `docs/AGENTS.example.md` | Branch and memory rules template for the AI |

Copy `bridge/` into your project as `.memory-bridge/`, then put the two config files in place.

I set the requirements and rules, and built this together with Claude Code and Codex.
