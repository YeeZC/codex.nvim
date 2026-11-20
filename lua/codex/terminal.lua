--- Runs the Codex CLI in a managed Neovim terminal.
local M = {}
local cwd = require("codex.cwd")
local logger = require("codex.logger")
local session = require("codex.terminal.session")
local utils = require("codex.utils")

local defaults = {
  provider = "auto",
  split_side = "right",
  split_width_percentage = 0.30,
  show_native_term_exit_tip = true,
  auto_close = true,
  auto_insert = true,
  git_repo_cwd = false,
  snacks_win_opts = {},
  fix_streamed_paste = "auto",
}

local frontend
local config
local command
local env

function M.setup(terminal_opts, terminal_cmd, terminal_env)
  terminal_opts = terminal_opts or {}
  vim.validate("terminal", terminal_opts, "table")
  vim.validate("terminal_cmd", terminal_cmd, "string", true)
  vim.validate("env", terminal_env, "table", true)
  local options = vim.tbl_extend("force", defaults, terminal_opts)
  assert(
    options.provider == "auto" or options.provider == "native" or options.provider == "snacks",
    "terminal.provider must be auto, native or snacks"
  )
  assert(options.split_side == "left" or options.split_side == "right", "terminal.split_side must be left or right")
  assert(
    type(options.split_width_percentage) == "number"
      and options.split_width_percentage > 0
      and options.split_width_percentage < 1,
    "terminal.split_width_percentage must be between 0 and 1"
  )
  vim.validate("terminal.snacks_win_opts", options.snacks_win_opts, "table")
  vim.validate("terminal.cwd", options.cwd, "string", true)
  vim.validate("terminal.cwd_provider", options.cwd_provider, "function", true)
  for _, key in ipairs({ "auto_close", "auto_insert", "git_repo_cwd", "show_native_term_exit_tip" }) do
    vim.validate("terminal." .. key, options[key], "boolean")
  end
  assert(
    options.fix_streamed_paste == "auto" or type(options.fix_streamed_paste) == "boolean",
    "terminal.fix_streamed_paste must be auto or a boolean"
  )
  local executable = terminal_cmd or "codex"
  assert(executable:find("%S"), "terminal_cmd must contain a command")
  local options_env = vim.deepcopy(terminal_env or {})
  for key, value in pairs(options_env) do
    assert(type(key) == "string" and type(value) == "string", "env must contain string keys and values")
  end

  frontend = "native"
  if options.provider ~= "native" then
    local available = pcall(function()
      local snacks = require("snacks")
      assert(snacks.win and snacks.terminal)
    end)
    if available then
      frontend = "snacks"
    elseif options.provider == "snacks" then
      logger.warn("terminal", "Snacks terminal unavailable. Using the native terminal.")
    end
  end
  require("codex.terminal.paste_fix").apply(options.fix_streamed_paste)
  config, command = options, executable
  env = next(options_env) and options_env or vim.empty_dict()
end

---Show, focus or toggle the terminal. Arguments apply when starting a session.
---@param action "open"|"simple_toggle"|"focus_toggle"
---@param args? string
function M.show(action, args)
  local launch_command = args and args ~= "" and (command .. " " .. args) or command
  local file = vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) or ""
  local effective_config = vim.tbl_extend("force", {}, config)
  effective_config.cwd = cwd.resolve(config, {
    file = file ~= "" and file or nil,
    file_dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or nil,
    cwd = vim.fn.getcwd(),
  })
  session.show(action, utils.parse_command(launch_command), env, effective_config, frontend)
end

function M.close()
  session.close(config)
end

function M.get_active_terminal_bufnr()
  return config and session.buffer(config)
end

---Insert context at the cursor in the running Codex prompt.
---@param value string
---@param focus boolean
---@return boolean
function M.insert(value, focus)
  local buf = M.get_active_terminal_bufnr()
  if not buf then
    logger.warn("terminal", "Open Codex with :CodexOpen and wait for the prompt before sending context.")
    return false
  end
  local channel = vim.bo[buf].channel
  -- Keep PTY control bytes out of pasted content, including embedded bracketed-paste delimiters.
  local printable = utils.valid_utf8(value):gsub("[%c%z]", function(char)
    if char == "\t" or char == "\n" then
      return char
    end
    return string.format("\\x%02X", char:byte())
  end)
  local ok, written = pcall(vim.fn.chansend, channel, "\27[200~" .. printable .. "\27[201~")
  if not ok or written == 0 then
    logger.warn("terminal", "Could not write to the Codex terminal.")
    return false
  end
  if focus then
    M.show("open")
  end
  return true
end

return M
