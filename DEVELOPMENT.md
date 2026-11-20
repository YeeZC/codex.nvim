# Development

Install [mise](https://mise.jdx.dev/) and run `mise install` to provision Neovim and StyLua. Run `mise run format`, `mise run check`, and `mise run test` from the repository root.

The context tests run for Codex, agy, and Cursor adapters, checking permission flags, resume arguments, command aliases, and rejection of agent changes during an active session. The integration tests launch a raw terminal fixture to check process lifecycle, editor mappings, file paths, Visual selections, and bracketed-paste bytes. The window test also checks that a user autocmd can redirect focus and that a module reload can reuse a running Codex session. Run these tests against a local Snacks.nvim checkout with the following commands.

```sh
mise exec -- nvim -i NONE -l tests/integration/context.lua /path/to/snacks.nvim
mise exec -- nvim -i NONE -l tests/integration/windows.lua /path/to/snacks.nvim float
mise exec -- nvim -i NONE -l tests/integration/windows.lua /path/to/snacks.nvim right
```

For a real CLI check, start Neovim with the configuration in the README and open a file. Open Codex, wait for its prompt, and insert a file and a Visual selection. Check that both appear in the draft and that focus returns to the terminal. Toggle the terminal and verify that the draft is still there.

For agy and Cursor, repeat the real CLI draft check with `agent = "agy"` and `agent = "cursor"`. Verify multiline context stays in the composer until Enter is pressed. Their native Shift-Enter handling is used. Set `CODEX_TEST_AGENT=agy` or `CODEX_TEST_AGENT=cursor` when running the context test directly, including the Snacks checks above.

## Project website

The GitHub Pages site is a static page in `docs/`. Preview it with `python3 -m http.server 8000 --directory docs` and open `http://localhost:8000`. Changes to `docs/` on `main` deploy automatically through `.github/workflows/pages.yml`; the workflow can also be started manually. Keep the installation example and agent commands aligned with the README.
