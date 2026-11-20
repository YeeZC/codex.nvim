if vim.g.loaded_codex then
  return
end
vim.g.loaded_codex = true

if vim.g.codex_auto_setup then
  require("codex").setup(vim.g.codex_auto_setup)
end
