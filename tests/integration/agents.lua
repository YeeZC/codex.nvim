vim.opt.runtimepath:prepend(vim.fn.getcwd())
local agents = require("codex.agents")

assert(agents.get().command == "codex")
assert(agents.get("agy").command == "agy")
assert(agents.get("cursor").command == "agent")
assert(not pcall(agents.get, "unknown"))
assert(not pcall(agents.get, {}))
assert(not pcall(agents.get, false))
for _, name in ipairs({ "codex", "agy", "cursor" }) do
  local agent = agents.get(name)
  local base = { agent.command, "--model", "model with spaces; $literal" }
  local extra = { "--", "prompt; literal" }
  local expected = vim.list_extend(vim.list_slice(base), agent.yolo_args)
  vim.list_extend(expected, extra)
  assert(vim.deep_equal(agents.launch_args(agent, base, extra, true), expected))
  assert(#base == 3 and #extra == 2, "Launch must not mutate configured arguments")
  local delimited = { agent.command, "--", "--yolo" }
  expected = { agent.command }
  vim.list_extend(expected, agent.yolo_args)
  vim.list_extend(expected, { "--", "--yolo" })
  assert(vim.deep_equal(agents.launch_args(agent, delimited, {}, true), expected))
  for _, alias in ipairs(agent.yolo_aliases) do
    assert(vim.deep_equal(agents.launch_args(agent, { agent.command, alias }, {}, true), { agent.command, alias }))
    assert(vim.deep_equal(agents.launch_args(agent, { agent.command }, { alias }, true), { agent.command, alias }))
  end
end
print("PASS agent defaults, argument boundaries and YOLO aliases")
