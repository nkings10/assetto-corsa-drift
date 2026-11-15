-- Parse a car's lights.ini (+ extension light configs) for lead visuals.
-- Focused port of the TandemGhost lights path: mesh names, color, local pose, spot params.

local M = {}

local function parse_vec3(str)
  if not str or str == '' then return nil end
  local x, y, z = str:match('([%d%.%-eE]+)%s*[,;]%s*([%d%.%-eE]+)%s*[,;]%s*([%d%.%-eE]+)')
  if x then return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 } end
  return nil
end

local function normalize_color(c)
  if c == nil then return nil end
  local cx, cy, cz = c.x or 0, c.y or 0, c.z or 0
  local max_val = math.max(cx, cy, cz)
  if max_val <= 0 then return { r = 0, g = 0, b = 0 } end
  if max_val <= 1 then return { r = cx, g = cy, b = cz } end
  if max_val <= 255 then return { r = cx / 255, g = cy / 255, b = cz / 255 } end
  return { r = cx / max_val, g = cy / max_val, b = cz / max_val }
end

local function color_magnitude(c)
  if c == nil then return 0 end
  return math.max(c.x or 0, c.y or 0, c.z or 0)
end

local function empty_data()
  return {
    headlights = {},
    taillights = {},
    brakelights = {},
    headlight_entries = {},
    taillight_entries = {},
    brake_entries = {},
  }
end

local function dedup(list)
  local seen, out = {}, {}
  for i = 1, #list do
    local v = list[i]
    if type(v) == 'string' and v ~= '' and not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  return out
end

local function read_record_from_ini(ini, section)
  local rec = {}
  local mesh = ''
  pcall(function()
    mesh = ini:get(section, 'NAME', '')
  end)
  if mesh == '' then
    pcall(function()
      mesh = ini:get(section, 'MESH', '')
    end)
  end
  rec.mesh = mesh or ''

  local function read_str(key)
    local s = ''
    pcall(function()
      s = ini:get(section, key, '')
    end)
    if s == '' then return nil end
    return s
  end

  local function read_num(key)
    local s = read_str(key)
    if not s then return nil end
    return tonumber(s)
  end

  rec.color_raw = parse_vec3(read_str('COLOR'))
  rec.color = normalize_color(rec.color_raw)
  rec.color_intensity = color_magnitude(rec.color_raw)
  rec.off_color_raw = parse_vec3(read_str('OFF_COLOR'))
  rec.off_color = normalize_color(rec.off_color_raw)
  rec.position = parse_vec3(read_str('POSITION'))
  rec.direction = parse_vec3(read_str('DIRECTION'))
  rec.spot = read_num('SPOT')
  rec.spot_sharpness = read_num('SPOT_SHARPNESS')
  rec.range = read_num('RANGE')
  rec.specular_mult = read_num('SPECULAR_MULT')
  rec.fade_at = read_num('FADE_AT')
  rec.fade_smooth = read_num('FADE_SMOOTH')
  return rec
end

local function parse_ext_color(str)
  if not str or str == '' or str == '0' then return nil, 0 end
  local parts = {}
  for v in str:gmatch('[%d%.%-eE]+') do
    parts[#parts + 1] = tonumber(v) or 0
  end
  if #parts < 3 then return nil, 0 end
  local r, g, b = parts[1], parts[2], parts[3]
  local mult = parts[4] or 1
  local intensity = math.max(r, g, b) * mult
  local max_comp = math.max(r, g, b)
  if max_comp > 0 then
    return { r = r / max_comp, g = g / max_comp, b = b / max_comp }, intensity
  end
  return { r = 0, g = 0, b = 0 }, 0
end

local function read_extension(car_folder, result)
  if type(car_folder) ~= 'string' or car_folder == '' or io == nil or io.open == nil then
    return
  end

  local function parse_ext_file(path, file_type)
    local f = io.open(path, 'r')
    if f == nil then return end
    local content = f:read('*a')
    f:close()
    if type(content) ~= 'string' then return end

    local sections, current = {}, nil
    for line in content:gmatch('[^\r\n]+') do
      local section_name = line:match('^%[([^%]]+)%]')
      if section_name then
        current = { name = section_name, lines = {} }
        sections[#sections + 1] = current
      elseif current then
        current.lines[#current.lines + 1] = line
      end
    end

    for _, sec in ipairs(sections) do
      local sec_upper = sec.name:upper()
      local kv = {}
      for _, line in ipairs(sec.lines) do
        if not line:match('^%s*;') and not line:match('^%s*//') then
          local key, val = line:match('^%s*(%S+)%s*=%s*(.-)%s*$')
          if key then kv[key:upper()] = val end
        end
      end

      local color, intensity = parse_ext_color(kv.COLOR)
      local entry = {
        mesh = kv.NAME or '',
        color = color,
        color_intensity = intensity or 0,
        position = parse_vec3(kv.POSITION),
        direction = parse_vec3(kv.DIRECTION),
        range = tonumber(kv.RANGE),
        spot = tonumber(kv.SPOT),
        spot_sharpness = tonumber(kv.SPOT_SHARPNESS),
        specular_mult = tonumber(kv.SPECULAR_MULT),
        fade_at = tonumber(kv.FADE_AT),
        fade_smooth = tonumber(kv.FADE_SMOOTH),
        source = 'extension',
      }

      if sec_upper:find('LIGHT_BRAKE', 1, true) then
        result.brake_entries[#result.brake_entries + 1] = entry
        if entry.mesh ~= '' then
          for name in entry.mesh:gmatch('[^,%s]+') do
            result.brakelights[#result.brakelights + 1] = name
          end
        end
      elseif sec_upper:find('LIGHT_HEADLIGHT', 1, true) then
        result.headlight_entries[#result.headlight_entries + 1] = entry
        if entry.mesh ~= '' then
          for name in entry.mesh:gmatch('[^,%s]+') do
            result.headlights[#result.headlights + 1] = name
          end
        end
      elseif file_type == 'taillights' and sec_upper:find('EMISSIVE', 1, true) then
        local brake_color, brake_intensity = parse_ext_color(kv.FALLBACK_BRAKES_COLOR)
        if kv.NAME then
          for name in kv.NAME:gmatch('[^,%s]+') do
            local lo = name:lower()
            if lo:find('brake', 1, true) or lo:find('stop', 1, true) then
              result.brakelights[#result.brakelights + 1] = name
            else
              result.taillights[#result.taillights + 1] = name
              if brake_color then
                result.brakelights[#result.brakelights + 1] = name
              end
            end
          end
        end
        if brake_color then
          result.brake_entries[#result.brake_entries + 1] = {
            mesh = kv.NAME or '',
            color = brake_color,
            color_intensity = brake_intensity or 0,
            source = 'extension',
          }
        end
        if color then
          result.taillight_entries[#result.taillight_entries + 1] = {
            mesh = kv.NAME or '',
            color = color,
            color_intensity = intensity or 0,
            source = 'extension',
          }
        end
      end
    end
  end

  pcall(parse_ext_file, car_folder .. '/extension/headlights.ini', 'headlights')
  pcall(parse_ext_file, car_folder .. '/extension/taillights.ini', 'taillights')
end

function M.load(car_folder)
  local result = empty_data()
  if type(car_folder) ~= 'string' or car_folder == '' then
    return result
  end

  local lights_ini = nil
  if ac ~= nil and ac.INIConfig ~= nil then
    pcall(function()
      lights_ini = ac.INIConfig.load(car_folder .. '/data/lights.ini', ac.INIFormat.DefaultAcd)
    end)
  end

  if lights_ini ~= nil and lights_ini.iterate ~= nil then
    for index, section in lights_ini:iterate('LIGHT') do
      local rec = read_record_from_ini(lights_ini, section)
      if rec.mesh ~= '' then
        local desc = ''
        pcall(function()
          desc = lights_ini:get(section, 'DESCRIPTION', '')
        end)
        desc = tostring(desc):upper()
        local mesh_upper = rec.mesh:upper()
        local is_head = desc:find('HEAD', 1, true) or desc:find('FRONT', 1, true)
          or mesh_upper:find('HEADLIGHT', 1, true) or mesh_upper:find('HEAD_LIGHT', 1, true)
        local is_tail = desc:find('TAIL', 1, true) or desc:find('REAR', 1, true)
          or mesh_upper:find('TAILLIGHT', 1, true) or mesh_upper:find('TAIL_LIGHT', 1, true)
        if not is_head and not is_tail and rec.direction then
          local dz = tonumber(rec.direction.z) or 0
          if dz > 0.3 then is_head = true elseif dz < -0.3 then is_tail = true end
        end
        if not is_head and not is_tail and index <= 1 then is_head = true end
        if is_head then
          result.headlights[#result.headlights + 1] = rec.mesh
          result.headlight_entries[#result.headlight_entries + 1] = rec
        elseif is_tail then
          result.taillights[#result.taillights + 1] = rec.mesh
          result.taillight_entries[#result.taillight_entries + 1] = rec
        end
      end
    end

    for _, section in lights_ini:iterate('BRAKE') do
      local rec = read_record_from_ini(lights_ini, section)
      if rec.mesh ~= '' then
        result.brakelights[#result.brakelights + 1] = rec.mesh
        result.brake_entries[#result.brake_entries + 1] = rec
        if rec.off_color then
          result.taillights[#result.taillights + 1] = rec.mesh
          result.taillight_entries[#result.taillight_entries + 1] = rec
        end
      end
    end
  end

  read_extension(car_folder, result)

  result.headlights = dedup(result.headlights)
  result.taillights = dedup(result.taillights)
  result.brakelights = dedup(result.brakelights)
  return result
end

function M.entry_light_color(entry, base_scale)
  base_scale = base_scale or 40
  if entry == nil then return rgb(base_scale, 0, 0) end
  local c = entry.color or { r = 1, g = 0.02, b = 0.02 }
  local mag = entry.color_intensity or 255
  local factor = math.max(mag / 255, 1)
  return rgb((c.r or 1) * base_scale * factor, (c.g or 0) * base_scale * factor, (c.b or 0) * base_scale * factor)
end

function M.brake_emissive(entry)
  local intensity = 50
  if entry ~= nil and (entry.color_intensity or 0) > 0 then
    intensity = math.min(entry.color_intensity / 255 * 50, 300)
  end
  return intensity
end

function M.glow_color(entry, scale)
  scale = scale or 0.8
  local c = (entry and entry.color) or { r = 1, g = 0.02, b = 0.02 }
  return rgbm((c.r or 1) * scale, (c.g or 0.02) * scale, (c.b or 0.02) * scale, 1)
end

return M
