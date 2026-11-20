-- Symlink this file into your lazy.nvim plugin configuration to use this checkout.
local file = assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))

return {
  dir = vim.fs.dirname(file),
  name = "codex.nvim",
  main = "codex",
  cmd = {
    "Codex",
    "CodexOpen",
    "CodexFocus",
    "CodexClose",
    "CodexYolo",
    "CodexSend",
    "CodexAdd",
    "CodexTreeAdd",
    "CodexResume",
    "Agent",
    "AgentOpen",
    "AgentFocus",
    "AgentClose",
    "AgentYolo",
    "AgentResume",
    "AgentSend",
    "AgentAdd",
    "AgentTreeAdd",
  },
  opts = {},
  keys = {
    { "<leader>ac", "<Cmd>Codex<CR>", desc = "Toggle Codex" },
    { "<leader>ao", "<Cmd>CodexOpen<CR>", desc = "Open Codex" },
    { "<leader>af", "<Cmd>CodexFocus<CR>", desc = "Focus Codex" },
    { "<leader>aq", "<Cmd>CodexClose<CR>", desc = "Stop Codex session" },
    { "<leader>as", "<Cmd>CodexSend<CR>", mode = "x", desc = "Send selection to Codex" },
    { "<leader>ab", "<Cmd>CodexAdd<CR>", desc = "Add current file to Codex" },
    {
      "<leader>as",
      "<Cmd>CodexTreeAdd<CR>",
      desc = "Add file from tree",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw", "snacks_picker_list" },
    },
  },
}
