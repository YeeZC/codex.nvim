local M = {}
local logger = require("codex.logger")
local terminal = require("codex.terminal")
local utils = require("codex.utils")

local function file_path(buf)
  if vim.bo[buf].buftype == "" then
    local path = vim.api.nvim_buf_get_name(buf)
    if path ~= "" then
      return path
    end
  end
end

local function setup_current_file(enabled)
  local group = vim.api.nvim_create_augroup("CodexCurrentFile", { clear = true })
  if not enabled then
    return
  end

  local current_file = file_path(vim.api.nvim_get_current_buf())
  local last_file, last_terminal
  vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost" }, {
    group = group,
    desc = "Add the current file to the Codex draft when returning to its terminal",
    callback = function(event)
      local path = file_path(event.buf)
      if path then
        current_file = path
      elseif
        event.event == "BufEnter"
        and current_file
        and vim.bo[event.buf].buftype == "terminal"
        and terminal.get_active_terminal_bufnr() == event.buf
      then
        vim.schedule(function()
          if
            vim.api.nvim_get_current_buf() == event.buf
            and terminal.get_active_terminal_bufnr() == event.buf
            and (last_terminal ~= event.buf or last_file ~= current_file)
          then
            local context = "Current Neovim file: " .. vim.json.encode(utils.valid_utf8(current_file)) .. "\n\n"
            if terminal.insert(context, false) then
              last_file, last_terminal = current_file, event.buf
            end
          end
        end)
      end
    end,
  })
end

local function setup_keymaps(enabled, label)
  local group = vim.api.nvim_create_augroup("CodexKeymaps", { clear = true })
  if not enabled then
    return
  end

  local function map(mode, lhs, command, desc, buf)
    pcall(vim.keymap.set, mode, lhs, "<Cmd>" .. command .. "<CR>", {
      desc = desc:gsub("Codex", label),
      buffer = buf,
      unique = true,
    })
  end

  map("n", "<leader>ac", "Codex", "Toggle Codex")
  map("n", "<leader>ao", "CodexOpen", "Open Codex")
  map("n", "<leader>af", "CodexFocus", "Focus Codex")
  map("n", "<leader>aq", "CodexClose", "Stop Codex session")
  map("n", "<leader>ab", "CodexAdd", "Add current file to Codex")
  map("x", "<leader>as", "CodexSend", "Send selection to Codex")

  local tree_filetypes = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw", "snacks_picker_list" }
  local function map_tree(buf)
    map("n", "<leader>as", "CodexTreeAdd", "Add file from tree", buf)
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = tree_filetypes,
    callback = function(event)
      map_tree(event.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(tree_filetypes, vim.bo[buf].filetype) then
      map_tree(buf)
    end
  end
end

---Configure Codex and register the editor commands.
---@param opts? {agent?: "codex"|"agy"|"cursor", terminal?: CodexTerminalConfig, terminal_cmd?: string, default_args?: string[], env?: table<string, string>, focus_after_send?: boolean, auto_add_current_file?: boolean, default_keymaps?: boolean, log_level?: string}
function M.setup(opts)
  assert(vim.fn.has("nvim-0.11") == 1, "Codex.nvim requires Neovim 0.11 or newer")
  vim.validate("opts", opts, "table", true)
  opts = opts or {}
  vim.validate("focus_after_send", opts.focus_after_send, "boolean", true)
  vim.validate("auto_add_current_file", opts.auto_add_current_file, "boolean", true)
  vim.validate("default_keymaps", opts.default_keymaps, "boolean", true)
  local agent = require("codex.agents").get(opts.agent)
  terminal.setup(opts.terminal, opts.terminal_cmd, opts.env, opts.default_args, agent.name)
  logger.setup({ log_level = opts.log_level or "info", label = agent.label })
  setup_current_file(opts.auto_add_current_file)
  local focus = opts.focus_after_send ~= false
  local function command(name, callback, options)
    options.desc = options.desc:gsub("Codex", agent.label)
    vim.api.nvim_create_user_command(name, callback, options)
    vim.api.nvim_create_user_command(name:gsub("^Codex", "Agent"), callback, options)
  end

  command("Codex", function(args)
    terminal.show("simple_toggle", args.args)
  end, { nargs = "*", desc = "Toggle the Codex terminal" })

  command("CodexFocus", function(args)
    terminal.show("focus_toggle", args.args)
  end, { nargs = "*", desc = "Focus Codex or hide its focused terminal" })

  command("CodexOpen", function(args)
    terminal.show("open", args.args)
  end, { nargs = "*", desc = "Open or focus the Codex terminal" })

  command("CodexYolo", function(args)
    if terminal.get_active_terminal_bufnr() then
      logger.warn("terminal", "Run :AgentClose before starting :AgentYolo.")
      return
    end
    terminal.show("open", args.args, true)
  end, { nargs = "*", desc = "Start Codex with its permission-bypass option" })

  command("CodexClose", terminal.close, { desc = "Close the Codex session" })

  command("CodexResume", function(args)
    if terminal.get_active_terminal_bufnr() then
      logger.warn("terminal", "Run :AgentClose before starting :AgentResume.")
      return
    end
    terminal.show("open", args.args, false, true)
  end, { nargs = "*", desc = "Resume the latest Codex session" })

  command("CodexAdd", function(args)
    local path = args.fargs[1] or "%"
    if path == "%" or path == "#" or path:match("^[%%#]:") then
      path = vim.fn.expand(path)
    else
      if not vim.uv.fs_stat(path) then
        path = path:gsub("\\([ \t])", "%1")
      end
      path = utils.expand_tilde(path)
    end
    if path == "" or not vim.uv.fs_stat(path) then
      logger.warn("context", "File or directory not found: " .. path)
      return
    end
    path = vim.fn.fnamemodify(path, ":p")
    terminal.insert("Path: " .. vim.json.encode(utils.valid_utf8(path)) .. "\n\n", focus)
  end, { nargs = "?", complete = "file", desc = "Insert a file or directory path into the Codex prompt" })

  command("CodexTreeAdd", function()
    local files, err = require("codex.integrations").get_selected_files_from_tree()
    if not files or #files == 0 then
      logger.warn("context", err or "No files selected.")
      return
    end
    local paths = {}
    for _, path in ipairs(files) do
      local absolute = vim.fn.fnamemodify(path, ":p")
      paths[#paths + 1] = "Path: " .. vim.json.encode(utils.valid_utf8(absolute))
    end
    terminal.insert(table.concat(paths, "\n") .. "\n\n", focus)
  end, { desc = "Insert paths from the file explorer into the Codex prompt" })

  command("CodexSend", function(args)
    if vim.bo.buftype ~= "" then
      logger.warn("context", "Select text in a file buffer.")
      return
    end

    local first, last, lines
    local mode = utils.selection_type(vim.api.nvim_get_mode().mode)
    if mode then
      local anchor, cursor = vim.fn.getpos("v"), vim.fn.getpos(".")
      lines = vim.fn.getregion(anchor, cursor, { type = mode, exclusive = vim.o.selection == "exclusive" })
      first, last = math.min(anchor[2], cursor[2]), math.max(anchor[2], cursor[2])
    elseif args.range > 0 then
      first, last = args.line1, args.line2
      lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
    else
      logger.warn("context", "Select text or give :CodexSend a line range.")
      return
    end

    local path = vim.api.nvim_buf_get_name(0)
    local label = path == "" and "(unsaved buffer)" or vim.json.encode(utils.valid_utf8(path))
    local context =
      string.format("Selection from %s, lines %d–%d:\n%s\n\n", label, first, last, table.concat(lines, "\n"))
    if mode then
      vim.cmd.normal({ args = { "\27" }, bang = true })
    end
    terminal.insert(context, focus)
  end, { range = true, desc = "Insert selected buffer text into the Codex prompt" })

  setup_keymaps(opts.default_keymaps ~= false, agent.label)
end

return M
