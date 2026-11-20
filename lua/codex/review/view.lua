local M = {}
local api = vim.api

local function append_change(lines, change)
  local path = vim.fn.strtrans(change.path)
  local kind = change.kind.type
  local target = type(change.kind.move_path) == "string" and vim.fn.strtrans(change.kind.move_path) or path
  lines[#lines + 1] = "--- " .. (kind == "add" and "/dev/null" or path)
  lines[#lines + 1] = "+++ " .. (kind == "delete" and "/dev/null" or target)
  local body = vim.split(change.diff:gsub("\n$", ""), "\n", { plain = true })
  if kind == "update" then
    vim.list_extend(lines, body)
  elseif change.diff ~= "" then
    local adding = kind == "add"
    local span = "1," .. #body
    lines[#lines + 1] = ("@@ -%s +%s @@"):format(adding and "0,0" or span, adding and span or "0,0")
    for _, line in ipairs(body) do
      lines[#lines + 1] = (adding and "+" or "-") .. line
    end
  end
  lines[#lines + 1] = ""
end

local function event(pattern, review, win, buf, reason)
  pcall(api.nvim_exec_autocmds, "User", {
    pattern = pattern,
    modeline = false,
    data = {
      buffer = buf,
      window = win,
      thread_id = review.thread,
      turn_id = review.turn,
      item_id = review.item,
      request_id = review.id,
      reason = reason,
    },
  })
end

function M.open(review)
  if review.win and api.nvim_win_is_valid(review.win) and api.nvim_win_get_buf(review.win) == review.buf then
    api.nvim_set_current_win(review.win)
    return
  end
  local lines = {}
  for _, change in ipairs(review.changes) do
    append_change(lines, change)
  end
  local buf = api.nvim_create_buf(false, true)
  local ok, win = pcall(function()
    vim.bo[buf].bufhidden = "wipe"
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "diff"
    vim.bo[buf].modifiable = false
    vim.keymap.set("n", "a", "<Cmd>CodexDiffAccept<CR>", { buffer = buf, desc = "Accept Codex changes" })
    vim.keymap.set("n", "d", "<Cmd>CodexDiffDeny<CR>", { buffer = buf, desc = "Reject Codex changes" })
    vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, desc = "Hide Codex diff" })
    local width = math.max(1, math.floor(vim.o.columns * 0.86))
    local height = math.max(1, math.floor((vim.o.lines - vim.o.cmdheight) * 0.72))
    return api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
      width = width,
      height = height,
      zindex = 100,
      border = "rounded",
      title = " Codex file changes ",
      footer = width >= 33 and " a Accept   d Reject   q Hide " or nil,
      footer_pos = width >= 33 and "center" or nil,
    })
  end)
  if not ok or not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then
    if api.nvim_buf_is_valid(buf) then
      pcall(api.nvim_buf_delete, buf, {})
    end
    error(ok and "The review window changed while opening." or win, 0)
  end

  review.win, review.buf = win, buf
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      vim.schedule(function()
        if review.win == win then
          review.win, review.buf = nil, nil
          event("CodexDiffClosed", review, win, buf, "hidden")
        end
      end)
    end,
  })
  event("CodexDiffOpened", review, win, buf)
end

function M.close(review, reason)
  local win, buf = review.win, review.buf
  if not win then
    return
  end
  review.win, review.buf = nil, nil
  if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
    pcall(api.nvim_win_close, win, false)
  end
  if buf and api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, {})
  end
  event("CodexDiffClosed", review, win, buf, reason)
end

return M
