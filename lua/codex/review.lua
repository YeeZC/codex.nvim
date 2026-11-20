local M = {}
local api = vim.api
local uv = vim.uv
local logger = require("codex.logger")
local view = require("codex.review.view")
local current

local function item_key(thread, turn, item)
  return table.concat({ thread, turn, item }, "\0")
end

local function has_diff(changes)
  if type(changes) ~= "table" or #changes == 0 then
    return false
  end
  for _, change in ipairs(changes) do
    if type(change.path) ~= "string" or type(change.diff) ~= "string" or type(change.kind) ~= "table" then
      return false
    end
    local kind = change.kind.type
    if kind ~= "add" and kind ~= "delete" and kind ~= "update" then
      return false
    end
  end
  return true
end

local function show(review)
  local ok, err = pcall(view.open, review)
  if not ok then
    logger.warn("review", "Could not open the diff. " .. tostring(err))
  end
end

local function dismiss(state, review, reason)
  state.pending[review.id] = nil
  view.close(review, reason)
end

local function present(state, review, changes)
  if state.pending[review.id] ~= review then
    return
  end
  if not has_diff(changes) then
    logger.warn("review", "Diff details are unavailable. Review this request in the Codex terminal.")
    return
  end
  review.changes = changes
  for _, pending in pairs(state.pending) do
    if pending ~= review and pending.win and api.nvim_win_is_valid(pending.win) then
      logger.info("review", "Another Codex diff is ready. Use :CodexDiff to review it.")
      return
    end
  end
  show(review)
end

local function handle(state, message, from_tui)
  local method, params = message.method, message.params or {}
  if from_tui then
    local review = state.pending[message.id]
    if review then
      review.answered = true
    end
  elseif method == "item/started" and params.item.type == "fileChange" then
    state.items[item_key(params.threadId, params.turnId, params.item.id)] = params.item.changes
  elseif method == "item/fileChange/requestApproval" and message.id ~= nil then
    if state.pending[message.id] then
      return
    end
    state.sequence = state.sequence + 1
    local review = {
      id = message.id,
      thread = params.threadId,
      turn = params.turnId,
      item = params.itemId,
      sequence = state.sequence,
    }
    state.pending[message.id] = review
    local key = item_key(review.thread, review.turn, review.item)
    local changes = state.items[key]
    state.items[key] = nil
    present(state, review, changes)
  elseif method == "serverRequest/resolved" then
    local review = state.pending[params.requestId]
    if review and review.thread == params.threadId then
      dismiss(state, review, "resolved")
    end
  elseif method == "item/completed" and params.item.type == "fileChange" then
    state.items[item_key(params.threadId, params.turnId, params.item.id)] = nil
  elseif method == "turn/completed" or method == "thread/closed" then
    local turn = params.turn and params.turn.id
    for _, review in pairs(state.pending) do
      if review.thread == params.threadId and (not turn or review.turn == turn) then
        dismiss(state, review, "resolved")
      end
    end
  end
  -- Other server requests remain available for the Codex TUI to answer.
end

local function disconnect(state, reason)
  if state.client then
    state.client.close()
    state.client = nil
  end
  if current == state then
    current = nil
  end
  for _, review in pairs(state.pending) do
    dismiss(state, review, reason)
  end
  state.items = {}
end

function M.start(argv, environment, cwd, cancelled)
  local state = { items = {}, pending = {}, sequence = 0 }
  local dir = assert(uv.fs_mkdtemp(vim.fs.joinpath(uv.os_tmpdir(), "codex-nvim-XXXXXX")))
  local path = vim.fs.joinpath(dir, "review.sock")
  local upstream = vim.fs.joinpath(dir, "server.sock")
  local job, failure
  local backend = {}
  local stopped = false
  local function cleanup()
    vim.fn.delete(dir, "rf")
  end

  function backend.close()
    if stopped then
      return
    end
    stopped = true
    disconnect(state, "session closed")
    if job and job > 0 then
      pcall(vim.fn.jobstop, job)
    else
      cleanup()
    end
  end

  local ok, err = pcall(function()
    local server_args = {
      argv[1],
      "app-server",
      "--listen",
      "unix://" .. upstream,
      "--disable",
      "app_server_websocket_compression",
      "-c",
      'sandbox_mode="read-only"',
      "-c",
      'approval_policy="on-request"',
      "-c",
      'approvals_reviewer="user"',
    }
    job = vim.fn.jobstart(server_args, {
      cwd = cwd,
      env = environment,
      on_exit = function(_, code)
        job = nil
        failure = "Codex App Server exited with status " .. code .. "."
        if current == state then
          logger.warn("review", failure)
        end
        disconnect(state, "disconnected")
        cleanup()
      end,
    })
    assert(job > 0, "Could not start Codex App Server.")
    vim.wait(5000, function()
      return failure or cancelled() or uv.fs_stat(upstream)
    end, 20)
    if cancelled() then
      return
    end
    assert(not failure and uv.fs_stat(upstream), failure or "Timed out waiting for the Codex App Server socket.")
    state.client = require("codex.review.socket").listen(path, upstream, function(message, from_tui)
      handle(state, message, from_tui)
    end, function(reason)
      if reason and current == state and not stopped then
        logger.warn("review", reason)
      end
      disconnect(state, "disconnected")
    end)
  end)

  if not ok or cancelled() then
    backend.close()
    if not ok then
      error(err, 0)
    end
    return
  end

  current = state
  local tui = { argv[1], "--remote", "unix://" .. path, "--sandbox", "read-only", "--ask-for-approval", "on-request" }
  vim.list_extend(tui, argv, 2)
  return backend, tui
end

local function selected()
  local first
  if current then
    local buf = api.nvim_get_current_buf()
    for _, review in pairs(current.pending) do
      if review.changes then
        if review.buf == buf then
          return review
        end
        if not first or review.sequence < first.sequence then
          first = review
        end
      end
    end
  end
  if not first then
    logger.info("review", "No pending Codex diff is available.")
  end
  return first
end

function M.open()
  local review = selected()
  if review then
    show(review)
  end
end

local function normalize(path)
  return uv.fs_realpath(path) or vim.fs.normalize(vim.fn.resolve(path), { expand_env = false })
end

local function modified_path(changes)
  local paths = {}
  for _, change in ipairs(changes) do
    paths[normalize(change.path)] = true
    if type(change.kind.move_path) == "string" then
      paths[normalize(change.kind.move_path)] = true
    end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buftype == "" then
      local name = api.nvim_buf_get_name(buf)
      if name ~= "" and paths[normalize(name)] then
        return name
      end
    end
  end
end

function M.decide(decision)
  local review = selected()
  if not review or review.answered then
    return
  end
  if decision == "accept" then
    local modified = modified_path(review.changes)
    if modified then
      logger.warn("review", "Save your edits before accepting changes to " .. modified)
      return
    end
  end
  if current.client.send({ id = review.id, result = { decision = decision } }) then
    review.answered = true
  end
end

return M
