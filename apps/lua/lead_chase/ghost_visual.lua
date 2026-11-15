-- Visual lead: KN5 in the scene with animated wheels, brake glow, and light smoke.
-- No physics car — avoids setCarPosition wiping wheel/light state.

local M = {}

local node = nil
local ready = false
local loaded_id = nil
local status = 'idle'

local wheel_mat = { nil, nil, nil, nil }
local tyre_mat = { nil, nil, nil, nil }
local wheel_orig = { nil, nil, nil, nil }
local tyre_orig = { nil, nil, nil, nil }
local spin = { 0, 0, 0, 0 }
local steer_smooth = 0

local brake_meshes = nil
local brake_on = false
local light_l = nil
local light_r = nil

local smoke = nil
local smoke_t = 0

local function v3(t, fallback)
  if t == nil then return fallback or vec3(0, 0, 0) end
  return vec3(t.x or 0, t.y or 0, t.z or 0)
end

local function speed_ms(vel)
  if vel == nil then return 0 end
  return math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
end

local function find_largest_kn5(folder)
  if io == nil or io.scanDir == nil then return nil end
  local files = io.scanDir(folder, '*.kn5')
  if files == nil or #files == 0 then return nil end
  local best, best_size = nil, -1
  for i = 1, #files do
    local name = files[i]
    local lower = name:lower()
    if not lower:find('collider', 1, true)
      and not lower:find('driver', 1, true)
      and not lower:find('crew', 1, true) then
      local path = folder .. '/' .. name
      local size = io.fileSize and (io.fileSize(path) or 0) or 0
      if size > best_size then
        best_size = size
        best = name
      end
    end
  end
  return best
end

local function kn5_candidates(car_id)
  local cars = ac.getFolder(ac.FolderID.ContentCars)
  if type(cars) ~= 'string' or cars == '' then return {} end
  local folder = cars .. '/' .. car_id
  local names = { car_id .. '.kn5' }
  local base = car_id:match('_([^_]+_[^_]+_[^_]+)$')
    or car_id:match('_([^_]+_[^_]+)$')
    or car_id:match('_([^_]+)$')
  if base then names[#names + 1] = base .. '.kn5' end
  names[#names + 1] = 'body.kn5'
  local largest = find_largest_kn5(folder)
  if largest then names[#names + 1] = largest end
  local paths = {}
  local seen = {}
  for i = 1, #names do
    local path = folder .. '/' .. names[i]
    if not seen[path] then
      seen[path] = true
      if io == nil or io.fileExists == nil or io.fileExists(path) then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function cache_matrix(root, names)
  for i = 1, #names do
    local ok, ref = pcall(function()
      return root:findNodes(names[i])
    end)
    if ok and ref ~= nil and (type(ref) ~= 'table' or #ref > 0) then
      local mok, mat = pcall(function()
        return ref:getTransformationRaw()
      end)
      if mok and mat ~= nil then
        local orig = mat4x4()
        orig:set(mat)
        return mat, orig
      end
    end
  end
  return nil, nil
end

local function find_wheels(root)
  local wheel_names = {
    { 'WHEEL_LF', 'wheel_lf' },
    { 'WHEEL_RF', 'wheel_rf' },
    { 'WHEEL_LR', 'wheel_lr' },
    { 'WHEEL_RR', 'wheel_rr' },
  }
  local tyre_names = {
    { 'TYRE_LF', 'tyre_lf', 'TIRE_LF', 'tire_lf' },
    { 'TYRE_RF', 'tyre_rf', 'TIRE_RF', 'tire_rf' },
    { 'TYRE_LR', 'tyre_lr', 'TIRE_LR', 'tire_lr' },
    { 'TYRE_RR', 'tyre_rr', 'TIRE_RR', 'tire_rr' },
  }
  for i = 1, 4 do
    wheel_mat[i], wheel_orig[i] = cache_matrix(root, wheel_names[i])
    tyre_mat[i], tyre_orig[i] = cache_matrix(root, tyre_names[i])
  end
end

local function find_brake_meshes(root)
  brake_meshes = nil
  local patterns = {
    '{ ?BRAKE? , ?brake? , actsAsBrakeLights:yes }',
    '{ ?LIGHT_BRAKE? , ?light_brake? }',
    '{ ?REAR_LIGHT? , ?rear_light? }',
  }
  for i = 1, #patterns do
    local ok, meshes = pcall(function()
      return root:findMeshes(patterns[i])
    end)
    if ok and meshes ~= nil and #meshes > 0 then
      pcall(function()
        meshes:ensureUniqueMaterials()
      end)
      brake_meshes = meshes
      return
    end
  end
end

local function ensure_lights()
  if light_l ~= nil or ac.LightSource == nil then return end
  local ok1, l = pcall(ac.LightSource, ac.LightType.Regular)
  local ok2, r = pcall(ac.LightSource, ac.LightType.Regular)
  if ok1 and l ~= nil then
    l.color = rgb(40, 0, 0)
    l.range = 5
    l.spot = 90
    l.spotSharpness = 0.2
    l.shadows = false
    l.position = vec3(0, -1000, 0)
    light_l = l
  end
  if ok2 and r ~= nil then
    r.color = rgb(40, 0, 0)
    r.range = 5
    r.spot = 90
    r.spotSharpness = 0.2
    r.shadows = false
    r.position = vec3(0, -1000, 0)
    light_r = r
  end
end

-- Apply Y steer then X spin onto a live matrix from its original basis (row1/2/3).
local function apply_spin_steer(mat, orig, spin_rad, steer_rad)
  if mat == nil or orig == nil then return end
  local ox1, oy1, oz1 = orig.row1.x, orig.row1.y, orig.row1.z
  local ox2, oy2, oz2 = orig.row2.x, orig.row2.y, orig.row2.z
  local ox3, oy3, oz3 = orig.row3.x, orig.row3.y, orig.row3.z
  local cos_s, sin_s = math.cos(steer_rad), math.sin(steer_rad)
  local rx = ox1 * cos_s + ox3 * sin_s
  local ry = oy1 * cos_s + oy3 * sin_s
  local rz = oz1 * cos_s + oz3 * sin_s
  local fx = -ox1 * sin_s + ox3 * cos_s
  local fy = -oy1 * sin_s + oy3 * cos_s
  local fz = -oz1 * sin_s + oz3 * cos_s
  local ux, uy, uz = ox2, oy2, oz2
  local cos_r, sin_r = math.cos(spin_rad), math.sin(spin_rad)
  mat.row1.x, mat.row1.y, mat.row1.z = rx, ry, rz
  mat.row2.x = ux * cos_r + fx * sin_r
  mat.row2.y = uy * cos_r + fy * sin_r
  mat.row2.z = uz * cos_r + fz * sin_r
  mat.row3.x = -ux * sin_r + fx * cos_r
  mat.row3.y = -uy * sin_r + fy * cos_r
  mat.row3.z = -uz * sin_r + fz * cos_r
end

local function copy_orig(mat, orig)
  if mat == nil or orig == nil then return end
  mat.row1.x, mat.row1.y, mat.row1.z, mat.row1.w = orig.row1.x, orig.row1.y, orig.row1.z, orig.row1.w
  mat.row2.x, mat.row2.y, mat.row2.z, mat.row2.w = orig.row2.x, orig.row2.y, orig.row2.z, orig.row2.w
  mat.row3.x, mat.row3.y, mat.row3.z, mat.row3.w = orig.row3.x, orig.row3.y, orig.row3.z, orig.row3.w
end

local function set_brake_visual(on, pose)
  ensure_lights()
  if on and not brake_on then
    brake_on = true
    if brake_meshes ~= nil then
      pcall(function()
        brake_meshes:setMaterialProperty('ksEmissive', 50)
        brake_meshes:setMaterialProperty('ksDiffuse', 0)
        brake_meshes:setMaterialProperty('ksAmbient', 12.5)
      end)
    end
  elseif not on and brake_on then
    brake_on = false
    if brake_meshes ~= nil then
      pcall(function()
        brake_meshes:setMaterialProperty('ksEmissive', 0)
        brake_meshes:setMaterialProperty('ksDiffuse', 1)
        brake_meshes:setMaterialProperty('ksAmbient', 0)
      end)
    end
  end
  if light_l == nil then return end
  if not on or pose == nil then
    light_l.position = vec3(0, -1000, 0)
    if light_r then light_r.position = vec3(0, -1000, 0) end
    return
  end
  local pos = v3(pose.pos)
  local look = v3(pose.dir, vec3(0, 0, 1))
  if look:length() > 0.001 then look:normalize() else look = vec3(0, 0, 1) end
  local up = v3(pose.up, vec3(0, 1, 0))
  if up:length() > 0.001 then up:normalize() else up = vec3(0, 1, 0) end
  local side = vec3(look.z * up.y - look.y * up.z, look.x * up.z - look.z * up.x, look.y * up.x - look.x * up.y)
  if side:length() < 0.001 then
    side = vec3(look.z, 0, -look.x)
  end
  if side:length() < 0.001 then side = vec3(1, 0, 0) else side:normalize() end
  local rear = pos - look * 2.0 + up * 0.5
  local dir = (-look - up * 0.1):normalize()
  light_l.position = rear + side * 0.55
  light_l.direction = dir
  if light_r then
    light_r.position = rear - side * 0.55
    light_r.direction = dir
  end
end

local function ensure_smoke()
  if smoke ~= nil or ac.Particles == nil or ac.Particles.Smoke == nil then return end
  local ok, emitter = pcall(ac.Particles.Smoke, {
    color = rgbm(0.85, 0.85, 0.85, 0.5),
    size = 0.4,
    life = 1.0,
    temperature = 0.15,
  })
  if ok then smoke = emitter end
end

local function update_smoke(pose, dt)
  ensure_smoke()
  if smoke == nil or pose == nil then return end
  local speed_kmh = speed_ms(pose.vel) * 3.6
  local steer = math.abs(pose.steer or 0)
  smoke_t = smoke_t + (dt or 0)
  if speed_kmh < 25 or steer < 0.2 or smoke_t < 0.03 then return end
  smoke_t = 0
  local pos = v3(pose.pos)
  local look = v3(pose.dir, vec3(0, 0, 1))
  if look:length() > 0.001 then look:normalize() else look = vec3(0, 0, 1) end
  local up = v3(pose.up, vec3(0, 1, 0))
  if up:length() > 0.001 then up:normalize() else up = vec3(0, 1, 0) end
  local side = vec3(look.z * up.y - look.y * up.z, look.x * up.z - look.z * up.x, look.y * up.x - look.x * up.y)
  if side:length() < 0.001 then side = vec3(1, 0, 0) else side:normalize() end
  local vel = v3(pose.vel)
  for _, sign in ipairs({ -1, 1 }) do
    local p = pos - look * 1.15 + side * (0.7 * sign) + up * 0.05
    pcall(function()
      smoke:emit(p, vel * 0.15 + side * (sign * 1.5), 0.4 + steer * 0.5)
    end)
  end
end

function M.status()
  return status
end

function M.ready()
  return ready
end

function M.ensure(car_id)
  if car_id == nil or car_id == '' then
    status = 'no car id'
    return false
  end
  if ready and loaded_id == car_id and node ~= nil then
    return true
  end
  ready = false
  loaded_id = car_id
  if node ~= nil then
    pcall(function()
      node:setPosition(vec3(0, -1000, 0))
    end)
  end
  node = nil
  local paths = kn5_candidates(car_id)
  if #paths == 0 then
    status = 'kn5 missing'
    return false
  end
  local ok_root, cars_root = pcall(ac.findNodes, 'carsRoot:yes')
  if not ok_root or cars_root == nil then
    status = 'no carsRoot'
    return false
  end
  local ok_node, created = pcall(function()
    return cars_root:createBoundingSphereNode('LeadChaseGhost', 12)
  end)
  if not ok_node or created == nil then
    status = 'node failed'
    return false
  end
  node = created
  pcall(function()
    node:setVirtualCarFlag(true)
  end)
  local loaded = nil
  local path = nil
  for i = 1, #paths do
    path = paths[i]
    local ok_load, meshes = pcall(function()
      return node:loadKN5(path)
    end)
    if ok_load and meshes ~= nil and #meshes > 0 then
      loaded = meshes
      break
    end
  end
  if loaded == nil then
    status = 'load failed'
    pcall(function()
      node:setPosition(vec3(0, -1000, 0))
    end)
    return false
  end
  pcall(function()
    loaded:ensureUniqueMaterials()
  end)
  find_wheels(node)
  find_brake_meshes(node)
  node:setPosition(vec3(0, -1000, 0))
  ready = true
  status = 'ok ' .. tostring(path:match('[^/\\]+$') or path)
  return true
end

function M.hide()
  if node ~= nil then
    pcall(function()
      node:setPosition(vec3(0, -1000, 0))
    end)
  end
  set_brake_visual(false, nil)
  spin[1], spin[2], spin[3], spin[4] = 0, 0, 0, 0
  steer_smooth = 0
end

function M.show(pose, dt)
  if pose == nil or node == nil or not ready then
    M.hide()
    return
  end
  dt = dt or 0.016
  if dt > 0.1 then dt = 0.1 end
  if dt < 0 then dt = 0 end

  local pos = v3(pose.pos)
  local look = v3(pose.dir, vec3(0, 0, 1))
  if look:length() > 0.001 then look:normalize() else look = vec3(0, 0, 1) end
  local up = v3(pose.up, vec3(0, 1, 0))
  if up:length() > 0.001 then up:normalize() else up = vec3(0, 1, 0) end

  node:setPosition(pos)
  node:setOrientation(look, up)

  local target_steer = (pose.steer or 0) * math.rad(32)
  steer_smooth = steer_smooth + (target_steer - steer_smooth) * math.min(1, dt * 10)

  local spd = speed_ms(pose.vel)
  local radius = 0.33
  for i = 1, 4 do
    local omega = pose.wheels and pose.wheels[i] or 0
    if math.abs(omega) < 0.01 then
      omega = spd / radius
    end
    if spd < 0.3 then omega = 0 end
    spin[i] = (spin[i] + omega * dt) % 6.283185307179586
    if spd < 0.3 then spin[i] = 0 end
    local steer = (i <= 2) and steer_smooth or 0
    local has_tyre = tyre_mat[i] ~= nil and tyre_orig[i] ~= nil
    if has_tyre then
      copy_orig(wheel_mat[i], wheel_orig[i])
      apply_spin_steer(tyre_mat[i], tyre_orig[i], spin[i], steer)
    elseif wheel_mat[i] and wheel_orig[i] then
      apply_spin_steer(wheel_mat[i], wheel_orig[i], spin[i], steer)
    end
  end

  set_brake_visual((pose.brake or 0) > 0.05, pose)
  update_smoke(pose, dt)
end

return M
