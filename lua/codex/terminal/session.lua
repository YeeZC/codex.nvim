local M = {}
local api = vim.api
local logger = require("codex.logger")
local window = require("codex.terminal.window")
local marker = "codex_session"
local session
local opening
local session_group
local displayed_tip = false

local function live(job)
  if not job or job <= 0 then
    return false
  end
  return pcall(vim.fn.jobpid, job)
end

local function delete_buffer(buf)
  if api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
end

local function finish(state, exit_code)
  if state.finished then
    return
  end
  state.finished = true
  if session == state then
    session = nil
  end
  if api.nvim_buf_is_valid(state.buf) then
    vim.b[state.buf][marker] = nil
  end
  if state.stopping or state.options.auto_close then
    window.dismiss(state, false)
  end
  if state.stopping or (state.frontend == "snacks" and state.options.auto_close) then
    if state.job and state.job > 0 then
      -- The process can exit before the PTY finishes pending writes.
      vim.defer_fn(function()
        delete_buffer(state.buf)
      end, 10)
    else
      delete_buffer(state.buf)
    end
  end
  if
    not state.stopping
    and exit_code
    and exit_code ~= 0
    and state.frontend == "snacks"
    and state.options.auto_close
  then
    logger.error("terminal", ("Codex exited with status %d."):format(exit_code))
  end
end

local function monitor(state)
  session_group = session_group or api.nvim_create_augroup("CodexManagedSession", { clear = false })
  api.nvim_clear_autocmds({ group = session_group, buffer = state.buf })
  api.nvim_create_autocmd("BufEnter", {
    group = session_group,
    buffer = state.buf,
    desc = "Restore input when returning to the Codex terminal",
    callback = function()
      if state.options.auto_insert then
        vim.schedule(function()
          -- A later autocmd can move focus away before the window switch settles.
          if
            api.nvim_get_current_buf() == state.buf
            and not state.stopping
            and not state.finished
            and live(state.job)
          then
            vim.cmd.startinsert()
          end
        end)
      end
    end,
  })
  api.nvim_create_autocmd("TermClose", {
    group = session_group,
    buffer = state.buf,
    once = true,
    callback = function()
      local status = vim.v.event.status
      vim.schedule(function()
        finish(state, status)
      end)
    end,
  })
end

local function adopt(options)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local saved = vim.b[buf][marker]
    if saved and vim.bo[buf].buftype == "terminal" and live(vim.bo[buf].channel) then
      local state = {
        buf = buf,
        job = vim.bo[buf].channel,
        win = window.find(buf),
        frontend = saved.frontend,
        options = vim.tbl_extend("force", options, { auto_close = saved.auto_close }),
      }
      monitor(state)
      return state
    end
  end
end

local function active(options)
  if session and (not api.nvim_buf_is_valid(session.buf) or not live(session.job)) then
    finish(session)
  end
  if not session and not opening then
    session = adopt(options)
  end
  return session
end

function M.buffer(options)
  local state = active(options)
  return state and state.buf
end

function M.close(options)
  if opening then
    opening.stopping = true
    return
  end
  local state = active(options)
  if not state or state.stopping then
    return
  end
  state.stopping = true
  -- A child may still be setting up its PTY immediately after jobstart.
  if state.launched and vim.uv.hrtime() - state.launched < 1000000000 then
    local ok, pid = pcall(vim.fn.jobpid, state.job)
    if ok then
      local _, editor = pcall(api.nvim_get_proc, vim.fn.getpid())
      vim.wait(300, function()
        local got_child, child = pcall(api.nvim_get_proc, pid)
        return type(editor) ~= "table" or not got_child or not child or child.name ~= editor.name
      end, 5)
    end
  end
  if live(state.job) then
    pcall(vim.fn.jobstop, state.job)
    vim.wait(1000, function()
      return not live(state.job)
    end, 5)
  end
  if not live(state.job) then
    finish(state)
  end
end

local function start(argv, environment, options, frontend)
  local buf = api.nvim_create_buf(false, false)
  local state = { buf = buf, argv = argv, options = options, frontend = frontend }
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  opening = state
  local ok, why = pcall(function()
    window.show(state)
    if state.stopping or not api.nvim_buf_is_valid(buf) then
      return
    end
    monitor(state)
    state.job = api.nvim_buf_call(buf, function()
      return vim.fn.jobstart(argv, { term = true, cwd = options.cwd, env = environment })
    end)
    assert(state.job > 0, "Codex command did not start")
    state.launched = vim.uv.hrtime()
    vim.bo[buf].bufhidden = "hide"
    if frontend == "native" then
      vim.bo[buf].filetype = "codex"
    end
    vim.b[buf][marker] = { frontend = frontend, auto_close = options.auto_close }
    require("codex.utils").map_terminal_suspend(buf)
  end)
  opening = nil
  if not ok or not state.job or state.job <= 0 then
    if live(state.job) then
      session, state.stopping = state, false
      M.close(options)
    else
      state.stopping = true
      finish(state)
    end
    if not ok then
      logger.error("terminal", "Could not open Codex. " .. tostring(why))
    end
    return
  end
  session = state
  if state.stopping then
    state.stopping = false
    M.close(options)
    return
  end
  if options.auto_insert and api.nvim_get_current_buf() == buf then
    vim.cmd.startinsert()
  end
  if frontend == "native" and options.show_native_term_exit_tip and not displayed_tip then
    displayed_tip = true
    logger.info("terminal", "Press Ctrl-\\ then Ctrl-N to leave Terminal mode.")
  end
end

function M.show(action, argv, environment, options, frontend)
  if opening or (session and session.stopping) then
    return
  end
  local state = active(options)
  if state and state.frontend ~= frontend then
    M.close(options)
    state = active(options)
    if state then
      return
    end
  end
  if not state then
    start(argv, environment, options, frontend)
  elseif
    window.visible(state)
    and (action == "simple_toggle" or (action == "focus_toggle" and state.win == api.nvim_get_current_win()))
  then
    window.dismiss(state, true)
  else
    state.options = vim.tbl_extend("force", options, { auto_close = state.options.auto_close })
    local ok, err = pcall(window.show, state)
    if not ok then
      logger.error("terminal", "Could not show Codex. " .. tostring(err))
    end
  end
end

return M
