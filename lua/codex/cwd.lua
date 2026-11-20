local M = {}

local function directory(value)
  if type(value) ~= "string" or value == "" then
    return
  end
  if not value:match("^[~$]") and vim.fn.isdirectory(value) == 1 then
    return value
  end
  local candidate = vim.fn.expand(value)
  if vim.fn.isdirectory(candidate) == 1 then
    return candidate
  end
end

function M.git_root(start)
  local dir = directory(start)
  if not dir then
    return
  end
  local ok, result = pcall(function()
    return vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = dir, text = true }):wait()
  end)
  if ok and result.code == 0 then
    local root = directory((result.stdout or ""):gsub("\n$", ""))
    if root then
      return root
    end
  end
  return vim.fs.root(vim.fs.normalize(vim.fn.fnamemodify(dir, ":p")), ".git")
end

function M.resolve(options, context)
  if type(options) ~= "table" then
    return
  end
  if options.cwd_provider then
    local ok, result = pcall(options.cwd_provider, context)
    local supplied = ok and directory(result)
    if supplied then
      return supplied
    end
  end
  local configured = directory(options.cwd)
  if configured then
    return configured
  end
  if options.git_repo_cwd then
    return M.git_root(context and (context.file_dir or context.cwd) or vim.fn.getcwd())
  end
end

return M
