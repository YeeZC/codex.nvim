# Repository Guidelines

- `lua/codex/` contains the plugin. `plugin/codex.lua` loads optional automatic setup and `dev-config.lua` provides a lazy.nvim spec for this checkout.
- Use two-space indentation, double quotes, and the repository's StyLua configuration. Keep module-local functions local. Document exported options and commands in `README.md`.
- Before changing terminal window handling, reproduce the affected sequence in real Neovim. A split command can run user autocmds, so the current window after a split does not establish ownership. Close only plugin-owned windows, and use non-forced window closes to protect modified buffers.
- Keep `utils.win_set_buf_in_split` for terminal placement. User `BufLeave` autocmds can redirect a direct native buffer swap. The helper lets Neovim handle `BufWinLeave`, `BufHidden`, and `BufUnload`, and preserves buffers when a user autocmd changes the split during preparation.
- Send context as bracketed paste. Keep its contents in the draft until the user submits it. Use argv lists when spawning the CLI so quoting, spaces, and shell metacharacters survive.
- Run `mise run check` and `mise run test` before submitting changes. See `DEVELOPMENT.md` for the Snacks float check and a manual TUI check.
