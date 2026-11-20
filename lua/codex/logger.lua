local levels = { "ERROR", "WARN", "INFO", "DEBUG", "TRACE" }
local M = { levels = {} }
local threshold = 3
local label = "Codex"

local function write(level, area, pieces, compact)
  if level > threshold then
    return
  end
  local name = label
  local prefix = "[" .. name .. "]" .. (area and (" [" .. area .. "]") or "")
  local message = prefix .. " [" .. levels[level] .. "] " .. table.concat(pieces, " ")
  vim.schedule(function()
    if compact then
      message = message:gsub("%s+", " ")
      local width = vim.v.echospace
      if vim.fn.strdisplaywidth(message) > width then
        local suffix = width >= 3 and "..." or ""
        local chars = vim.fn.strchars(message)
        repeat
          chars = chars - 1
          message = vim.fn.strcharpart(message, 0, chars)
        until vim.fn.strdisplaywidth(message .. suffix) <= width
        message = message .. suffix
      end
    end
    if level <= 2 then
      vim.notify(
        message,
        vim.log.levels[levels[level]],
        { title = name .. " " .. (level == 1 and "Error" or "Warning") }
      )
    else
      vim.api.nvim_echo({ { message } }, true, {})
    end
  end)
end

for rank, label in ipairs(levels) do
  M.levels[label] = rank
  M[label:lower()] = function(area, ...)
    local pieces = vim.tbl_map(function(value)
      return type(value) == "table" and vim.inspect(value) or tostring(value)
    end, type(area) == "string" and { ... } or { area, ... })
    write(rank, type(area) == "string" and area or nil, pieces, false)
  end
end

function M.setup(options)
  label = options.label or "Codex"
  threshold = M.levels[(options.log_level or "INFO"):upper()] or M.levels.INFO
end

function M.is_level_enabled(level)
  return (M.levels[level:upper()] or math.huge) <= threshold
end

function M.one_line(level, area, message)
  local rank = assert(M.levels[level:upper()])
  write(rank, area, { message }, threshold < M.levels.DEBUG)
end

return M
