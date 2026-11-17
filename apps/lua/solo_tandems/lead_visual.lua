-- Visual lead: KN5 lead with wheels, discs, steer wheel, lights, smoke, wipers, ground snap, wetness, sound.

local M = {}

local function sibling(name)
  local folder = 'apps/lua/solo_tandems/'
  if ac.getFolder and ac.FolderID and ac.FolderID.ACApps then
    local apps = ac.getFolder(ac.FolderID.ACApps)
    if type(apps) == 'string' and apps ~= '' then
      folder = apps .. '/lua/solo_tandems/'
    end
  end
  return dofile(folder .. name)
end

local model_notice = sibling('model_notice.lua')
local car_lights = sibling('car_lights.lua')
local car_data = sibling('car_data.lua')
local wetness = sibling('wetness.lua')
local height = sibling('height.lua')
local wipers = sibling('wipers.lua')
local smoke = sibling('smoke.lua')
local light_data = nil

local node = nil
local all_meshes = nil
local ready = false
local loaded_id = nil
local car_folder = nil
local car_spec = {
  steer_lock = car_data.DEFAULT_LOCK,
  radius_front = car_data.DEFAULT_RADIUS,
  radius_rear = car_data.DEFAULT_RADIUS,
}
local status = 'idle'
local was_hidden = true
local ground_offset = nil
local height_state = nil

local wheel_mat = { nil, nil, nil, nil }
local tyre_mat = { nil, nil, nil, nil }
local disc_mat = { nil, nil, nil, nil }
local wheel_orig = { nil, nil, nil, nil }
local tyre_orig = { nil, nil, nil, nil }
local disc_orig = { nil, nil, nil, nil }
local wheel_ref = { nil, nil, nil, nil }
local tyre_ref = { nil, nil, nil, nil }
local spin = { 0, 0, 0, 0 }
local steer_smooth = 0

local steer_mat = nil
local steer_orig = nil

local wiper_nodes = {}
local wiper_ksanim = nil

local brake_meshes = nil
local head_meshes = nil
local tail_meshes = nil
local exterior_meshes = nil
local tyre_meshes = nil
local brake_on = false
local lights_on = false
local beams_on = false
local tails_on = false
local beam_state = ''
local reverse_meshes = nil
local left_meshes = nil
local right_meshes = nil
local wet_applied = false
local last_wet = -1
local wet_saved = nil

local brake_l, brake_r = nil, nil
local head_l, head_r, tail_light = nil, nil, nil

local smoke_main, smoke_heavy, smoke_push = nil, nil, nil
local smoke_clock = 0
local smoke_pos = vec3()
local smoke_vel = vec3()

local sound = nil
local sound_bank = nil
local sound_id = nil
local smooth_rpm = 900
local smooth_gas = 0

local glow_brake = {
  meshes = nil,
  values = { gGlowColor = rgbm(1.5, 0.05, 0.02, 1) },
  cacheKey = 'soloTandemsBrkGlow',
  defines = [[
    float4 main(PS_IN pin) {
      return float4(gGlowColor.rgb, 1);
    }
  ]],
}
local glow_head = {
  meshes = nil,
  values = { gGlowColor = rgbm(1.5, 1.5, 1.35, 1) },
  cacheKey = 'soloTandemsHLGlow',
  defines = [[
    float4 main(PS_IN pin) {
      return float4(gGlowColor.rgb, 1);
    }
  ]],
}
local glow_tail = {
  meshes = nil,
  values = { gGlowColor = rgbm(0.6, 0.01, 0.01, 1) },
  cacheKey = 'soloTandemsTLGlow',
  defines = [[
    float4 main(PS_IN pin) {
      return float4(gGlowColor.rgb, 1);
    }
  ]],
}

local function v3(t, fallback)
  if t == nil then return fallback or vec3(0, 0, 0) end
  return vec3(t.x or 0, t.y or 0, t.z or 0)
end

local function speed_ms(vel)
  if vel == nil then return 0 end
  return math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
end

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
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
  if type(cars) ~= 'string' or cars == '' then return {}, nil end
  local folder = cars .. '/' .. car_id
  local names = { car_id .. '.kn5' }
  local base = car_id:match('_([^_]+_[^_]+_[^_]+)$')
    or car_id:match('_([^_]+_[^_]+)$')
    or car_id:match('_([^_]+)$')
  if base then names[#names + 1] = base .. '.kn5' end
  names[#names + 1] = 'body.kn5'
  local largest = find_largest_kn5(folder)
  if largest then names[#names + 1] = largest end
  local paths, seen = {}, {}
  for i = 1, #names do
    local path = folder .. '/' .. names[i]
    if not seen[path] then
      seen[path] = true
      if io == nil or io.fileExists == nil or io.fileExists(path) then
        paths[#paths + 1] = path
      end
    end
  end
  return paths, folder
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
        return mat, orig, ref
      end
    end
  end
  return nil, nil, nil
end

local function find_parts(root)
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
  local disc_names = {
    { 'BRAKE_DISC_LF', 'DISC_LF', 'disk_lf', 'BRAKE_DISC_FL', 'DISC_FL' },
    { 'BRAKE_DISC_RF', 'DISC_RF', 'disk_rf', 'BRAKE_DISC_FR', 'DISC_FR' },
    { 'BRAKE_DISC_LR', 'DISC_LR', 'disk_lr', 'BRAKE_DISC_RL', 'DISC_RL' },
    { 'BRAKE_DISC_RR', 'DISC_RR', 'disk_rr', 'BRAKE_DISC_RR' },
  }
  for i = 1, 4 do
    wheel_mat[i], wheel_orig[i], wheel_ref[i] = cache_matrix(root, wheel_names[i])
    tyre_mat[i], tyre_orig[i], tyre_ref[i] = cache_matrix(root, tyre_names[i])
    disc_mat[i], disc_orig[i] = cache_matrix(root, disc_names[i])
  end
  steer_mat, steer_orig = cache_matrix(root, {
    'STEER_HR', 'STEER', 'steer_hr', 'steer', 'Steer_HR', 'Steer',
  })

  wiper_nodes = {}
  wiper_ksanim = nil
  local wiper_names = { 'WIPER_LEFT', 'WIPER_RIGHT', 'WIPER_L', 'WIPER_R', 'Wiper_L', 'Wiper_R', 'wiper_l', 'wiper_r' }
  for i = 1, #wiper_names do
    local mat, orig = cache_matrix(root, { wiper_names[i] })
    if mat and orig then
      wiper_nodes[#wiper_nodes + 1] = { mat = mat, orig = orig }
    end
  end
  if car_folder ~= nil and io ~= nil and io.dirExists ~= nil then
    local anim_dir = car_folder .. '/animations'
    if io.dirExists(anim_dir) and io.scanDir ~= nil then
      local files = io.scanDir(anim_dir, '*.ksanim')
      if files then
        for i = 1, #files do
          local lower = files[i]:lower()
          if lower:find('wiper', 1, true) then
            wiper_ksanim = anim_dir .. '/' .. files[i]
            break
          end
        end
      end
    end
  end
end

local function find_named_meshes(root, names)
  if root == nil or names == nil or #names == 0 then return nil end
  local ok, meshes = pcall(function()
    return root:findMeshes(names)
  end)
  if ok and meshes ~= nil and #meshes > 0 then
    pcall(function()
      meshes:ensureUniqueMaterials()
    end)
    return meshes
  end
  return nil
end

local function clear_wet_state()
  wet_saved = nil
  wet_applied = false
  last_wet = -1
end

local function find_meshes(root)
  clear_wet_state()
  local function grab(patterns)
    for i = 1, #patterns do
      local ok, meshes = pcall(function()
        return root:findMeshes(patterns[i])
      end)
      if ok and meshes ~= nil and #meshes > 0 then
        pcall(function()
          meshes:ensureUniqueMaterials()
        end)
        return meshes
      end
    end
    return nil
  end

  light_data = car_lights.load(car_folder)
  brake_meshes = find_named_meshes(root, light_data.brakelights)
  head_meshes = find_named_meshes(root, light_data.headlights)
  tail_meshes = find_named_meshes(root, light_data.taillights)
  reverse_meshes = find_named_meshes(root, light_data.reverse)
  left_meshes = find_named_meshes(root, light_data.turn_left)
  right_meshes = find_named_meshes(root, light_data.turn_right)

  if head_meshes == nil then
    head_meshes = grab({
      '{ ?HEADLIGHT? , ?headlight? , ?HEAD_LIGHT? }',
      '{ ?FRONT_LIGHT? , ?front_light? }',
    })
  end
  if tail_meshes == nil then
    tail_meshes = grab({
      '{ ?TAILLIGHT? , ?taillight? , ?TAIL_LIGHT? }',
      '{ ?REAR_LIGHT? , ?rear_light? }',
    })
  end
  if brake_meshes == nil then
    brake_meshes = grab({
      '{ actsAsBrakeLights:yes }',
      '{ ?LIGHT_BRAKE? , ?light_brake? , ?BRAKE_LIGHT? , ?brake_light? }',
      '{ ?STOPLIGHT? , ?stop_light? , ?STOP_LIGHT? }',
    })
  end

  local ok_all, meshes = pcall(function()
    return root:findMeshes('?')
  end)
  all_meshes = (ok_all and meshes) or nil
  exterior_meshes = all_meshes
  if brake_meshes == nil and all_meshes ~= nil then
    local names = {}
    for i = 1, #all_meshes do
      local mesh_name = nil
      pcall(function()
        mesh_name = all_meshes:name(i)
      end)
      if type(mesh_name) == 'string' then
        local lo = mesh_name:lower()
        local skip = lo:find('disc', 1, true) or lo:find('disk', 1, true)
          or lo:find('rotor', 1, true) or lo:find('caliper', 1, true)
          or lo:find('pad', 1, true) or lo:find('tyre', 1, true)
          or lo:find('tire', 1, true) or lo:find('rim', 1, true)
        local hit = lo:find('brakelight', 1, true) or lo:find('brake_light', 1, true)
          or lo:find('light_brake', 1, true) or lo:find('stoplight', 1, true)
          or lo:find('stop_light', 1, true) or lo:find('ref_bl', 1, true)
          or lo:find('ref_br', 1, true)
        if hit and not skip then
          names[#names + 1] = mesh_name
        end
      end
    end
    brake_meshes = find_named_meshes(root, names)
  end
  if brake_meshes == nil then
    brake_meshes = tail_meshes
  end
  tyre_meshes = grab({ '{ ?TYRE? , ?tyre? , ?TIRE? , ?tire? }' })

  local brk_entry = light_data.brake_entries[1]
  local hl_entry = light_data.headlight_entries[1]
  local tl_entry = light_data.taillight_entries[1]
  glow_brake.values.gGlowColor = car_lights.glow_color(brk_entry, 0.8)
  glow_head.values.gGlowColor = car_lights.glow_color(hl_entry or { color = { r = 1, g = 1, b = 0.9 } }, 1.5)
  glow_tail.values.gGlowColor = car_lights.glow_color(tl_entry or { color = { r = 0.6, g = 0.01, b = 0.01 } }, 0.6)
  glow_brake.meshes = brake_meshes
  glow_head.meshes = head_meshes
  glow_tail.meshes = tail_meshes
  if render ~= nil and render.BlendMode ~= nil then
    glow_brake.blendMode = render.BlendMode.BlendAdd
    glow_head.blendMode = render.BlendMode.BlendAdd
    glow_tail.blendMode = render.BlendMode.BlendAdd
  end
  if render ~= nil and render.DepthMode ~= nil then
    glow_brake.depthMode = render.DepthMode.ReadOnly
    glow_head.depthMode = render.DepthMode.ReadOnly
    glow_tail.depthMode = render.DepthMode.ReadOnly
  end
end

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

local function apply_steer_wheel(angle)
  if steer_mat == nil or steer_orig == nil then return end
  local orig = steer_orig
  local m = steer_mat
  local cos_a, sin_a = math.cos(angle), math.sin(angle)
  local ox1, oy1, oz1 = orig.row1.x, orig.row1.y, orig.row1.z
  local ox2, oy2, oz2 = orig.row2.x, orig.row2.y, orig.row2.z
  m.row1.x = ox1 * cos_a + ox2 * sin_a
  m.row1.y = oy1 * cos_a + oy2 * sin_a
  m.row1.z = oz1 * cos_a + oz2 * sin_a
  m.row2.x = -ox1 * sin_a + ox2 * cos_a
  m.row2.y = -oy1 * sin_a + oy2 * cos_a
  m.row2.z = -oz1 * sin_a + oz2 * cos_a
  m.row3.x, m.row3.y, m.row3.z = orig.row3.x, orig.row3.y, orig.row3.z
end

local function apply_wiper_pose(progress, angle)
  if wiper_ksanim ~= nil and node ~= nil then
    pcall(function()
      node:setAnimation(wiper_ksanim, progress, true)
    end)
    return
  end
  local cos_w, sin_w = math.cos(angle), math.sin(angle)
  for i = 1, #wiper_nodes do
    local w = wiper_nodes[i]
    local orig, m = w.orig, w.mat
    local ox1, oy1, oz1 = orig.row1.x, orig.row1.y, orig.row1.z
    local ox2, oy2, oz2 = orig.row2.x, orig.row2.y, orig.row2.z
    m.row1.x = ox1 * cos_w + ox2 * sin_w
    m.row1.y = oy1 * cos_w + oy2 * sin_w
    m.row1.z = oz1 * cos_w + oz2 * sin_w
    m.row2.x = -ox1 * sin_w + ox2 * cos_w
    m.row2.y = -oy1 * sin_w + oy2 * cos_w
    m.row2.z = -oz1 * sin_w + oz2 * cos_w
    m.row3.x, m.row3.y, m.row3.z = orig.row3.x, orig.row3.y, orig.row3.z
  end
end

local function update_wipers(pose)
  local progress = wipers.progress(pose and pose.wipers)
  apply_wiper_pose(progress, wipers.angle(progress))
end

local function hide_light(light)
  if light ~= nil then light.position = vec3(0, -1000, 0) end
end

local function dispose_light(light)
  if light == nil then return end
  pcall(function()
    if light.dispose then light:dispose() end
  end)
end

local function dispose_brake_lights()
  dispose_light(brake_l)
  dispose_light(brake_r)
  brake_l, brake_r = nil, nil
end

local function dispose_running_lights()
  dispose_light(head_l)
  dispose_light(head_r)
  dispose_light(tail_light)
  head_l, head_r, tail_light = nil, nil, nil
  lights_on = false
end

local function head_emissive_level()
  local entry = light_data and light_data.headlight_entries[1] or nil
  return car_lights.head_emissive(entry)
end

local function tail_emissive_level()
  local entry = light_data and light_data.taillight_entries[1] or nil
  return car_lights.tail_emissive(entry)
end

local function apply_light_params(light, entry, defs)
  if light == nil then return end
  light.color = car_lights.entry_light_color(entry, defs.color_scale)
  light.specularMultiplier = (entry and entry.specular_mult) or defs.specular
  light.range = (entry and entry.range) or defs.range
  light.rangeGradientOffset = defs.range_grad or 0.2
  light.fadeAt = (entry and entry.fade_at) or defs.fade_at
  light.fadeSmooth = (entry and entry.fade_smooth) or defs.fade_smooth
  light.spot = (entry and entry.spot) or defs.spot
  light.spotSharpness = (entry and entry.spot_sharpness) or defs.spot_sharp
  light.shadows = false
  light.position = vec3(0, -1000, 0)
  light.direction = vec3(0, -0.1, -1)
end

local function ensure_brake_lights()
  if brake_l ~= nil then return end
  if ac.LightSource == nil then return end
  local entries = (light_data and light_data.brake_entries) or {}
  local e1 = entries[1]
  local e2 = entries[2] or entries[1]
  local defs = {
    color_scale = 40,
    specular = 0.8,
    range = 15,
    fade_at = 200,
    fade_smooth = 80,
    spot = 130,
    spot_sharp = 0.2,
  }
  local ok_l, left = pcall(ac.LightSource, ac.LightType.Regular)
  local ok_r, right = pcall(ac.LightSource, ac.LightType.Regular)
  if ok_l and left ~= nil then
    apply_light_params(left, e1, defs)
    brake_l = left
  end
  if ok_r and right ~= nil then
    apply_light_params(right, e2, defs)
    brake_r = right
  end
end

local function ensure_running_light_sources()
  if head_l ~= nil then return end
  if ac.LightSource == nil then return end
  local hl_entries = (light_data and light_data.headlight_entries) or {}
  local tl_entries = (light_data and light_data.taillight_entries) or {}
  local hl_defs = {
    color_scale = 8,
    specular = 1.0,
    range = 80,
    range_grad = 0.3,
    fade_at = 400,
    fade_smooth = 100,
    spot = 60,
    spot_sharp = 0.7,
  }
  local tl_defs = {
    color_scale = 60,
    specular = 0.5,
    range = 25,
    range_grad = 0.2,
    fade_at = 200,
    fade_smooth = 80,
    spot = 120,
    spot_sharp = 0.3,
  }
  local default_hl = { color = { r = 0.78, g = 0.78, b = 0.7 }, color_intensity = 255 }
  local default_tl = { color = { r = 0.04, g = 0, b = 0 }, color_intensity = 255 }
  local hl_l = hl_entries[1] or default_hl
  local hl_r = hl_entries[2] or hl_entries[1] or default_hl
  local tl_e = tl_entries[1] or default_tl
  local ok1, a = pcall(ac.LightSource, ac.LightType.Regular)
  local ok2, b = pcall(ac.LightSource, ac.LightType.Regular)
  local ok3, c = pcall(ac.LightSource, ac.LightType.Regular)
  if ok1 and a then
    apply_light_params(a, hl_l, hl_defs)
    head_l = a
  end
  if ok2 and b then
    apply_light_params(b, hl_r, hl_defs)
    head_r = b
  end
  if ok3 and c then
    apply_light_params(c, tl_e, tl_defs)
    tail_light = c
  end
end

local function set_emissive(meshes, on, intensity, ambient)
  if meshes == nil then return end
  if on then
    pcall(function()
      meshes:setMaterialProperty('ksEmissive', intensity)
      meshes:setMaterialProperty('ksDiffuse', 0)
      meshes:setMaterialProperty('ksAmbient', ambient or (intensity * 0.25))
    end)
  else
    pcall(function()
      meshes:setMaterialProperty('ksEmissive', 0)
      meshes:setMaterialProperty('ksDiffuse', 1)
      meshes:setMaterialProperty('ksAmbient', 0)
    end)
  end
end

local function apply_running_emissive()
  local hl = head_emissive_level()
  local tl = tail_emissive_level()
  set_emissive(head_meshes, true, hl, hl * 0.3)
  if not brake_on or brake_meshes ~= tail_meshes then
    set_emissive(tail_meshes, true, tl, tl * 0.25)
  end
end

local function set_running_lights(head_on, high_on)
  head_on = head_on == true
  high_on = high_on == true
  local key = (head_on and 'h' or '-') .. (high_on and 'H' or '-')
  if key == beam_state then return end
  beam_state = key
  beams_on = head_on or high_on
  tails_on = head_on
  lights_on = beams_on
  if beams_on then
    ensure_running_light_sources()
    local hl = head_emissive_level()
    if high_on then hl = hl * 1.6 end
    set_emissive(head_meshes, true, hl, hl * 0.3)
  else
    set_emissive(head_meshes, false, 0, 0)
    hide_light(head_l)
    hide_light(head_r)
  end
  if tails_on then
    if not brake_on or brake_meshes ~= tail_meshes then
      local tl = tail_emissive_level()
      set_emissive(tail_meshes, true, tl, tl * 0.25)
    end
  else
    if not brake_on then
      set_emissive(tail_meshes, false, 0, 0)
    end
    hide_light(tail_light)
  end
end

local function valid_local_pos(p)
  return p ~= nil and type(p.x) == 'number' and not (p.x == 0 and p.y == 0 and p.z == 0)
end

local function local_to_world(pos, look, up, side, local_pos)
  return pos + side * local_pos.x + up * local_pos.y + look * local_pos.z
end

local function local_dir_to_world(look, up, side, local_dir)
  if local_dir == nil then return (-look - up * 0.05):normalize() end
  return (side * local_dir.x + up * local_dir.y + look * local_dir.z):normalize()
end

local function update_running_lights(look, up, side, pos)
  if look == nil or up == nil or side == nil or pos == nil or (not beams_on and not tails_on) then
    hide_light(head_l)
    hide_light(head_r)
    hide_light(tail_light)
    return
  end
  ensure_running_light_sources()
  if not beams_on then
    hide_light(head_l)
    hide_light(head_r)
  end
  if not tails_on then
    hide_light(tail_light)
  end
  local hl_entries = (light_data and light_data.headlight_entries) or {}
  local tl_entries = (light_data and light_data.taillight_entries) or {}
  local size = vec3(1.8, 1.3, 4.5)
  local head_dir = (look - up * 0.08):normalize()

  if beams_on and head_l ~= nil and #hl_entries >= 2 and valid_local_pos(hl_entries[1].position) and valid_local_pos(hl_entries[2].position) then
    head_l.position = local_to_world(pos, look, up, side, hl_entries[1].position)
    head_l.direction = hl_entries[1].direction and local_dir_to_world(look, up, side, hl_entries[1].direction) or head_dir
    if head_r then
      head_r.position = local_to_world(pos, look, up, side, hl_entries[2].position)
      head_r.direction = hl_entries[2].direction and local_dir_to_world(look, up, side, hl_entries[2].direction) or head_dir
    end
  elseif beams_on and head_l ~= nil and #hl_entries >= 1 and valid_local_pos(hl_entries[1].position) then
    local lp = hl_entries[1].position
    local dir = hl_entries[1].direction and local_dir_to_world(look, up, side, hl_entries[1].direction) or head_dir
    head_l.position = local_to_world(pos, look, up, side, lp)
    head_l.direction = dir
    if head_r then
      head_r.position = local_to_world(pos, look, up, side, { x = -lp.x, y = lp.y, z = lp.z })
      head_r.direction = dir
    end
  elseif beams_on and head_l ~= nil then
    local front = pos + look * (size.z * 0.48) + up * (size.y * 0.42)
    local side_off = size.x * 0.35
    head_l.position = front + side * side_off
    head_l.direction = head_dir
    if head_r then
      head_r.position = front - side * side_off
      head_r.direction = head_dir
    end
  end

  if not tails_on or tail_light == nil then return end
  local avg_x, avg_y, avg_z, count = 0, 0, 0, 0
  for i = 1, #tl_entries do
    local e = tl_entries[i]
    if valid_local_pos(e.position) then
      avg_x = avg_x + e.position.x
      avg_y = avg_y + e.position.y
      avg_z = avg_z + e.position.z
      count = count + 1
    end
  end
  if count > 0 then
    local lp = { x = avg_x / count, y = avg_y / count, z = avg_z / count }
    tail_light.position = local_to_world(pos, look, up, side, lp)
    local dir_src = tl_entries[1] and tl_entries[1].direction or nil
    tail_light.direction = local_dir_to_world(look, up, side, dir_src)
  else
    tail_light.position = pos - look * (size.z * 0.48) + up * (size.y * 0.42)
    tail_light.direction = (-look - up * 0.05):normalize()
  end
end

local function set_brake_visual(on, look, up, side, pos)
  ensure_brake_lights()
  local entry = light_data and light_data.brake_entries[1] or nil
  if on ~= brake_on then
    brake_on = on
    local meshes = brake_meshes or tail_meshes
    if on then
      local intensity = car_lights.brake_emissive(entry)
      set_emissive(meshes, true, intensity, intensity * 0.25)
      glow_brake.values.gGlowColor = car_lights.glow_color(entry, 0.8)
    else
      -- Restore running-light emissive when headlights are on (TandemGhost behaviour).
      if lights_on and meshes == tail_meshes then
        local tl = tail_emissive_level()
        set_emissive(meshes, true, tl, tl * 0.25)
      else
        set_emissive(meshes, false, 0, 0)
        if lights_on and brake_meshes ~= nil and tail_meshes ~= nil and brake_meshes ~= tail_meshes then
          local tl = tail_emissive_level()
          set_emissive(tail_meshes, true, tl, tl * 0.25)
        end
      end
    end
  end
  if not on then
    hide_light(brake_l)
    hide_light(brake_r)
    return
  end
  if look == nil or pos == nil or side == nil or up == nil then return end

  local entries = (light_data and light_data.brake_entries) or {}
  local e1, e2 = entries[1], entries[2]
  if e1 ~= nil and valid_local_pos(e1.position) and e2 ~= nil and valid_local_pos(e2.position) then
    if brake_l then
      brake_l.position = local_to_world(pos, look, up, side, e1.position)
      brake_l.direction = local_dir_to_world(look, up, side, e1.direction)
    end
    if brake_r then
      brake_r.position = local_to_world(pos, look, up, side, e2.position)
      brake_r.direction = local_dir_to_world(look, up, side, e2.direction)
    end
  elseif e1 ~= nil and valid_local_pos(e1.position) then
    local lp = e1.position
    local dir = local_dir_to_world(look, up, side, e1.direction)
    if brake_l then
      brake_l.position = local_to_world(pos, look, up, side, lp)
      brake_l.direction = dir
    end
    if brake_r then
      brake_r.position = local_to_world(pos, look, up, side, { x = -lp.x, y = lp.y, z = lp.z })
      brake_r.direction = dir
    end
  else
    local size = vec3(1.8, 1.3, 4.5)
    local rear = pos - look * (size.z * 0.48) + up * (size.y * 0.42)
    local dir = (-look - up * 0.05):normalize()
    local side_off = size.x * 0.35
    if brake_l then
      brake_l.position = rear + side * side_off
      brake_l.direction = dir
    end
    if brake_r then
      brake_r.position = rear - side * side_off
      brake_r.direction = dir
    end
  end
end

local function ensure_smoke()
  if smoke_main ~= nil or ac.Particles == nil or ac.Particles.Smoke == nil then return end
  -- Same emitter params as TandemGhost (white FadeIn tyre smoke).
  local ok1, main = pcall(ac.Particles.Smoke, {
    color = rgbm(1, 1, 1, 0.3),
    colorConsistency = 0.3,
    thickness = 0.5,
    life = 5.0,
    size = 0.15,
    spreadK = 1.5,
    growK = 2.0,
    targetYVelocity = 0.05,
    flags = ac.Particles.SmokeFlags and ac.Particles.SmokeFlags.FadeIn or nil,
  })
  local ok2, heavy = pcall(ac.Particles.Smoke, {
    color = rgbm(1, 1, 1, 0.4),
    colorConsistency = 0.35,
    thickness = 0.6,
    life = 6.0,
    size = 0.2,
    spreadK = 1.8,
    growK = 2.5,
    targetYVelocity = 0.08,
    flags = ac.Particles.SmokeFlags and ac.Particles.SmokeFlags.FadeIn or nil,
  })
  if ok1 then smoke_main = main end
  if ok2 then smoke_heavy = heavy end
  if ac.Particles.Detractor ~= nil then
    local ok3, push = pcall(ac.Particles.Detractor, { radius = 2.0, forceMultiplier = 0.6 })
    if ok3 then smoke_push = push end
  end
end

local function wheel_world(index)
  local ref = tyre_ref[index] or wheel_ref[index]
  if ref == nil or ref.getWorldTransformationRaw == nil then return nil end
  local ok, wm = pcall(ref.getWorldTransformationRaw, ref)
  if not ok or wm == nil then return nil end
  local point = wm.row4 or wm.position
  if point == nil or type(point.x) ~= 'number' then return nil end
  return { x = point.x, y = point.y, z = point.z }
end

local function update_smoke(pose, look, side, pos, dt)
  ensure_smoke()
  if smoke_main == nil or pose == nil or pos == nil or look == nil or side == nil then return end
  local drift = math.abs(pose.drift or 0)
  local speed = pose.speed or (speed_ms(pose.vel) * 3.6)
  if smoke_push ~= nil then
    smoke_push.position = pos
    if pose.vel then smoke_push.velocity = v3(pose.vel) end
  end
  local now = os.preciseClock and os.preciseClock() or (smoke_clock + (dt or 0))
  -- Match TandemGhost: ~120 Hz, 5° / 12 km/h thresholds, multi-burst around each rear wheel.
  if drift <= 5 or speed <= 12 or now - smoke_clock < 0.008 then
    return
  end
  smoke_clock = now

  local intensity = clamp((drift - 5) / 35, 0, 1) * clamp((speed - 12) / 68, 0, 1)
  local wheel_r = smoke.radius()
  local vel = v3(pose.vel)
  local kick = speed * 0.012 * intensity
  local kick_x, kick_z = -look.x * kick, -look.z * kick
  local slip_sign = (pose.drift or 0) > 0 and -1 or 1
  local slip_x = side.x * slip_sign * speed * 0.006
  local slip_z = side.z * slip_sign * speed * 0.006

  local rl_x, rl_y, rl_z = smoke.contact(pos, look, side, wheel_world(3), 1, car_spec.radius_rear)
  local rr_x, rr_y, rr_z = smoke.contact(pos, look, side, wheel_world(4), -1, car_spec.radius_rear)

  local main_amount = 0.8 + intensity * 3.5
  for i = 1, 2 do
    local wx, wy, wz
    if i == 1 then
      wx, wy, wz = rl_x, rl_y, rl_z
    else
      wx, wy, wz = rr_x, rr_y, rr_z
    end
    local wc_x, wc_y, wc_z = wx, wy + wheel_r, wz
    for burst = 1, 3 do
      local angle
      if burst == 1 then
        angle = -math.pi / 2 + (math.random() - 0.5) * 1.2
      elseif burst == 2 then
        angle = math.pi * (0.5 + math.random() * 0.5)
      else
        angle = math.random() * math.pi * 2
      end
      local r_offset = wheel_r * (0.7 + math.random() * 0.6)
      local along = math.cos(angle) * r_offset
      local up = math.sin(angle) * r_offset
      local lateral = (math.random() - 0.5) * 0.4
      smoke_pos.x = wc_x - look.x * along + (math.random() - 0.5) * 0.15 + side.x * lateral
      smoke_pos.y = wc_y + up
      smoke_pos.z = wc_z - look.z * along + (math.random() - 0.5) * 0.15 + side.z * lateral
      if smoke_pos.y < wy then smoke_pos.y = wy end
      local out_x, out_y, out_z = smoke_pos.x - wc_x, smoke_pos.y - wc_y, smoke_pos.z - wc_z
      local out_len = math.sqrt(out_x * out_x + out_y * out_y + out_z * out_z) + 0.001
      local out_force = 0.5 + intensity * 1.0
      smoke_vel.x = vel.x * 0.35 + kick_x + slip_x + (out_x / out_len) * out_force + (math.random() - 0.5) * 0.6
      smoke_vel.y = 0.1 + math.random() * 0.2 + (out_y / out_len) * out_force * 0.3
      smoke_vel.z = vel.z * 0.35 + kick_z + slip_z + (out_z / out_len) * out_force + (math.random() - 0.5) * 0.6
      pcall(function()
        smoke_main:emit(smoke_pos, smoke_vel, main_amount * (0.7 + math.random() * 0.6))
      end)
    end
  end

  if intensity > 0.3 and smoke_heavy ~= nil then
    local heavy_amount = (intensity - 0.3) * 4.0
    for i = 1, 2 do
      local wx, wy, wz
      if i == 1 then
        wx, wy, wz = rl_x, rl_y, rl_z
      else
        wx, wy, wz = rr_x, rr_y, rr_z
      end
      local wc_x, wc_y, wc_z = wx, wy + wheel_r, wz
      for _ = 1, 2 do
        local angle = math.random() * math.pi * 2
        local r_offset = wheel_r * (0.5 + math.random() * 0.8)
        local along = math.cos(angle) * r_offset
        local up = math.sin(angle) * r_offset
        smoke_pos.x = wc_x - look.x * along + side.x * (math.random() - 0.5) * 0.5
        smoke_pos.y = math.max(wy, wc_y + up)
        smoke_pos.z = wc_z - look.z * along + side.z * (math.random() - 0.5) * 0.5
        local out_x, out_y, out_z = smoke_pos.x - wc_x, smoke_pos.y - wc_y, smoke_pos.z - wc_z
        local out_len = math.sqrt(out_x * out_x + out_y * out_y + out_z * out_z) + 0.001
        local out_force = 0.8 + intensity * 1.5
        smoke_vel.x = vel.x * 0.45 + kick_x * 1.3 + slip_x * 1.5 + (out_x / out_len) * out_force + (math.random() - 0.5) * 0.8
        smoke_vel.y = 0.15 + math.random() * 0.25 + (out_y / out_len) * out_force * 0.4
        smoke_vel.z = vel.z * 0.45 + kick_z * 1.3 + slip_z * 1.5 + (out_z / out_len) * out_force + (math.random() - 0.5) * 0.8
        pcall(function()
          smoke_heavy:emit(smoke_pos, smoke_vel, heavy_amount)
        end)
      end
    end
    if intensity > 0.6 then
      local c_x = (rl_x + rr_x) * 0.5
      local c_y = (rl_y + rr_y) * 0.5
      local c_z = (rl_z + rr_z) * 0.5
      smoke_pos.x = c_x - look.x * 0.2 + (math.random() - 0.5) * 0.4
      smoke_pos.y = c_y + math.random() * 0.06
      smoke_pos.z = c_z - look.z * 0.2 + (math.random() - 0.5) * 0.4
      smoke_vel.x = vel.x * 0.45 + kick_x * 1.5 + (math.random() - 0.5) * 0.6
      smoke_vel.y = 0.08 + math.random() * 0.2
      smoke_vel.z = vel.z * 0.45 + kick_z * 1.5 + (math.random() - 0.5) * 0.6
      pcall(function()
        smoke_heavy:emit(smoke_pos, smoke_vel, heavy_amount * 0.8)
      end)
    end
  end
end

local function world_y(ref)
  if ref == nil or ref.getWorldTransformationRaw == nil then return nil end
  local ok, y = pcall(function()
    local wm = ref:getWorldTransformationRaw()
    if wm == nil then return nil end
    if wm.row4 ~= nil and type(wm.row4.y) == 'number' then return wm.row4.y end
    if wm.position ~= nil and type(wm.position.y) == 'number' then return wm.position.y end
    return nil
  end)
  if ok and type(y) == 'number' then return y end
  return nil
end

local function compute_ground_offset()
  ground_offset = nil
  if node == nil then return end
  pcall(function()
    node:setPosition(vec3(0, 0, 0))
    node:setOrientation(vec3(0, 0, 1), vec3(0, 1, 0))
  end)
  local root_y = world_y(node) or 0
  local front, rear = {}, {}
  for i = 1, 4 do
    -- The wheel hub is the tyre centre. A tyre mesh pivot often sits higher, which buried the rubber.
    local ref = wheel_ref[i] or tyre_ref[i]
    local hub_y = world_y(ref)
    if hub_y ~= nil then
      local radius = i <= 2 and car_spec.radius_front or car_spec.radius_rear
      local offset = height.hub_offset(radius, hub_y, root_y)
      if offset ~= nil then
        local axle = i <= 2 and front or rear
        axle[#axle + 1] = offset
      end
    end
  end
  pcall(function()
    node:setPosition(vec3(0, -1000, 0))
    if node.clearMotion then node:clearMotion() end
  end)
  ground_offset = height.ride_offset(front, rear)
end

local function ray_distance(from, dir, length)
  if physics ~= nil and physics.raycastTrack ~= nil then
    local ok, dist = pcall(physics.raycastTrack, from, dir, length)
    if ok and type(dist) == 'number' and dist > 0.05 and dist < length - 0.05 then
      return dist
    end
  end
  if render == nil or render.createRay == nil then return nil end
  local ok, dist = pcall(function()
    local ray = render.createRay(from, dir, length)
    if ray == nil or ray.track == nil then return nil end
    return ray:track()
  end)
  if ok and type(dist) == 'number' and dist > 0.05 and dist < length - 0.05 then
    return dist
  end
  return nil
end

local function get_ground_y(world_pos)
  local from = vec3(world_pos.x, world_pos.y + 5, world_pos.z)
  local dist = ray_distance(from, vec3(0, -1, 0), 30)
  if dist == nil then return nil end
  return from.y - dist
end

local function snap_y(recorded_y, world_xz)
  local ground = nil
  if height_state == nil or height_state.gap == nil then
    ground = get_ground_y(vec3(world_xz.x, recorded_y, world_xz.z))
  end
  local y, state = height.step(height_state, recorded_y, ground, ground_offset)
  height_state = state
  return y
end

local function read_material(meshes, index, name)
  if meshes == nil or meshes.getMaterialPropertyValue == nil then return nil end
  local ok, value = pcall(meshes.getMaterialPropertyValue, meshes, index, name)
  if ok and type(value) == 'number' then return value end
  return nil
end

local function write_material(meshes, index, name, value)
  if meshes == nil or meshes.at == nil then return end
  local one = meshes:at(index)
  if one ~= nil and one.setMaterialProperty ~= nil then
    one:setMaterialProperty(name, value)
  end
end

local function update_wetness()
  if all_meshes == nil or ac.getSim == nil then return end
  local ok, sim = pcall(ac.getSim)
  if not ok or sim == nil then return end
  local wet = sim.rainWetness or 0
  local q = math.floor(wet * 100 + 0.5) / 100
  if q > 0.01 then
    if wet_saved == nil and exterior_meshes ~= nil then
      wet_saved = wetness.capture(exterior_meshes, tyre_meshes, read_material)
    end
    if q ~= last_wet then
      last_wet = q
      wet_applied = true
      pcall(function()
        if exterior_meshes then
          exterior_meshes:setMaterialProperty('ksSpecularEXP', 20 + wet * 80)
          exterior_meshes:setMaterialProperty('fresnelC', 0.04 + wet * 0.2)
        end
        if tyre_meshes then
          tyre_meshes:setMaterialProperty('fresnelC', 0.02)
        end
      end)
    end
  elseif wet_applied then
    wet_applied = false
    last_wet = -1
    pcall(function()
      local writes = wetness.restore_writes(wet_saved)
      if #writes > 0 then
        for i = 1, #writes do
          local item = writes[i]
          local meshes = item.group == 'tyre' and tyre_meshes or exterior_meshes
          pcall(write_material, meshes, item.index, item.prop, item.value)
        end
      elseif exterior_meshes then
        exterior_meshes:setMaterialProperty('ksSpecularEXP', 50)
        exterior_meshes:setMaterialProperty('fresnelC', 0.04)
      end
    end)
  end
end

local function stop_sound()
  if sound ~= nil then
    pcall(function()
      if sound.isValid and sound:isValid() then
        sound:stop()
        if sound.dispose then sound:dispose() end
      end
    end)
    sound = nil
  end
  sound_bank = nil
  sound_id = nil
  smooth_rpm = 900
  smooth_gas = 0
end

local function update_sound(pose, look, pos)
  if pose == nil then
    stop_sound()
    return
  end
  local car_id = loaded_id
  if car_id == nil then return end
  if sound_id ~= car_id then
    stop_sound()
  end
  if sound == nil then
    sound_id = car_id
    local sfx = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. car_id .. '/sfx/'
    pcall(function()
      sound_bank = ac.loadSoundbank(sfx .. car_id .. '.bank', sfx .. 'GUIDs.txt')
    end)
    local names = {
      'event:/cars/' .. car_id .. '/engine_ext',
      'event:/cars/' .. car_id .. '/engine',
      '/cars/' .. car_id .. '/engine_ext',
      '/cars/' .. car_id .. '/engine',
    }
    for i = 1, #names do
      local ok, snd = pcall(ac.AudioEvent, names[i], true)
      if ok and snd ~= nil and (snd.isValid == nil or snd:isValid()) then
        sound = snd
        pcall(function()
          sound.volume = 0.4
          sound:setPosition(pos, look, nil, v3(pose.vel))
          sound:start()
        end)
        break
      end
    end
  end
  if sound == nil then return end
  pcall(function()
    sound:setPosition(pos, look, nil, v3(pose.vel))
    local rpm = pose.rpm or 900
    local gas = pose.gas or 0
    smooth_rpm = smooth_rpm + (rpm - smooth_rpm) * 0.15
    smooth_gas = smooth_gas + (gas - smooth_gas) * 0.3
    smooth_rpm = clamp(smooth_rpm, 800, 9000)
    smooth_gas = clamp(smooth_gas, 0, 1)
    sound:setParam('rpms', smooth_rpm)
    sound:setParam('throttle', smooth_gas)
    sound:setParam('gear', pose.gear or 3)
    sound.volume = 0.25 + smooth_gas * 0.25
  end)
end

function M.is_model_notice(text)
  return model_notice.is_notice(text)
end

function M.status()
  return status
end

function M.ready()
  return ready
end

local function drop_node()
  if node == nil then return end
  local old = node
  node = nil
  ready = false
  pcall(function()
    old:dispose()
  end)
end

function M.ensure(car_id)
  if car_id == nil or car_id == '' then
    status = model_notice.message('no-car', car_id)
    return false
  end
  if ready and loaded_id == car_id and node ~= nil then
    return true
  end
  ready = false
  loaded_id = car_id
  stop_sound()
  dispose_brake_lights()
  dispose_running_lights()
  light_data = nil
  drop_node()
  local paths, folder = kn5_candidates(car_id)
  car_folder = folder
  if folder == nil then
    status = model_notice.message('no-cars-folder', car_id)
    return false
  end
  local folder_exists = true
  if io ~= nil and io.dirExists ~= nil then
    folder_exists = io.dirExists(folder) == true
  end
  if not folder_exists then
    status = model_notice.message('not-installed', car_id)
    return false
  end
  if #paths == 0 then
    status = model_notice.message('no-model', car_id)
    return false
  end
  local ok_root, cars_root = pcall(ac.findNodes, 'carsRoot:yes')
  if not ok_root or cars_root == nil then
    status = model_notice.message('place-failed', car_id)
    return false
  end
  local ok_node, created = pcall(function()
    return cars_root:createBoundingSphereNode('soloTandemsLead', 12)
  end)
  if not ok_node or created == nil then
    status = model_notice.message('place-failed', car_id)
    return false
  end
  node = created
  pcall(function()
    node:setVirtualCarFlag(true)
  end)
  local loaded, path = nil, nil
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
    status = model_notice.message('load-failed', car_id)
    drop_node()
    return false
  end
  pcall(function()
    loaded:ensureUniqueMaterials()
  end)
  find_parts(node)
  find_meshes(node)
  car_spec = car_data.load(car_folder)
  lights_on = false
  beams_on = false
  tails_on = false
  beam_state = ''
  brake_on = false
  set_emissive(head_meshes, false, 0, 0)
  set_emissive(tail_meshes, false, 0, 0)
  set_emissive(brake_meshes, false, 0, 0)
  compute_ground_offset()
  ready = true
  was_hidden = true
  height_state = nil
  status = 'ok ' .. tostring(path:match('[^/\\]+$') or path)
  return true
end

local function names_inside(special, general)
  if type(special) ~= 'table' or #special == 0 then return false end
  local have = {}
  for i = 1, #(general or {}) do
    have[general[i]] = true
  end
  for i = 1, #special do
    if not have[special[i]] then return false end
  end
  return true
end

local function apply_role_meshes(meshes, names, entry, state)
  if meshes == nil or entry == nil then return end
  local color, intensity = car_lights.active_color(entry, state)
  if color == nil then
    if names_inside(names, light_data and light_data.taillights) and tails_on then
      return
    end
    set_emissive(meshes, false, 0, 0)
    return
  end
  local level = 60
  if type(intensity) == 'number' and intensity > 0 then
    level = math.min(intensity / 255 * 60, 300)
  end
  set_emissive(meshes, true, level, level * 0.25)
end

local function update_signal_lights(state)
  if light_data == nil then return end
  apply_role_meshes(reverse_meshes, light_data.reverse, light_data.reverse_entries[1], state)
  apply_role_meshes(left_meshes, light_data.turn_left, light_data.turn_left_entries[1], state)
  apply_role_meshes(right_meshes, light_data.turn_right, light_data.turn_right_entries[1], state)
end

function M.hide()
  if node ~= nil then
    pcall(function()
      node:setPosition(vec3(0, -1000, 0))
      if node.clearMotion then node:clearMotion() end
    end)
  end
  set_running_lights(false)
  set_brake_visual(false, nil, nil, nil, nil)
  update_signal_lights({})
  stop_sound()
  spin[1], spin[2], spin[3], spin[4] = 0, 0, 0, 0
  steer_smooth = 0
  height_state = nil
  was_hidden = true
end

function M.show(pose, dt)
  if pose == nil or node == nil or not ready then
    M.hide()
    return
  end
  dt = dt or 0.016
  if dt > 0.1 then dt = 0.1 end
  if dt < 0 then dt = 0 end

  local look = v3(pose.dir, vec3(0, 0, 1))
  if look:length() > 0.001 then look:normalize() else look = vec3(0, 0, 1) end
  local up = v3(pose.up, vec3(0, 1, 0))
  if up:length() > 0.001 then up:normalize() else up = vec3(0, 1, 0) end
  local side = v3(pose.side)
  if side:length() < 0.001 then
    side = vec3(look.z * up.y - look.y * up.z, look.x * up.z - look.z * up.x, look.y * up.x - look.x * up.y)
  end
  if side:length() < 0.001 then side = vec3(1, 0, 0) else side:normalize() end

  local raw = v3(pose.pos)
  local y = snap_y(raw.y, raw)
  local pos = vec3(raw.x, y, raw.z)

  node:setPosition(pos)
  node:setOrientation(look, up)
  if was_hidden then
    pcall(function()
      if node.clearMotion then node:clearMotion() end
    end)
    was_hidden = false
  end

  local target_steer = (pose.steer or 0) * math.rad(32)
  steer_smooth = steer_smooth + (target_steer - steer_smooth) * math.min(1, dt * 10)
  apply_steer_wheel((pose.steer or 0) * math.rad(car_spec.steer_lock))

  local spd = speed_ms(pose.vel)
  for i = 1, 4 do
    local radius = i <= 2 and car_spec.radius_front or car_spec.radius_rear
    local omega = pose.wheels and pose.wheels[i] or 0
    if math.abs(omega) < 0.01 then omega = spd / radius end
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
    if disc_mat[i] and disc_orig[i] then
      apply_spin_steer(disc_mat[i], disc_orig[i], spin[i], steer)
    end
  end

  update_wipers(pose)
  local recorded_lights = pose.lights or {}
  local head_on = recorded_lights.head == 1
  local high_on = recorded_lights.high == 1
  set_running_lights(head_on, high_on)
  update_running_lights(look, up, side, pos)
  set_brake_visual((pose.brake or 0) > 0.08, look, up, side, pos)
  update_signal_lights({
    head = head_on and 1 or 0,
    high = high_on and 1 or 0,
    brake = (pose.brake or 0) > 0.08 and 1 or 0,
    reverse = (pose.gear or 0) < 0 and 1 or 0,
    left = recorded_lights.left,
    right = recorded_lights.right,
    blink = recorded_lights.blink,
  })
  update_smoke(pose, look, side, pos, dt)
  update_wetness()
  update_sound(pose, look, pos)
end

function M.draw_glows()
  if not ready or was_hidden or render == nil or render.mesh == nil then return end
  if beams_on and glow_head.meshes ~= nil then
    pcall(render.mesh, glow_head)
  end
  if tails_on and glow_tail.meshes ~= nil and not brake_on then
    pcall(render.mesh, glow_tail)
  end
  if brake_on then
    glow_brake.meshes = brake_meshes or tail_meshes
    if glow_brake.meshes ~= nil then
      pcall(render.mesh, glow_brake)
    end
  end
end

return M
