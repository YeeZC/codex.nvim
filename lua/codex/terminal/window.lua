local M = {}
local api = vim.api
local utils = require("codex.utils")
local owner = "codex_terminal_buffer"
local backdrop_var = "codex_terminal_backdrop"

function M.attached(win, buf)
  return win and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf
end

function M.find(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.w[win][owner] == buf then
      return win
    end
  end
end

local function split(buf, position, parent, size)
  local source = api.nvim_win_get_buf(parent or 0)
  local vertical = position == "left" or position == "right"
  local geometry = { split = position, win = parent or -1 }
  geometry[vertical and "width" or "height"] = size
  local win = api.nvim_open_win(source, false, geometry)
  if not M.attached(win, source) then
    return
  end
  local ok, placed = pcall(utils.win_set_buf_in_split, win, buf)
  if M.attached(win, buf) then
    vim.w[win][owner] = buf
  elseif M.attached(win, source) then
    pcall(api.nvim_win_close, win, false)
  end
  if not ok then
    error(placed, 0)
  end
  return placed and win or nil
end

local function return_focus(state, win)
  if api.nvim_get_current_win() ~= win then
    return
  end
  local tab = api.nvim_win_get_tabpage(win)
  local last = state.return_to
  if last and api.nvim_win_is_valid(last) and api.nvim_win_get_tabpage(last) == tab then
    api.nvim_set_current_win(last)
    return
  end
  for _, other in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if other ~= win and api.nvim_win_get_config(other).relative == "" then
      api.nvim_set_current_win(other)
      return
    end
  end
end

local function set_hidden(win, hidden)
  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_set_config(win, { hide = hidden })
  end
end

local function backdrop(state)
  local view = state.view
  if view and view.backdrop then
    return view.backdrop.win
  end
  if state.win and api.nvim_win_is_valid(state.win) then
    return vim.w[state.win][backdrop_var]
  end
end

function M.visible(state)
  return M.attached(state.win, state.buf) and not api.nvim_win_get_config(state.win).hide
end

function M.dismiss(state, keep_window)
  local win, view = state.win, state.view
  if not M.attached(win, state.buf) then
    if view then
      view.win = nil
      view:close({ buf = false })
    end
    state.win = nil
    return
  end

  return_focus(state, win)
  if not M.attached(win, state.buf) then
    return
  end
  if state.replaced then
    local previous = state.replaced
    if not api.nvim_buf_is_valid(previous) then
      previous = api.nvim_create_buf(true, false)
    end
    if not utils.win_set_buf_in_split(win, previous) then
      return
    end
    if api.nvim_win_is_valid(win) then
      vim.w[win][owner] = nil
    end
    state.replaced = nil
  elseif keep_window and api.nvim_win_get_config(win).relative ~= "" then
    set_hidden(win, true)
    set_hidden(backdrop(state), true)
    return
  else
    local shade = backdrop(state)
    if vim.w[win][owner] ~= state.buf or not pcall(api.nvim_win_close, win, false) then
      return
    end
    if not view and shade and api.nvim_win_is_valid(shade) then
      pcall(api.nvim_win_close, shade, false)
    end
  end

  if view then
    view.win = nil
    view:close({ buf = false })
  end
  state.win = nil
end

local function attach_snacks(state)
  local snacks = require("snacks")
  -- Load the terminal style while keeping PTY ownership in the session.
  local _ = snacks.terminal
  local user = state.options.snacks_win_opts
  local opts = snacks.win.resolve(
    "terminal",
    {
      position = state.options.split_side,
      width = state.options.split_width_percentage,
      height = 0,
      relative = "editor",
      bo = { filetype = "codex" },
      keys = {
        codex_new_line = {
          "<S-CR>",
          function()
            api.nvim_chan_send(vim.bo[state.buf].channel, "\\")
            vim.defer_fn(function()
              if api.nvim_buf_is_valid(state.buf) and state.job then
                pcall(api.nvim_chan_send, state.job, "\r")
              end
            end, 10)
          end,
          mode = "t",
          desc = "New line",
        },
      },
    },
    user,
    {
      buf = state.buf,
      show = false,
      enter = false,
    }
  )
  opts.wo = opts.wo or {}
  opts.wo.winbar = opts.wo.winbar or (opts.position == "float" and "" or "%{get(b:, 'term_title', '')}")
  local view = snacks.win.new(opts)
  view.cmd = state.argv
  local open_window = view.open_win
  local show_window = view.show
  function view:open_win()
    local position = self.opts.position
    if position == "float" then
      open_window(self)
    elseif position == "current" then
      self.win = api.nvim_get_current_win()
      state.replaced = api.nvim_get_current_buf()
      assert(utils.win_set_buf_in_split(self.win, state.buf), "Codex window was changed while opening")
    else
      local vertical = position == "left" or position == "right"
      local parent = self.opts.relative == "win" and self.opts.win or nil
      if parent and not api.nvim_win_is_valid(parent) then
        parent = nil
      end
      local size = self:win_opts()
      if not parent and self.opts.stack then
        for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
          local anchor = vim.w[candidate].snacks_win
          if anchor and anchor.stack and anchor.position == position and anchor.relative == self.opts.relative then
            parent = candidate
            position = vertical and "bottom" or "right"
            size = {
              width = math.max(1, math.floor(api.nvim_win_get_width(candidate) / 2)),
              height = math.max(1, math.floor(api.nvim_win_get_height(candidate) / 2)),
            }
            vertical = not vertical
            break
          end
        end
      end
      self.win = assert(
        split(state.buf, position, parent, vertical and size.width or size.height),
        "Codex split was changed while opening"
      )
    end
    state.win = self.win
    if M.attached(self.win, state.buf) then
      vim.w[self.win][owner] = state.buf
      vim.w[self.win].snacks_win = {
        id = self.id,
        position = self.opts.position,
        relative = self.opts.relative,
        stack = self.opts.stack,
      }
    end
  end
  function view:hide()
    M.dismiss(state, true)
    return self
  end
  function view:show()
    if M.attached(state.win, state.buf) then
      set_hidden(state.win, false)
      set_hidden(backdrop(state), false)
      return self
    end
    show_window(self)
    if M.attached(state.win, state.buf) then
      vim.w[state.win][backdrop_var] = self.backdrop and self.backdrop.win or nil
    end
    return self
  end
  function view:toggle()
    if M.visible(state) then
      return self:hide()
    end
    return self:show()
  end
  state.view = view
  view:show()
end

function M.show(state)
  local from = api.nvim_get_current_win()
  if not M.attached(from, state.buf) then
    state.return_to = from
  end
  local existing = M.find(state.buf)
  if existing then
    state.win = existing
    if api.nvim_win_get_config(existing).relative ~= "" then
      set_hidden(existing, false)
      set_hidden(backdrop(state), false)
    end
  elseif state.frontend == "snacks" then
    if state.view then
      M.dismiss(state, false)
      state.view:show()
    else
      attach_snacks(state)
    end
  else
    local width = math.max(1, math.floor(vim.o.columns * state.options.split_width_percentage))
    state.win = split(state.buf, state.options.split_side, nil, width)
  end

  if M.attached(state.win, state.buf) then
    local user = state.options.snacks_win_opts
    if state.frontend ~= "snacks" or (user.enter ~= false and user.focusable ~= false) then
      api.nvim_set_current_win(state.win)
      if state.job and state.options.auto_insert and api.nvim_get_current_buf() == state.buf then
        vim.cmd.startinsert()
      end
    end
  end
end

return M
