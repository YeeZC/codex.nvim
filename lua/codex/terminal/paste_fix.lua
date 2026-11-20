local M = {}
local active, previous
local paste

local function replay(chunks)
  local win = chunks.window
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= chunks.buffer then
    win = vim.fn.bufwinid(chunks.buffer)
  end
  if win == -1 then
    return false
  end
  return vim.api.nvim_win_call(win, function()
    return previous(vim.split(table.concat(chunks), "\n", { plain = true }), -1)
  end)
end

local function wrapped(lines, phase)
  if phase == 1 then
    local buf = vim.api.nvim_get_current_buf()
    local terminal = require("codex.terminal")
    if vim.bo[buf].buftype == "terminal" and terminal.get_active_terminal_bufnr() == buf then
      paste = { window = vim.api.nvim_get_current_win(), buffer = buf }
    else
      paste = nil
    end
  end
  if not active or not paste or phase == -1 then
    return previous(lines, phase)
  end

  paste[#paste + 1] = table.concat(lines, "\n")
  if phase == 3 then
    local chunks = paste
    paste = nil
    return replay(chunks)
  end
  return true
end

function M.apply(setting)
  paste = nil
  local version = vim.version()
  local affected = vim.version.lt(version, { 0, 12, 2 })
    or version.major == 0 and version.minor == 12 and version.patch == 2 and version.prerelease ~= nil
  active = setting == true or (setting ~= false and affected)
  if active and not previous then
    previous, vim.paste = vim.paste, wrapped
  end
end

return M
