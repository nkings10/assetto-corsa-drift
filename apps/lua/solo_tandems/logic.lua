-- Recording and chase rules. No Custom Shaders Patch calls, so the tests can run it.

local M = {}

M.RECORD = 'record'
M.SPAWN = 'spawn'
M.CHASE = 'chase'
M.TELEPORT = 'teleport'
M.START = 'start'
M.CLEAR = 'clear'

local MAX_SECONDS = 15 * 60
local SAMPLE_INTERVAL = 1 / 30

local function copy3(v)
  return { x = v.x, y = v.y, z = v.z }
end

local function length(v)
  return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function normalize(v)
  local len = length(v)
  if len < 0.0001 then return { x = 0, y = 0, z = 1 } end
  return { x = v.x / len, y = v.y / len, z = v.z / len }
end

local function lerp3(a, b, u)
  return {
    x = a.x + (b.x - a.x) * u,
    y = a.y + (b.y - a.y) * u,
    z = a.z + (b.z - a.z) * u,
  }
end

local function copy_wheels(wheels)
  if wheels == nil then return { 0, 0, 0, 0 } end
  return {
    wheels[1] or 0,
    wheels[2] or 0,
    wheels[3] or 0,
    wheels[4] or 0,
  }
end

local function lerp_wheels(a, b, u)
  a = a or { 0, 0, 0, 0 }
  b = b or { 0, 0, 0, 0 }
  return {
    a[1] + (b[1] - a[1]) * u,
    a[2] + (b[2] - a[2]) * u,
    a[3] + (b[3] - a[3]) * u,
    a[4] + (b[4] - a[4]) * u,
  }
end

local function copy_up(up)
  if up == nil then return { x = 0, y = 1, z = 0 } end
  return normalize(up)
end

local function copy_side(side, dir, up)
  if side ~= nil then return normalize(side) end
  dir = dir or { x = 0, y = 0, z = 1 }
  up = up or { x = 0, y = 1, z = 0 }
  return normalize({
    x = dir.z * up.y - dir.y * up.z,
    y = dir.x * up.z - dir.z * up.x,
    z = dir.y * up.x - dir.x * up.y,
  })
end

local function vec_ok(v)
  return type(v) == 'table'
    and type(v.x) == 'number'
    and type(v.y) == 'number'
    and type(v.z) == 'number'
end

local function pose_copy(pose)
  local dir = normalize(pose.dir)
  local up = copy_up(pose.up)
  return {
    pos = copy3(pose.pos),
    dir = dir,
    up = up,
    side = copy_side(pose.side, dir, up),
    vel = copy3(pose.vel or { x = 0, y = 0, z = 0 }),
    brake = pose.brake or 0,
    steer = pose.steer or 0,
    gas = pose.gas or 0,
    rpm = pose.rpm or 0,
    gear = pose.gear or 0,
    drift = pose.drift or 0,
    speed = pose.speed or 0,
    wheels = copy_wheels(pose.wheels),
  }
end

local function hold_pose(sample)
  return {
    pos = copy3(sample.pos),
    dir = copy3(sample.dir),
    up = copy_up(sample.up),
    side = copy_side(sample.side, sample.dir, sample.up),
    vel = { x = 0, y = 0, z = 0 },
    brake = 0,
    steer = sample.steer or 0,
    gas = 0,
    rpm = math.min(sample.rpm or 900, 900),
    gear = sample.gear or 0,
    drift = 0,
    speed = 0,
    wheels = { 0, 0, 0, 0 },
  }
end

function M.create()
  return {
    recording = false,
    samples = {},
    elapsed = 0,
    placed = false,
    playing = false,
    play_t = 0,
    play_i = 1,
    chase_start = nil,
    pulse = nil,
    notice = 'Ready',
  }
end

function M.has_lead_run(state)
  return #state.samples > 0
end

local function stop_playback(state)
  state.playing = false
  state.play_t = 0
  state.play_i = 1
end

local function hide_lead_car(state)
  state.placed = false
  stop_playback(state)
end

function M.handle(state, action, ctx)
  ctx = ctx or {}
  local can_move = ctx.can_move ~= false
  state.pulse = nil

  if action == M.RECORD then
    if state.recording then
      state.recording = false
      if #state.samples == 0 then
        state.notice = 'Recording is empty'
      else
        state.notice = 'Lead run saved'
      end
      return state
    end
    state.recording = true
    state.samples = {}
    state.elapsed = 0
    state.sample_slot = nil
    hide_lead_car(state)
    state.notice = 'Recording'
    return state
  end

  if action == M.CLEAR then
    state.recording = false
    state.samples = {}
    state.elapsed = 0
    hide_lead_car(state)
    state.notice = 'Lead run cleared'
    return state
  end

  if action == M.CHASE then
    if ctx.pose == nil then
      state.notice = 'No car to mark'
      return state
    end
    local pose = pose_copy(ctx.pose)
    state.chase_start = { pos = pose.pos, dir = pose.dir }
    state.notice = 'Chase car set'
    return state
  end

  if state.recording then
    state.notice = 'Stop the recording first'
    return state
  end

  if action == M.SPAWN then
    if #state.samples == 0 then
      state.notice = 'No lead run recorded'
      return state
    end
    state.placed = true
    stop_playback(state)
    state.notice = 'Lead is waiting'
    return state
  end

  if action == M.START then
    if not state.placed then
      state.notice = 'Spawn the lead car first'
      return state
    end
    state.playing = true
    state.play_t = 0
    state.play_i = 1
    state.notice = 'Lead is running'
    return state
  end

  if action == M.TELEPORT then
    if state.chase_start == nil then
      state.notice = 'Set the chase car first'
      return state
    end
    if not can_move then
      state.notice = 'Extended physics is off'
      return state
    end
    state.pulse = 'teleport'
    if #state.samples == 0 then
      state.notice = 'Teleported'
      return state
    end
    state.placed = true
    stop_playback(state)
    state.notice = 'Teleported. Lead is waiting'
    return state
  end

  state.notice = 'Unknown action'
  return state
end

function M.capture(state, dt, pose)
  if not state.recording or pose == nil then return end
  dt = dt or 0
  if dt < 0 then dt = 0 end
  if state.elapsed + dt > MAX_SECONDS then
    state.recording = false
    state.notice = '15 minute recording limit reached'
    return
  end
  state.elapsed = state.elapsed + dt
  if state.elapsed >= MAX_SECONDS - 60 then
    local left = math.ceil(MAX_SECONDS - state.elapsed - 1e-9)
    if left < 1 then left = 1 end
    local unit = 'seconds'
    if left == 1 then unit = 'second' end
    state.notice = left .. ' ' .. unit .. ' of recording left'
  end
  local slot = math.floor(state.elapsed / SAMPLE_INTERVAL + 1e-9)
  if state.sample_slot ~= nil and slot <= state.sample_slot then
    return
  end
  state.sample_slot = slot
  local sample = pose_copy(pose)
  sample.t = state.elapsed
  state.samples[#state.samples + 1] = sample
end

function M.lead_position(state, dt)
  if not state.placed or #state.samples == 0 then
    return nil, 'hidden'
  end
  if not state.playing then
    return hold_pose(state.samples[1]), 'hold'
  end
  dt = dt or 0
  if dt < 0 then dt = 0 end
  if dt > 0.1 then dt = 0.1 end
  state.play_t = state.play_t + dt
  local samples = state.samples
  local first = samples[1]
  local last = samples[#samples]
  if state.play_t <= first.t then
    return {
      pos = copy3(first.pos),
      dir = copy3(first.dir),
      up = copy_up(first.up),
      side = copy_side(first.side, first.dir, first.up),
      vel = copy3(first.vel),
      brake = first.brake or 0,
      steer = first.steer or 0,
      gas = first.gas or 0,
      rpm = first.rpm or 0,
      gear = first.gear or 0,
      drift = first.drift or 0,
      speed = first.speed or 0,
      wheels = copy_wheels(first.wheels),
    }, 'play'
  end
  if last.t - state.play_t <= 0.0001 then
    state.playing = false
    state.play_t = 0
    state.play_i = 1
    state.notice = 'Lead ready'
    return hold_pose(first), 'hold'
  end
  local t = state.play_t
  local i = state.play_i or 1
  if i < 1 or i > #samples or samples[i].t > t then i = 1 end
  while i < #samples and samples[i + 1].t < t do
    i = i + 1
  end
  state.play_i = i
  local a = samples[i]
  local b = samples[i + 1] or a
  local span = b.t - a.t
  local u = span > 0 and (t - a.t) / span or 0
  local dir = normalize(lerp3(a.dir, b.dir, u))
  local up = normalize(lerp3(a.up or { x = 0, y = 1, z = 0 }, b.up or { x = 0, y = 1, z = 0 }, u))
  return {
    pos = lerp3(a.pos, b.pos, u),
    dir = dir,
    up = up,
    side = normalize(lerp3(
      a.side or copy_side(nil, a.dir, a.up),
      b.side or copy_side(nil, b.dir, b.up),
      u
    )),
    vel = lerp3(a.vel, b.vel, u),
    brake = (a.brake or 0) + ((b.brake or 0) - (a.brake or 0)) * u,
    steer = (a.steer or 0) + ((b.steer or 0) - (a.steer or 0)) * u,
    gas = (a.gas or 0) + ((b.gas or 0) - (a.gas or 0)) * u,
    rpm = (a.rpm or 0) + ((b.rpm or 0) - (a.rpm or 0)) * u,
    gear = a.gear or 0,
    drift = (a.drift or 0) + ((b.drift or 0) - (a.drift or 0)) * u,
    speed = (a.speed or 0) + ((b.speed or 0) - (a.speed or 0)) * u,
    wheels = lerp_wheels(a.wheels, b.wheels, u),
  }, 'play'
end

local function escape_str(s)
  s = tostring(s or '')
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  return '"' .. s .. '"'
end

local function encode_json(value)
  local t = type(value)
  if t == 'nil' then
    return 'null'
  end
  if t == 'boolean' then
    return value and 'true' or 'false'
  end
  if t == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then
      return '0'
    end
    return string.format('%.6g', value)
  end
  if t == 'string' then
    return escape_str(value)
  end
  if t ~= 'table' then
    return 'null'
  end
  local is_array = true
  local max_n = 0
  for k, _ in pairs(value) do
    if type(k) ~= 'number' or k < 1 or k ~= math.floor(k) then
      is_array = false
      break
    end
    if k > max_n then max_n = k end
  end
  if is_array and (max_n == #value or max_n == 0) then
    local parts = {}
    for i = 1, #value do
      parts[i] = encode_json(value[i])
    end
    return '[' .. table.concat(parts, ',') .. ']'
  end
  local parts = {}
  for k, v in pairs(value) do
    if type(k) == 'string' then
      parts[#parts + 1] = escape_str(k) .. ':' .. encode_json(v)
    end
  end
  table.sort(parts)
  return '{' .. table.concat(parts, ',') .. '}'
end

local function skip_ws(s, i)
  while true do
    local c = s:sub(i, i)
    if c ~= ' ' and c ~= '\n' and c ~= '\r' and c ~= '\t' then
      return i
    end
    i = i + 1
    if i > #s then return i end
  end
end

local function parse_json(s, i)
  i = skip_ws(s, i or 1)
  local c = s:sub(i, i)
  if c == '"' then
    local out = {}
    i = i + 1
    while i <= #s do
      local ch = s:sub(i, i)
      if ch == '"' then
        return table.concat(out), i + 1
      end
      if ch == '\\' then
        local n = s:sub(i + 1, i + 1)
        if n == 'n' then out[#out + 1] = '\n'
        elseif n == 'r' then out[#out + 1] = '\r'
        elseif n == 't' then out[#out + 1] = '\t'
        else out[#out + 1] = n end
        i = i + 2
      else
        out[#out + 1] = ch
        i = i + 1
      end
    end
    return nil, i
  end
  if c == '{' then
    local obj = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while i <= #s do
      local key
      key, i = parse_json(s, i)
      if type(key) ~= 'string' then return nil, i end
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ':' then return nil, i end
      local val
      val, i = parse_json(s, i + 1)
      obj[key] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == '}' then return obj, i + 1 end
      if sep ~= ',' then return nil, i end
      i = skip_ws(s, i + 1)
    end
    return nil, i
  end
  if c == '[' then
    local arr = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while i <= #s do
      local val
      val, i = parse_json(s, i)
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == ']' then return arr, i + 1 end
      if sep ~= ',' then return nil, i end
      i = skip_ws(s, i + 1)
    end
    return nil, i
  end
  if s:sub(i, i + 3) == 'true' then return true, i + 4 end
  if s:sub(i, i + 4) == 'false' then return false, i + 5 end
  if s:sub(i, i + 3) == 'null' then return nil, i + 4 end
  local num, rest = s:match('^([%-]?%d+%.?%d*[eE]?[%+%-]?%d*)()', i)
  if num then return tonumber(num), rest end
  return nil, i
end

function M.pack(state, meta)
  meta = meta or {}
  if state == nil or #state.samples == 0 then
    return nil, 'No lead run recorded'
  end
  local samples = {}
  for i = 1, #state.samples do
    local s = state.samples[i]
    samples[i] = pose_copy(s)
    samples[i].t = s.t or 0
  end
  return {
    version = 1,
    kind = 'solo_tandems',
    carId = meta.carId or '',
    trackId = meta.trackId or '',
    sampleCount = #samples,
    samples = samples,
  }
end

function M.encode(payload)
  if payload == nil then return nil end
  return encode_json(payload)
end

function M.decode(text)
  if type(text) ~= 'string' or text == '' then
    return nil, 'Empty file'
  end
  local data = select(1, parse_json(text, 1))
  if type(data) ~= 'table' then
    return nil, 'Bad file'
  end
  return data
end

function M.apply_pack(state, payload, opts)
  opts = opts or {}
  if state == nil or type(payload) ~= 'table' then
    return nil, 'Bad data'
  end
  if payload.kind ~= 'solo_tandems' then
    return nil, 'Not a Solo Tandems file'
  end
  local file_track = tostring(payload.trackId or '')
  local current_track = tostring(opts.trackId or '')
  if file_track ~= '' and current_track ~= '' and file_track ~= current_track then
    return nil, 'Not loading. Needs track: ' .. file_track
  end
  local samples_in = payload.samples
  if type(samples_in) ~= 'table' or #samples_in == 0 then
    return nil, 'No samples in file'
  end
  local samples = {}
  local elapsed = 0
  for i = 1, #samples_in do
    local raw = samples_in[i]
    if type(raw) ~= 'table' or not vec_ok(raw.pos) or not vec_ok(raw.dir) then
      return nil, 'Bad file'
    end
    local s = pose_copy(raw)
    s.t = raw.t or elapsed
    if s.t > elapsed then elapsed = s.t end
    samples[i] = s
  end
  state.recording = false
  state.samples = samples
  state.elapsed = elapsed
  hide_lead_car(state)
  state.notice = 'Lead run imported'
  return {
    carId = payload.carId or '',
    trackId = file_track,
  }
end

function M.sync_deck(link, remote_seq)
  if link.seen ~= true then
    link.seen = true
    link.seq = remote_seq
    return false
  end
  if remote_seq == link.seq then
    return false
  end
  link.seq = remote_seq
  return true
end

return M
