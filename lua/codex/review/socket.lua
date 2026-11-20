-- Relay the TUI's WebSocket over a private Unix socket. The TUI still owns
-- initialization and every request other than a file decision made in Neovim.
local M = {}
local bit = require("bit")
local uv = vim.uv
local max_payload = 64 * 1024 * 1024

local function mask_bytes(payload, mask)
  local index = 0
  return (
    payload:gsub(".", function(char)
      local byte = bit.bxor(char:byte(), mask:byte(index % 4 + 1))
      index = index + 1
      return string.char(byte)
    end)
  )
end

local function decision_frame(message)
  local payload = vim.json.encode(message)
  local size = #payload
  local mask = assert(uv.random(4))
  local header = size < 126 and string.char(129, 128 + size)
    or string.char(129, 254, math.floor(size / 256), size % 256)
  return header .. mask .. mask_bytes(payload, mask)
end

local function pop_frame(input, masked)
  local first, second = input:byte(1, 2)
  if not second then
    return
  end
  assert(bit.band(first, 112) == 0 and (second >= 128) == masked, "Unexpected Codex WebSocket frame")
  local size, offset = bit.band(second, 127), 3
  if size >= 126 then
    offset = size == 126 and 5 or 11
    if #input < offset - 1 then
      return
    end
    size = 0
    for index = 3, offset - 1 do
      size = size * 256 + input:byte(index)
    end
  end
  assert(size <= max_payload, "Oversized Codex WebSocket frame")
  local first_payload = offset + (masked and 4 or 0)
  local last = first_payload + size - 1
  if #input < last then
    return
  end
  return bit.band(first, 15), first >= 128, first_payload, last
end

local function relay(target, masked, inspect)
  local input, headers_done = "", false
  local fragments, fragment_size
  local queued = {}
  local function receive(data)
    input = input .. data
    if not headers_done then
      local _, ending = input:find("\r\n\r\n", 1, true)
      if not ending then
        assert(#input < 32768, "Oversized Codex WebSocket handshake")
        return
      end
      assert(target:write(input:sub(1, ending)))
      input = input:sub(ending + 1)
      headers_done = true
    end
    while input ~= "" do
      local opcode, final, first, last = pop_frame(input, masked)
      if not opcode then
        break
      end
      local forward = true
      if opcode == 1 or opcode == 0 then
        if opcode == 1 then
          assert(not fragments, "Unexpected Codex WebSocket text frame")
          fragments, fragment_size = {}, 0
        end
        assert(fragments, "Unexpected Codex WebSocket continuation")
        local payload = input:sub(first, last)
        if masked then
          payload = mask_bytes(payload, input:sub(first - 4, first - 1))
        end
        fragment_size = fragment_size + #payload
        assert(fragment_size <= max_payload, "Oversized Codex WebSocket message")
        fragments[#fragments + 1] = payload
        if final then
          forward = inspect(table.concat(fragments), opcode == 1) ~= false
          fragments = nil
        end
      end
      if forward then
        assert(target:write(input:sub(1, last)))
      end
      input = input:sub(last + 1)
    end
    if not fragments and #queued > 0 then
      for _, bytes in ipairs(queued) do
        assert(target:write(bytes))
      end
      queued = {}
    end
  end
  return receive,
    function(bytes)
      if fragments then
        queued[#queued + 1] = bytes
        return true
      end
      return target:write(bytes) ~= nil
    end
end

function M.listen(path, upstream, on_message, on_close)
  local listener = assert(uv.new_pipe(false))
  local tui, server
  local inject
  local closed = false
  local sent = {}

  local function close(reason)
    if closed then
      return
    end
    closed = true
    listener:close()
    if tui then
      tui:close()
    end
    if server then
      server:close()
    end
    if reason ~= nil then
      vim.schedule(function()
        on_close(reason)
      end)
    end
  end

  local function read(source, receive)
    source:read_start(function(err, data)
      if closed then
        return
      end
      if not data then
        close(err or false)
      else
        local ok, reason = pcall(receive, data)
        if not ok then
          close(reason)
        end
      end
    end)
  end

  local function inspect_tui(bytes, single_frame)
    local ok, message = pcall(vim.json.decode, bytes)
    if ok and type(message) == "table" and not message.method and message.id ~= nil then
      if sent[message.id] and single_frame then
        return false
      end
      vim.schedule(function()
        on_message(message, true)
      end)
    end
  end

  local function inspect_server(bytes)
    local ok, message = pcall(vim.json.decode, bytes)
    if ok and type(message) == "table" then
      local params = message.params
      if message.method == "serverRequest/resolved" and type(params) == "table" and params.requestId ~= nil then
        sent[params.requestId] = nil
      end
      vim.schedule(function()
        if not closed then
          on_message(message, false)
        end
      end)
    end
  end

  local ok, err = pcall(function()
    assert(listener:bind(path))
    assert(listener:listen(1, function(error)
      if error then
        close(error)
        return
      end
      local peer = assert(uv.new_pipe(false))
      if not listener:accept(peer) or tui then
        peer:close()
        return
      end
      tui = peer
      server = assert(uv.new_pipe(false))
      server:connect(upstream, function(why)
        if closed then
          return
        end
        if why then
          close(why)
          return
        end
        read(server, relay(tui, false, inspect_server))
        local receive
        receive, inject = relay(server, true, inspect_tui)
        read(tui, receive)
      end)
    end))
  end)
  if not ok then
    close()
    error(err, 0)
  end

  return {
    close = function()
      close()
    end,
    send = function(message)
      if closed or not inject or not inject(decision_frame(message)) then
        return false
      end
      sent[message.id] = true
      return true
    end,
  }
end

return M
