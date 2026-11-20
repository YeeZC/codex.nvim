local M = {}

local agents = {
  codex = {
    name = "codex",
    label = "Codex",
    command = "codex",
    yolo_args = { "--dangerously-bypass-approvals-and-sandbox" },
    yolo_aliases = { "--dangerously-bypass-approvals-and-sandbox", "--yolo" },
    resume_args = { "resume", "--last" },
  },
  agy = {
    name = "agy",
    label = "Antigravity",
    command = "agy",
    yolo_args = { "--dangerously-skip-permissions" },
    yolo_aliases = { "--dangerously-skip-permissions" },
    resume_args = { "--continue" },
  },
  cursor = {
    name = "cursor",
    label = "Cursor",
    command = "agent",
    yolo_args = { "--force" },
    yolo_aliases = { "--force", "-f", "--yolo" },
    resume_args = { "--continue" },
  },
}

function M.get(name)
  if name == nil then
    name = "codex"
  end
  assert(type(name) == "string" and agents[name], 'agent must be "codex", "agy" or "cursor"')
  return vim.deepcopy(agents[name])
end

-- Insert flags before positional arguments and the end-of-options delimiter.
function M.launch_args(agent, base, extra, yolo, resume)
  local argv = vim.list_slice(base)
  if resume then
    vim.list_extend(argv, agent.resume_args)
  end
  vim.list_extend(argv, extra)
  if yolo then
    local insert_at = #base + 1
    for index = 2, #argv do
      if argv[index] == "--" then
        insert_at = math.min(insert_at, index)
        break
      end
      if vim.tbl_contains(agent.yolo_aliases, argv[index]) then
        return argv
      end
    end
    for index, flag in ipairs(agent.yolo_args) do
      table.insert(argv, insert_at + index - 1, flag)
    end
  end
  return argv
end

return M
