---@class CodexCwdContext
---@field cwd string
---@field file? string
---@field file_dir? string

---@class CodexTerminalConfig
---@field provider? "auto"|"native"|"snacks"
---@field split_side? "left"|"right"
---@field split_width_percentage? number
---@field snacks_win_opts? snacks.win.Config
---@field auto_insert? boolean
---@field auto_close? boolean
---@field show_native_term_exit_tip? boolean
---@field cwd? string
---@field cwd_provider? fun(context: CodexCwdContext): string?
---@field git_repo_cwd? boolean
---@field fix_streamed_paste? boolean|"auto"

return {}
