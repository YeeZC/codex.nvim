-- Run from the repository root with `nvim -l tests/integration/context.lua [snacks-directory]`.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = ","
local snacks_path = arg[1]
if snacks_path then
  vim.opt.runtimepath:append(snacks_path)
end

local agent = vim.env.CODEX_TEST_AGENT or "codex"
local adapter = require("codex.agents").get(agent)
local yolo_alias = adapter.yolo_aliases[#adapter.yolo_aliases]

local root
local original_buf
local ok, err = xpcall(function()
  root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  local input = root .. "/file with spaces.txt"
  local output = root .. "/received"
  local arguments = root .. "/arguments"
  local tree_file = root .. "/tree entry.txt"
  vim.fn.writefile({ "prefix 天地 suffix", "second line" }, input)
  vim.fn.writefile({ "tree fixture" }, tree_file)
  vim.cmd.edit({ args = { input } })
  original_buf = vim.api.nvim_get_current_buf()

  local opts = {
    agent = agent,
    default_args = { yolo_alias, "-c", [[fixture="literal $HOME; text"]] },
    terminal_cmd = "sh -c " .. vim.fn.shellescape([[
        output=$1
        arguments=$2
        shift 2
        printf '%s\n' "$@" > "$arguments"
        stty raw -echo && printf '\033[?2004hREADY' && cat > "$output"
      ]]) .. " sh " .. vim.fn.shellescape(output) .. " " .. vim.fn.shellescape(arguments),
    focus_after_send = false,
    terminal = {
      provider = snacks_path and "snacks" or "native",
      snacks_win_opts = { position = "float" },
      auto_insert = false,
      show_native_term_exit_tip = false,
    },
  }
  local codex = require("codex")
  codex.setup(vim.tbl_extend("force", opts, { default_keymaps = false }))
  assert(vim.fn.maparg("<leader>ao", "n") == "")
  vim.keymap.set("n", "<leader>af", "<Nop>")
  codex.setup(opts)
  assert(vim.fn.maparg("<leader>af", "n"):lower() == "<nop>")
  vim.api.nvim_feedkeys(",ao", "mx", false)
  local terminal_buf = vim.api.nvim_get_current_buf()
  assert(vim.bo[terminal_buf].filetype == "codex")
  if snacks_path then
    assert(vim.api.nvim_win_get_config(0).relative ~= "", "Expected a Snacks float")
    local mapped = vim.iter(vim.api.nvim_buf_get_keymap(terminal_buf, "t")):any(function(key)
      return key.desc == "New line"
    end)
    assert(mapped == (agent == "codex"), "Only Codex should receive the Shift-Enter workaround")
  end
  assert(vim.wait(3000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false), "\n"):find("READY", 1, true) ~= nil
  end))

  assert(vim.deep_equal(vim.fn.readfile(arguments), opts.default_args))
  local changed = vim.tbl_extend("force", opts, { agent = agent == "codex" and "agy" or "codex" })
  assert(not pcall(codex.setup, changed), "Changing agent must preserve the running session")
  assert(require("codex.terminal").get_active_terminal_bufnr() == terminal_buf)
  assert(vim.fn.exists(":AgentOpen") == 2)
  assert(vim.fn.exists(":AgentResume") == 2)
  for _, module in ipairs({ "codex", "codex.terminal", "codex.terminal.session" }) do
    package.loaded[module] = nil
  end
  codex = require("codex")
  assert(not pcall(codex.setup, changed), "Reload must preserve the running agent identity")
  codex.setup(opts)
  vim.cmd.AgentOpen()
  assert(require("codex.terminal").get_active_terminal_bufnr() == terminal_buf)
  vim.cmd.Codex()
  assert(vim.api.nvim_get_current_buf() == original_buf)
  vim.cmd.CodexYolo()
  assert(vim.api.nvim_get_current_buf() == original_buf)
  assert(require("codex.terminal").get_active_terminal_bufnr() == terminal_buf)
  vim.cmd.Codex()
  assert(vim.api.nvim_get_current_buf() == terminal_buf)
  vim.cmd.Codex()
  assert(vim.api.nvim_get_current_buf() == original_buf)
  vim.cmd("CodexAdd " .. vim.fn.fnameescape(input))
  vim.cmd("2CodexSend")
  vim.g.netrw_dirhistmax = 0
  vim.cmd.runtime("plugin/netrwPlugin.vim")
  vim.cmd.new()
  vim.cmd("Explore " .. vim.fn.fnameescape(root))
  assert(vim.bo.filetype == "netrw", "Expected a netrw directory listing")
  assert(vim.fn.search([[\Vtree entry.txt]], "w") > 0, "Expected the file in the directory listing")
  vim.api.nvim_feedkeys(",as", "mx", false)
  vim.cmd.close()
  assert(vim.api.nvim_get_current_buf() == original_buf)

  vim.api.nvim_buf_set_text(original_buf, 0, 7, 0, 13, { "日月" })
  vim.api.nvim_feedkeys("0wvl,as", "mx", false)

  local received
  assert(vim.wait(3000, function()
    local file = io.open(output, "rb")
    if file then
      received = file:read("*a")
      file:close()
    end
    return received and received:find("日月", 1, true) ~= nil
  end))
  local path = vim.json.encode(input)
  local expected = {
    "Path: " .. path,
    "Path: " .. vim.json.encode(tree_file),
    "Selection from " .. path .. ", lines 2–2:\nsecond line",
    "Selection from " .. path .. ", lines 1–1:\n日月",
  }
  for _, context in ipairs(expected) do
    assert(
      received:find("\27[200~" .. context .. "\n\n\27[201~", 1, true),
      ("Missing %q in %q"):format(context, received)
    )
  end
  assert(not received:find("\r", 1, true))
  assert(vim.api.nvim_get_current_buf() == original_buf)

  vim.cmd.CodexFocus()
  assert(vim.api.nvim_get_current_buf() == terminal_buf)
  vim.cmd.CodexClose()
  assert(vim.api.nvim_get_current_buf() == original_buf)
  assert(require("codex.terminal").get_active_terminal_bufnr() == nil)

  vim.fn.delete(output)
  opts.terminal.fix_streamed_paste = true
  require("codex").setup(vim.tbl_extend("force", opts, { auto_add_current_file = true }))
  vim.cmd([[CodexYolo --model "fixture model; literal"]])
  terminal_buf = vim.api.nvim_get_current_buf()
  assert(vim.wait(3000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false), "\n"):find("READY", 1, true) ~= nil
  end))
  assert(
    vim.deep_equal(
      vim.fn.readfile(arguments),
      { yolo_alias, "-c", [[fixture="literal $HOME; text"]], "--model", "fixture model; literal" }
    )
  )
  local channel = vim.bo[terminal_buf].channel
  assert(vim.api.nvim_paste("seg", false, 1))
  assert(vim.api.nvim_paste("ment", false, 2))
  assert(vim.api.nvim_paste("ed", false, 3))
  vim.fn.chansend(channel, "existing draft\n")
  vim.cmd.Codex()
  vim.cmd.edit({ args = { tree_file }, mods = { hide = true } })
  local latest = root .. "/latest file.txt"
  vim.cmd.edit({ args = { latest } })
  vim.cmd.enew()
  assert(vim.fn.chansend(channel, "while browsing\n") > 0)
  vim.cmd.CodexFocus()
  assert(vim.api.nvim_get_current_buf() == terminal_buf)
  assert(vim.wait(3000, function()
    return vim.fn.filereadable(output) == 1
      and table.concat(vim.fn.readfile(output), "\n"):find("Current Neovim file", 1, true) ~= nil
  end))
  vim.cmd.Codex()
  vim.cmd.CodexFocus()
  -- Let the scheduled buffer-entry callback run before writing the end marker.
  vim.schedule(function()
    vim.fn.chansend(channel, "END")
  end)
  assert(vim.wait(3000, function()
    received = table.concat(vim.fn.readfile(output), "\n")
    return received:sub(-3) == "END"
  end))
  assert(
    received
      == "\27[200~segmented\27[201~existing draft\nwhile browsing\n\27[200~Current Neovim file: "
        .. vim.json.encode(latest)
        .. "\n\n\27[201~END",
    ("Unexpected automatic context in %q"):format(received)
  )

  vim.cmd.CodexClose()
  codex.setup(vim.tbl_extend("force", opts, { default_args = { "--search" } }))
  vim.cmd.CodexYolo()
  terminal_buf = vim.api.nvim_get_current_buf()
  assert(vim.wait(3000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false), "\n"):find("READY", 1, true) ~= nil
  end))
  assert(vim.deep_equal(vim.fn.readfile(arguments), { "--search", unpack(adapter.yolo_args) }))
  vim.cmd.AgentClose()
  codex.setup(vim.tbl_extend("force", opts, { default_args = {} }))
  vim.cmd.AgentResume()
  terminal_buf = vim.api.nvim_get_current_buf()
  assert(vim.wait(3000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false), "\n"):find("READY", 1, true) ~= nil
  end))
  assert(vim.deep_equal(vim.fn.readfile(arguments), adapter.resume_args))
  vim.cmd.Agent()
  vim.cmd.AgentOpen()
  assert(vim.api.nvim_get_current_buf() == terminal_buf)
end, debug.traceback)

if vim.fn.exists(":CodexClose") == 2 then
  vim.cmd.CodexClose()
end
if original_buf and vim.api.nvim_buf_is_valid(original_buf) then
  vim.api.nvim_buf_delete(original_buf, { force = true })
end
if root then
  vim.fn.delete(root, "rf")
end

assert(ok, err)
print(
  "PASS " .. agent .. " context and terminal lifecycle (" .. (snacks_path and "Snacks float" or "native split") .. ")"
)
