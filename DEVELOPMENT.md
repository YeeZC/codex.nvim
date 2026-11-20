# Development

Install [mise](https://mise.jdx.dev/) and run `mise install` to provision Neovim and StyLua. Run `mise run format`, `mise run check`, and `mise run test` from the repository root.

The integration tests launch a raw terminal fixture to check process lifecycle, editor mappings, file paths, Visual selections, and bracketed-paste bytes. The window test also checks that a user autocmd can redirect focus and that a module reload can reuse a running Codex session. Run these tests against a local Snacks.nvim checkout with the following commands.

```sh
mise exec -- nvim -i NONE -l tests/integration/context.lua /path/to/snacks.nvim
mise exec -- nvim -i NONE -l tests/integration/windows.lua /path/to/snacks.nvim float
mise exec -- nvim -i NONE -l tests/integration/windows.lua /path/to/snacks.nvim right
```

For a real CLI check, start Neovim with the configuration in the README and open a file. Open Codex, wait for its prompt, and insert a file and a Visual selection. Check that both appear in the draft and that focus returns to the terminal. Toggle the terminal and verify that the draft is still there.

To check diff review with the real CLI, enable `terminal.diff_review` and run Codex in a scratch project. Ask it to create a file. Verify that the diff opens before the file appears and that `a` writes the file and clears the TUI approval. Ask for another file, use `q` and `:CodexDiff` to reopen the preview, then use `d` and check that the file was never created.
