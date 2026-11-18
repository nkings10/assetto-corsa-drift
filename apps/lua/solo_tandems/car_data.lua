-- Steering lock, steer ratio, and tyre size from the lead car's own files.
-- Full lock at the front tyre is the lock divided by the ratio.
-- A missing ratio, or an angle outside 15 to 70 degrees, keeps 32 degrees.

local M = {}

M.DEFAULT_LOCK = 450
M.DEFAULT_RADIUS = 0.33
M.FALLBACK_TYRE_ANGLE = 32
M.MIN_TYRE_ANGLE = 15
M.MAX_TYRE_ANGLE = 70

local function parse_ini(text)
  local sections = {}
  local current = nil
  if type(text) ~= 'string' then return sections end
  for line in text:gmatch('[^\r\n]+') do
    local name = line:match('^%s*%[([^%]]+)%]')
    if name then
      current = name:upper()
      sections[current] = sections[current] or {}
    elseif current ~= nil and not line:match('^%s*;') and not line:match('^%s*//') then
      local key, val = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
      if key then sections[current][key:upper()] = val end
    end
  end
  return sections
end

local function in_range(value, low, high)
  return type(value) == 'number' and value > low and value < high
end

function M.tyre_angle(lock, ratio)
  if type(lock) ~= 'number' or type(ratio) ~= 'number' then return M.FALLBACK_TYRE_ANGLE end
  local span = math.abs(ratio)
  if span == 0 then return M.FALLBACK_TYRE_ANGLE end
  local angle = lock / span
  if angle < M.MIN_TYRE_ANGLE or angle > M.MAX_TYRE_ANGLE then return M.FALLBACK_TYRE_ANGLE end
  return angle
end

function M.parse(car_text, tyres_text)
  local spec = {
    steer_lock = M.DEFAULT_LOCK,
    radius_front = M.DEFAULT_RADIUS,
    radius_rear = M.DEFAULT_RADIUS,
  }
  local car = parse_ini(car_text)
  local controls = car.CONTROLS or {}
  local lock = tonumber(controls.STEER_LOCK)
  if in_range(lock, 0, 2000) then spec.steer_lock = lock end
  local ratio = tonumber(controls.STEER_RATIO)
  if type(ratio) == 'number' and ratio ~= 0 then spec.steer_ratio = ratio end
  spec.tyre_angle = M.tyre_angle(spec.steer_lock, spec.steer_ratio)
  local tyres = parse_ini(tyres_text)
  local front = tonumber((tyres.FRONT or {}).RADIUS)
  local rear = tonumber((tyres.REAR or {}).RADIUS)
  if in_range(front, 0.05, 1) then spec.radius_front = front end
  if in_range(rear, 0.05, 1) then spec.radius_rear = rear end
  return spec
end

local function read_text(path)
  if io == nil or io.open == nil then return nil end
  local file = io.open(path, 'r')
  if file == nil then return nil end
  local text = file:read('*a')
  file:close()
  return text
end

local function ini_number(ini, section, key)
  if ini == nil or ini.get == nil then return nil end
  local value = nil
  pcall(function()
    value = ini:get(section, key, 0)
  end)
  return tonumber(value)
end

function M.load(folder)
  if type(folder) ~= 'string' or folder == '' then
    return M.parse(nil, nil)
  end
  local spec = M.parse(
    read_text(folder .. '/data/car.ini'),
    read_text(folder .. '/data/tyres.ini')
  )
  if ac == nil or ac.INIConfig == nil or ac.INIFormat == nil then
    return spec
  end
  local function load_ini(name)
    local ini = nil
    pcall(function()
      ini = ac.INIConfig.load(folder .. '/data/' .. name, ac.INIFormat.DefaultAcd)
    end)
    return ini
  end
  local car_ini = load_ini('car.ini')
  local lock = ini_number(car_ini, 'CONTROLS', 'STEER_LOCK')
  local ratio = ini_number(car_ini, 'CONTROLS', 'STEER_RATIO')
  local front = ini_number(load_ini('tyres.ini'), 'FRONT', 'RADIUS')
  local rear = ini_number(load_ini('tyres.ini'), 'REAR', 'RADIUS')
  if in_range(lock, 0, 2000) then spec.steer_lock = lock end
  if type(ratio) == 'number' and ratio ~= 0 then spec.steer_ratio = ratio end
  if in_range(front, 0.05, 1) then spec.radius_front = front end
  if in_range(rear, 0.05, 1) then spec.radius_rear = rear end
  spec.tyre_angle = M.tyre_angle(spec.steer_lock, spec.steer_ratio)
  return spec
end

return M
