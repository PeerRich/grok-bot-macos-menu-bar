# Grok Bot menu bar

A small macOS menu bar app that shows what your [Grok Bot](https://x.ai) bots are doing right now.

- **Menu bar:** the avatar and current task of the active bot ("Handling it", "Searching the web", …), plus `+N` when more bots are active.
- **Menu:** active bots on top, then a divider, then the rest of your bots with avatar and last message. Hidden bots sit in a submenu. Clicking a bot opens it in Grok Bot.

Unofficial. Not affiliated with xAI. It depends on Grok Bot internals (tested with 0.79.3) and can break when Grok Bot updates.

## Build and run

Needs macOS 14.4+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
./build.sh --run
```

This builds `build/Grok Menu.app` and starts it.

## How it works

| Data | Source |
| --- | --- |
| Bot list, names, last message | Grok Bot's roster file in `~/Library/Application Support/Grok Bot/sand-client-persistence` (read-only) |
| Photo avatars | `~/Library/Application Support/Grok Bot/roster-avatars` |
| Shape avatars | Drawn locally from the bot's shape and colour |
| Live status (running, current task) | The running Grok Bot window, over the Chromium DevTools protocol |

Grok Bot keeps live status only in memory, so reading it needs Grok Bot started with
`--remote-debugging-port=9347`. Use **Enable Live Status (Relaunch Grok Bot)…** in the menu, or
start Grok Bot from the menu when it is not running. Started from the Dock, Grok Bot has no port
and the menu shows the bot list without live status.

**Security note:** while that port is open, any program running on your Mac can inspect and
control the Grok Bot window. The port listens on 127.0.0.1 only. Quit Grok Bot and start it
normally to close it.

## Credits

Avatar silhouettes and eyes are ported from [bloub](https://github.com/jeremy-prt/bloub) by
Jérémy Perret (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
