local M = {}
local api = vim.api

function M.map_terminal_suspend(buf)
  local exists = vim.iter(api.nvim_buf_get_keymap(buf, "t")):any(function(key)
    return key.lhsraw == "\26" or key.lhs == "<C-Z>"
  end)
  if not exists then
    vim.keymap.set("t", "<C-z>", "<Cmd>suspend<CR>", { buffer = buf, desc = "Suspend Neovim" })
  end
end

local function place(win, buf, ignored, keep)
  local original = vim.o.eventignore
  local events = vim.split(original, ",", { plain = true, trimempty = true })
  events = vim.tbl_filter(function(event)
    return not (event:sub(1, 1) == "-" and ignored[event:sub(2):lower()])
  end, events)
  for event in pairs(ignored) do
    events[#events + 1] = event
  end
  vim.o.eventignore = table.concat(events, ",")
  local old_policy = keep and vim.bo[keep].bufhidden
  local ok, result = pcall(function()
    if keep then
      vim.bo[keep].bufhidden = "hide"
    end
    api.nvim_win_set_buf(win, buf)
  end)
  if keep and api.nvim_buf_is_valid(keep) then
    vim.bo[keep].bufhidden = old_policy
  end
  vim.o.eventignore = original
  if not ok then
    error(result, 0)
  end
end

-- Dispatch BufLeave before the switch acquires Neovim's internal buffer lock.
-- A handler may navigate or close the split, so re-check it before placing the buffer.
function M.win_set_buf_in_split(win, buf, opts)
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(buf) then
    return false
  end
  if api.nvim_win_get_buf(win) == buf then
    return true
  end
  local ignored = { optionset = true }
  if opts and opts.ignore_bufenter then
    ignored.bufenter = true
  end
  api.nvim_win_call(win, function()
    local from = api.nvim_win_get_buf(win)
    if not vim.wo[win].winfixbuf and vim.fn.getcmdwintype() == "" then
      api.nvim_exec_autocmds("BufLeave", { buffer = from, modeline = false })
      ignored.bufleave = true
    end
    if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(buf) then
      return
    end
    local replaced = api.nvim_win_get_buf(win)
    local keep = ignored.bufleave and (replaced ~= from or vim.bo[replaced].modified)
    api.nvim_win_call(win, function()
      place(win, buf, ignored, keep and replaced or nil)
    end)
  end)
  return api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf
end

function M.expand_tilde(word)
  local home = vim.env.HOME
  if home and home ~= "" and (word == "~" or word:sub(1, 2) == "~/") then
    return home .. word:sub(2)
  end
  return word
end

-- Read shell-style words for jobstart's argv form. The shell never interprets the result.
function M.parse_command(command)
  local arguments = {}
  local quote, escaped
  local double_escapes = { ['"'] = true, ["\\"] = true, ["$"] = true, ["`"] = true }
  local word = {}
  local started = false
  local function finish_word()
    if started then
      arguments[#arguments + 1] = M.expand_tilde(table.concat(word))
      word, started = {}, false
    end
  end
  for char in command:gmatch(".") do
    if escaped then
      if quote == '"' and not double_escapes[char] then
        word[#word + 1] = "\\"
      end
      word[#word + 1], escaped = char, false
    elseif char == "\\" and quote ~= "'" then
      started, escaped = true, true
    elseif quote then
      if char == quote then
        quote = nil
      else
        word[#word + 1] = char
      end
    elseif char == '"' or char == "'" then
      started, quote = true, char
    elseif char == " " or char == "\t" then
      finish_word()
    else
      started = true
      word[#word + 1] = char
    end
  end
  if escaped then
    word[#word + 1] = "\\"
  end
  finish_word()
  return arguments
end

local selections = { v = "v", s = "v", V = "V", S = "V", ["\22"] = "\22", ["\19"] = "\22" }

function M.selection_type(mode)
  if mode and (#mode == 1 or (#mode == 2 and mode:sub(2) == "s")) then
    return selections[mode:sub(1, 1)]
  end
end

-- ASCII and legal Unicode scalars may be passed through unchanged. Consume the
-- valid prefix of an interrupted sequence in one replacement.
function M.valid_utf8(value)
  local parts, start, cursor = {}, 1, 1
  while cursor <= #value do
    local first = value:byte(cursor)
    if first < 128 then
      cursor = cursor + 1
    else
      local need = (first >= 194 and first <= 223 and 1)
        or (first >= 224 and first <= 239 and 2)
        or (first >= 240 and first <= 244 and 3)
        or 0
      local finish = cursor
      for offset = 1, need do
        local byte = value:byte(cursor + offset)
        local lo, hi = 128, 191
        if offset == 1 then
          lo = (first == 224 and 160) or (first == 240 and 144) or lo
          hi = (first == 237 and 159) or (first == 244 and 143) or hi
        end
        if not byte or byte < lo or byte > hi then
          break
        end
        finish = finish + 1
      end
      if need == 0 or finish - cursor ~= need then
        parts[#parts + 1] = value:sub(start, cursor - 1)
        parts[#parts + 1] = "�"
        start = finish + 1
      end
      cursor = finish + 1
    end
  end
  parts[#parts + 1] = value:sub(start)
  return table.concat(parts)
end

return M
