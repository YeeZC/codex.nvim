-- Run in Neovim's main loop so it processes mouse and keyboard input.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.mouse = "a"

local api = vim.api
local editor = api.nvim_get_current_win()
require("codex").setup({
  terminal_cmd = "sh -c 'stty raw -echo && printf READY && cat'",
  terminal = { provider = "native", show_native_term_exit_tip = false },
})

local function click(win)
  local row, col = unpack(api.nvim_win_get_position(win))
  api.nvim_input_mouse("left", "press", "", 0, row, col)
  api.nvim_input_mouse("left", "release", "", 0, row, col)
end

local win, buf
local function contains(value)
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find(value, 1, true) ~= nil
end

local steps = {
  function()
    vim.cmd.CodexOpen()
    win = api.nvim_get_current_win()
    buf = api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return contains("READY")
      end),
      "Codex terminal fixture did not start"
    )
  end,
  function()
    assert(api.nvim_get_mode().mode == "t", "Expected Terminal mode on open")
    click(editor)
  end,
  function()
    assert(api.nvim_get_current_win() == editor, "Expected focus to move to the editor")
    click(win)
  end,
  function()
    assert(api.nvim_get_current_win() == win and api.nvim_get_current_buf() == buf, "Expected focus to return to Codex")
    assert(api.nvim_get_mode().mode == "t", "Expected Terminal mode after clicking back into Codex")
    api.nvim_input("click-input")
  end,
  function()
    assert(
      vim.wait(3000, function()
        return contains("click-input")
      end),
      "Typed text did not reach the terminal process"
    )
    vim.cmd.CodexClose()
    print("PASS Codex terminal input after mouse focus")
    vim.cmd.quit()
  end,
}

local function run(index)
  local ok, err = pcall(steps[index])
  if not ok then
    io.stderr:write(tostring(err) .. "\n")
    vim.cmd.cquit()
  elseif steps[index + 1] then
    vim.defer_fn(function()
      run(index + 1)
    end, 100)
  end
end

run(1)
