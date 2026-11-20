-- Run in real Neovim so the window and buffer events go through the normal API.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local snacks, position = arg[1], arg[2] or "float"
if snacks then
  vim.opt.runtimepath:append(snacks)
end

local api = vim.api
local codex = require("codex")
local terminal = require("codex.terminal")
local options = {
  terminal_cmd = "sh -c 'stty raw -echo && printf READY && cat'",
  default_keymaps = false,
  terminal = {
    provider = snacks and "snacks" or "native",
    snacks_win_opts = { position = position, fixbuf = false },
    auto_insert = false,
    show_native_term_exit_tip = false,
  },
}
local alternate = api.nvim_get_current_win()
vim.cmd.new()
local editor = api.nvim_get_current_win()
local original = api.nvim_get_current_buf()
api.nvim_buf_set_lines(original, 0, -1, false, { "unsaved text" })

local redirected = false
if not snacks or position ~= "float" then
  api.nvim_create_autocmd("BufLeave", {
    buffer = original,
    once = true,
    callback = function()
      redirected = true
      api.nvim_set_current_win(alternate)
    end,
  })
end

codex.setup(options)
vim.cmd.CodexOpen()
local buf = assert(terminal.get_active_terminal_bufnr(), "Missing terminal session")
local win = api.nvim_get_current_win()
assert(api.nvim_win_get_buf(win) == buf and win ~= alternate and win ~= editor)
assert(api.nvim_win_get_buf(editor) == original and vim.bo[original].modified)
assert(snacks and position == "float" or redirected, "Expected the BufLeave handler to redirect")
assert(vim.wait(3000, function()
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("READY", 1, true) ~= nil
end))
local channel = vim.bo[buf].channel

vim.cmd.Codex()
assert(api.nvim_get_current_win() == editor)
if snacks and position == "float" then
  assert(api.nvim_win_get_config(win).hide)
else
  assert(not api.nvim_win_is_valid(win))
end

-- The running terminal and its draft must survive a Lua module reload.
package.loaded["codex"] = nil
package.loaded["codex.terminal"] = nil
package.loaded["codex.terminal.session"] = nil
require("codex").setup(options)
terminal = require("codex.terminal")
vim.cmd.CodexFocus()
assert(api.nvim_get_current_buf() == buf)
assert(vim.bo[buf].channel == channel)
if snacks and position == "float" then
  assert(api.nvim_get_current_win() == win and not api.nvim_win_get_config(win).hide)
end

-- A user may move an ordinary unsaved buffer into the former terminal window.
-- Closing Codex must stop the job while keeping that window and its contents.
win = api.nvim_get_current_win()
local replacement = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(replacement, 0, -1, false, { "keep this file" })
api.nvim_win_set_buf(win, replacement)
api.nvim_set_current_win(editor)
vim.cmd.CodexClose()
assert(terminal.get_active_terminal_bufnr() == nil)
assert(api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == replacement)
assert(vim.bo[replacement].modified and vim.bo[original].modified)
assert(api.nvim_buf_get_lines(replacement, 0, 1, false)[1] == "keep this file")
print("PASS Codex window ownership and session reload (" .. (snacks and ("Snacks " .. position) or "native") .. ")")
