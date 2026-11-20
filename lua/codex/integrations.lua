local M = {}
local utils = require("codex.utils")
local readers = {}

local function present(path)
  return type(path) == "string" and path ~= ""
end

local function on_disk(path)
  return present(path) and (vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1)
end

local function add(paths, path)
  if present(path) then
    paths[#paths + 1] = path
  end
end

local function each_selected_line(read)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local anchor = utils.selection_type(vim.api.nvim_get_mode().mode) and vim.fn.line("v") or line
  for number = math.min(line, anchor), math.max(line, anchor) do
    read(number)
  end
end

function readers.NvimTree()
  local tree = require("nvim-tree.api")
  local paths = {}
  for _, node in ipairs(tree.marks.list() or {}) do
    if node.type == "file" then
      add(paths, node.absolute_path)
    end
  end
  if #paths == 0 then
    local node = tree.tree.get_node_under_cursor()
    if node and (node.type == "file" or node.type == "directory") then
      add(paths, node.absolute_path)
    end
  end
  return paths
end

readers["neo-tree"] = function()
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  local tree = state and state.tree
  local paths = {}
  if not tree then
    return paths
  end
  if
    utils.selection_type(vim.api.nvim_get_mode().mode)
    and (not state.winid or state.winid == vim.api.nvim_get_current_win())
  then
    each_selected_line(function(line)
      local node = tree:get_node(line)
      if node and (node.type == "file" or node.type == "directory") then
        add(paths, node.path)
      end
    end)
  end
  if #paths == 0 then
    local selection = tree.get_selection and tree:get_selection()
    for _, node in ipairs(selection and #selection > 0 and selection or state.selected_nodes or {}) do
      if node.type == "file" then
        add(paths, node.path)
      end
    end
  end
  if #paths == 0 then
    local node = tree:get_node()
    if node and (node.type == "file" or node.type == "directory") then
      add(paths, node.path)
    end
  end
  return paths
end

function readers.oil()
  local oil = require("oil")
  local paths = {}
  local buf = vim.api.nvim_get_current_buf()
  local directory = oil.get_current_dir(buf)
  if not directory then
    return paths
  end
  local visual = utils.selection_type(vim.api.nvim_get_mode().mode) ~= nil
  each_selected_line(function(line)
    local ok, entry
    if visual then
      ok, entry = pcall(oil.get_entry_on_line, buf, line)
    else
      ok, entry = pcall(oil.get_cursor_entry)
    end
    if ok and entry and present(entry.name) and entry.name ~= "." and entry.name ~= ".." then
      local path = vim.fs.joinpath(directory, entry.name)
      paths[#paths + 1] = entry.type == "directory" and (path .. "/") or path
    end
  end)
  return paths
end

function readers.minifiles()
  local mini = require("mini.files")
  local buf = vim.api.nvim_get_current_buf()
  local paths = {}
  each_selected_line(function(line)
    local ok, entry = pcall(mini.get_fs_entry, buf, line)
    if ok and entry and on_disk(entry.path) then
      add(paths, entry.path)
    end
  end)
  return paths
end

function readers.netrw()
  local paths = {}
  local marked, entries = pcall(vim.fn["netrw#Expose"], "netrwmarkfilelist")
  if marked and type(entries) == "table" then
    for _, path in ipairs(entries) do
      if on_disk(path) then
        add(paths, path)
      end
    end
  end
  if #paths == 0 then
    local name = vim.fn["netrw#Call"]("NetrwGetWord")
    if present(name) and name ~= "." and name ~= ".." and name ~= "../" then
      local path = vim.fs.joinpath(vim.b.netrw_curdir or vim.fn.getcwd(), name)
      if on_disk(path) then
        add(paths, path)
      end
    end
  end
  return paths
end

function readers.snacks_picker_list()
  local picker = require("snacks").picker
  local all = picker.get({ tab = true })
  local current = vim.api.nvim_get_current_win()
  local selected = vim.iter(all):find(function(item)
    return item.list and item.list.win and item.list.win.win == current
  end) or all[#all]
  local paths = {}
  for _, item in ipairs(selected and selected:selected({ fallback = true }) or {}) do
    if present(item.file) then
      local ok, path = pcall(function()
        return picker.util.path(item)
      end)
      if not ok or not present(path) then
        path = item.cwd
            and not item.file:match("^[/\\]")
            and not item.file:match("^%a:[/\\]")
            and vim.fs.joinpath(item.cwd, item.file)
          or item.file
      end
      if on_disk(path) then
        add(paths, path)
      end
    end
  end
  return paths
end

function M.get_selected_files_from_tree()
  local kind = vim.bo.filetype
  local read = readers[kind]
  if not read then
    return nil, "Select a path in a supported file explorer."
  end
  local ok, paths = pcall(read)
  if not ok then
    require("codex.logger").debug("explorer", paths)
    return nil, "Could not read files from " .. kind .. "."
  end
  if #paths == 0 then
    return nil, "No file or directory selected."
  end
  return paths
end

return M
