vim.opt.runtimepath:prepend(vim.fn.getcwd())

local api = vim.api
local receive, disconnect
local sent, opened, closed = {}, {}, {}
local fixture = vim.fn.tempname()
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = app-server ]; then',
  '  : > "${3#unix://}"',
  "  exec sleep 60",
  "fi",
  "exec cat",
}, fixture)
assert(vim.uv.fs_chmod(fixture, tonumber("700", 8)))

package.loaded["codex.review.socket"] = {
  listen = function(_, _, on_message, on_close)
    receive, disconnect = on_message, on_close
    return {
      send = function(message)
        sent[#sent + 1] = message
        return true
      end,
      close = function() end,
    }
  end,
}

local function propose(id, changes)
  local item = { id = "patch-" .. id, type = "fileChange", changes = changes }
  receive({ method = "item/started", params = { threadId = "thread", turnId = "turn", item = item } })
  receive({
    method = "item/fileChange/requestApproval",
    id = id,
    params = { threadId = "thread", turnId = "turn", itemId = item.id },
  })
end

local function resolved(id)
  receive({ method = "serverRequest/resolved", params = { threadId = "thread", requestId = id } })
end

local ok, error_message = xpcall(function()
  require("codex").setup({
    terminal_cmd = fixture,
    terminal = { provider = "native", auto_insert = false, diff_review = true, show_native_term_exit_tip = false },
    log_level = "error",
  })
  api.nvim_create_autocmd("User", {
    pattern = "CodexDiffOpened",
    callback = function(event)
      opened[#opened + 1] = event.data
    end,
  })
  api.nvim_create_autocmd("User", {
    pattern = "CodexDiffClosed",
    callback = function(event)
      closed[#closed + 1] = event.data
    end,
  })

  local editor = api.nvim_get_current_buf()
  local path = vim.fn.tempname()
  api.nvim_buf_set_name(editor, path)
  api.nvim_buf_set_lines(editor, 0, -1, false, { "unsaved edit" })
  vim.cmd.CodexOpen()
  local terminal = api.nvim_get_current_buf()
  assert(vim.bo[terminal].buftype == "terminal")

  receive({ method = "item/commandExecution/requestApproval", id = 15, params = {} })
  assert(#opened == 0)
  propose(0, {
    { path = path, kind = { type = "update" }, diff = "@@ -1 +1 @@\n-before\n+after\n" },
    { path = path .. ".new", kind = { type = "add" }, diff = "new text\n" },
    { path = path .. ".old", kind = { type = "delete" }, diff = "old text\n" },
  })

  local preview = api.nvim_get_current_buf()
  local contents = table.concat(api.nvim_buf_get_lines(preview, 0, -1, false), "\n")
  assert(vim.bo[preview].filetype == "diff" and not vim.bo[preview].modifiable)
  for _, line in ipairs({ "-before", "+after", "+new text", "-old text" }) do
    assert(contents:find(line, 1, true))
  end
  assert(opened[1].request_id == 0 and opened[1].buffer == preview)
  vim.cmd.CodexDiffAccept()
  assert(#sent == 0 and vim.bo[editor].modified, "An unsaved edit must not be overwritten")

  vim.cmd.close()
  assert(vim.wait(1000, function()
    return #closed == 1
  end))
  assert(closed[1].reason == "hidden" and closed[1].buffer == preview and #sent == 0)
  vim.cmd.CodexDiff()
  local window = api.nvim_get_current_win()
  assert(#opened == 2 and vim.bo.filetype == "diff")
  vim.bo[editor].modified = false
  vim.cmd.CodexDiffAccept()
  vim.cmd.CodexDiffAccept()
  assert(vim.deep_equal(sent, { { id = 0, result = { decision = "accept" } } }))
  assert(api.nvim_win_is_valid(window), "Keep the review open until the server resolves the request")
  resolved(0)
  assert(not api.nvim_win_is_valid(window) and closed[2].reason == "resolved")

  local change = { path = path, kind = { type = "add" }, diff = "another proposal\n" }
  propose("reject", { change })
  vim.cmd.CodexDiffDeny()
  assert(vim.deep_equal(sent[2], { id = "reject", result = { decision = "decline" } }))
  resolved("reject")
  propose("terminal", { change })
  receive({ id = "terminal", result = { decision = "accept" } }, true)
  vim.cmd.CodexDiffDeny()
  assert(#sent == 2, "A decision from the TUI must take precedence")
  resolved("terminal")
  assert(vim.bo.filetype ~= "diff")

  propose("disconnect", { change })
  disconnect("fixture disconnected")
  assert(vim.bo.filetype ~= "diff" and closed[#closed].reason == "disconnected")
  assert(api.nvim_buf_is_valid(editor) and api.nvim_buf_is_valid(terminal))
end, debug.traceback)

vim.cmd.CodexClose()
vim.fn.delete(fixture)
assert(ok, error_message)
print("PASS Codex file review, decisions, and cleanup")
