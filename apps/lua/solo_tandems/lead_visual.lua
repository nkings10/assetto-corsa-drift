-- Visual lead: KN5 lead with wheels, discs, steer wheel, lights, smoke, wipers, ground snap, wetness, sound.

local M = {}

local node = nil
local all_meshes = nil
local ready = false
local loaded_id = nil
local car_folder = nil
local status = 'idle'
local was_hidden = true
local ground_offset = 0.05
local last_y = nil
local ground_bias = 0
local raycast_ok = nil
local gfx_y = 0

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
local wiper_t = 0

local brake_meshes = nil
local head_meshes = nil
local tail_meshes = nil
local exterior_meshes = nil
local tyre_meshes = nil
local brake_on = false
local lights_on = false
local wet_applied = false
local last_wet = -1

local brake_l, brake_r = nil, nil
local head_l, head_r, tail_light = nil, nil, nil

local smoke_main, smoke_heavy, smoke_push = nil, nil, nil
local smoke_clock = 0

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

local function find_meshes(root)
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
  brake_meshes = grab({
    '{ ?BRAKE? , ?brake? , actsAsBrakeLights:yes }',
    '{ ?LIGHT_BRAKE? , ?light_brake? }',
  })
  head_meshes = grab({
    '{ ?HEADLIGHT? , ?headlight? , ?HEAD_LIGHT? }',
    '{ ?FRONT_LIGHT? , ?front_light? }',
  })
  tail_meshes = grab({
    '{ ?TAILLIGHT? , ?taillight? , ?TAIL_LIGHT? }',
    '{ ?REAR_LIGHT? , ?rear_light? }',
  })
  local ok_all, meshes = pcall(function()
    return root:findMeshes('?')
  end)
  all_meshes = (ok_all and meshes) or nil
  exterior_meshes = all_meshes
  tyre_meshes = grab({ '{ ?TYRE? , ?tyre? , ?TIRE? , ?tire? }' })
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

local function update_wipers(dt)
  wiper_t = wiper_t + dt * 1.2
  local progress = math.abs(math.sin(wiper_t * math.pi))
  if wiper_ksanim ~= nil and node ~= nil then
    pcall(function()
      node:setAnimation(wiper_ksanim, progress, true)
    end)
    return
  end
  local angle = math.sin(wiper_t * math.pi * 2) * math.rad(55)
  for i = 1, #wiper_nodes do
    local w = wiper_nodes[i]
    local orig, m = w.orig, w.mat
    local cos_w, sin_w = math.cos(angle), math.sin(angle)
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

local function make_light(color, range, spot)
  if ac.LightSource == nil then return nil end
  local ok, light = pcall(ac.LightSource, ac.LightType.Regular)
  if not ok or light == nil then return nil end
  light.color = color
  light.range = range
  light.spot = spot
  light.spotSharpness = 0.4
  light.shadows = false
  light.position = vec3(0, -1000, 0)
  return light
end

local function ensure_lights()
  if brake_l == nil then
    brake_l = make_light(rgb(40, 0, 0), 5, 90)
    brake_r = make_light(rgb(40, 0, 0), 5, 90)
  end
  if head_l == nil then
    head_l = make_light(rgb(8, 8, 7), 60, 55)
    head_r = make_light(rgb(8, 8, 7), 60, 55)
    tail_light = make_light(rgb(4, 0, 0), 18, 110)
  end
end

local function hide_light(light)
  if light ~= nil then light.position = vec3(0, -1000, 0) end
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

local function set_running_lights(on)
  if on == lights_on then return end
  lights_on = on
  ensure_lights()
  set_emissive(head_meshes, on, 100, 30)
  set_emissive(tail_meshes, on, 60, 15)
  if not on then
    hide_light(head_l)
    hide_light(head_r)
    hide_light(tail_light)
  end
end

local function set_brake_visual(on, look, up, side, pos)
  ensure_lights()
  if on ~= brake_on then
    brake_on = on
    -- Prefer dedicated brake meshes; fall back to taillight meshes only while braking.
    local meshes = brake_meshes or tail_meshes
    set_emissive(meshes, on, 55, 14)
    if not on and brake_meshes ~= nil and tail_meshes ~= nil and brake_meshes ~= tail_meshes then
      set_emissive(tail_meshes, false, 0, 0)
    end
  end
  if not on then
    hide_light(brake_l)
    hide_light(brake_r)
    return
  end
  if look == nil or pos == nil then return end
  local rear = pos - look * 2.0 + up * 0.5
  local dir = (-look - up * 0.1):normalize()
  if brake_l then
    brake_l.position = rear + side * 0.55
    brake_l.direction = dir
  end
  if brake_r then
    brake_r.position = rear - side * 0.55
    brake_r.direction = dir
  end
end

local function ensure_smoke()
  if smoke_main ~= nil or ac.Particles == nil or ac.Particles.Smoke == nil then return end
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

local function update_smoke(pose, look, side, pos, dt)
  ensure_smoke()
  if smoke_main == nil or pose == nil then return end
  local drift = math.abs(pose.drift or 0)
  local speed = pose.speed or (speed_ms(pose.vel) * 3.6)
  if smoke_push ~= nil then
    smoke_push.position = pos
    if pose.vel then smoke_push.velocity = v3(pose.vel) end
  end
  local now = os.preciseClock and os.preciseClock() or smoke_clock + dt
  -- Tandem fires ~120 Hz with many bursts; keep a lighter stream for Solo Tandems.
  if drift <= 8 or speed <= 20 or now - smoke_clock < 0.04 then
    return
  end
  smoke_clock = now
  local intensity = clamp((drift - 8) / 40, 0, 1) * clamp((speed - 20) / 80, 0, 1)
  local wheel_base, track_half = 1.35, 0.72
  local vel = v3(pose.vel)
  local kick = speed * 0.008 * intensity
  local slip_sign = (pose.drift or 0) > 0 and -1 or 1
  local amount = 0.25 + intensity * 0.9
  for _, sign in ipairs({ -1, 1 }) do
    local contact = pos - look * wheel_base + side * (track_half * sign) + vec3(0, 0.02, 0)
    local v = vec3(
      vel.x * 0.25 - look.x * kick + side.x * slip_sign * speed * 0.004,
      0.05 + math.random() * 0.1,
      vel.z * 0.25 - look.z * kick + side.z * slip_sign * speed * 0.004
    )
    pcall(function()
      smoke_main:emit(contact, v, amount)
    end)
    if intensity > 0.55 and smoke_heavy ~= nil then
      pcall(function()
        smoke_heavy:emit(contact, v * 1.1, (intensity - 0.55) * 1.2)
      end)
    end
  end
end

local function compute_ground_offset()
  if node == nil then
    ground_offset = 0.05
    return
  end
  pcall(function()
    node:setPosition(vec3(0, 0, 0))
    node:setOrientation(vec3(0, 0, 1), vec3(0, 1, 0))
  end)
  local sum, count = 0, 0
  local radius = 0.33
  for i = 1, 4 do
    local ref = tyre_ref[i] or wheel_ref[i]
    if ref ~= nil then
      local ok, world_y = pcall(function()
        local wm = ref:getWorldTransformationRaw()
        if wm == nil then return nil end
        if wm.row4 ~= nil then return wm.row4.y end
        if wm.position ~= nil then return wm.position.y end
        return nil
      end)
      if ok and world_y ~= nil then
        sum = sum + (radius - world_y)
        count = count + 1
      end
    end
  end
  pcall(function()
    node:setPosition(vec3(0, -1000, 0))
    if node.clearMotion then node:clearMotion() end
  end)
  if count > 0 then
    ground_offset = sum / count
  else
    -- No wheel nodes: keep a tiny road offset; drop recorded COM when raycast misses.
    ground_offset = 0.05
    ground_bias = -0.95 + gfx_y
  end
end

local function get_ground_y(world_pos)
  if raycast_ok == false or render == nil or render.createRay == nil then return nil end
  local from = vec3(world_pos.x, world_pos.y + 5, world_pos.z)
  local dir = vec3(0, -1, 0)
  local ok, dist = pcall(function()
    local ray = render.createRay(from, dir, 20)
    return ray:track()
  end)
  if ok and dist ~= nil and dist >= 0 then
    raycast_ok = true
    return from.y - dist
  end
  local ok2, dist2 = pcall(function()
    local ray = render.createRay(from, dir, 20)
    return ray:physics(vec3(), vec3())
  end)
  if ok2 and dist2 ~= nil and dist2 >= 0 then
    raycast_ok = true
    return from.y - dist2
  end
  if raycast_ok == nil then raycast_ok = false end
  return nil
end

local function snap_y(recorded_y, world_xz, dt, speed_kmh)
  local ground = get_ground_y(vec3(world_xz.x, recorded_y, world_xz.z))
  local target
  if ground ~= nil then
    -- Seat the KN5 origin from the road, not from physics COM (that floated ~1 m).
    target = ground + ground_offset
  else
    -- No raycast: drop from recorded COM toward visual ground height.
    local drop = ground_bias
    if math.abs(drop) < 0.05 then drop = -0.95 + gfx_y end
    target = recorded_y + drop
  end
  if was_hidden or last_y == nil then
    last_y = target
    return target
  end
  local max_delta = 0.12 * math.max(1, (speed_kmh or 0) / 80)
  local delta = clamp(target - last_y, -max_delta, max_delta)
  local smooth = (delta < 0) and 14 or 10
  last_y = last_y + delta * math.min(1, dt * smooth)
  return last_y
end

local function update_wetness()
  if all_meshes == nil or ac.getSim == nil then return end
  local ok, sim = pcall(ac.getSim)
  if not ok or sim == nil then return end
  local wet = sim.rainWetness or 0
  local q = math.floor(wet * 100 + 0.5) / 100
  if q > 0.01 then
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
      if exterior_meshes then
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
  stop_sound()
  if node ~= nil then
    pcall(function()
      node:setPosition(vec3(0, -1000, 0))
    end)
  end
  node = nil
  local paths, folder = kn5_candidates(car_id)
  car_folder = folder
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
    return cars_root:createBoundingSphereNode('SoloTandemsLead', 12)
  end)
  if not ok_node or created == nil then
    status = 'node failed'
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
    status = 'load failed'
    pcall(function()
      node:setPosition(vec3(0, -1000, 0))
    end)
    return false
  end
  pcall(function()
    loaded:ensureUniqueMaterials()
  end)
  find_parts(node)
  find_meshes(node)
  lights_on = false
  brake_on = false
  set_emissive(head_meshes, false, 0, 0)
  set_emissive(tail_meshes, false, 0, 0)
  set_emissive(brake_meshes, false, 0, 0)
  gfx_y = 0
  if ac.getCar ~= nil then
    local ok_car, car = pcall(ac.getCar, 0)
    if ok_car and car ~= nil and car.graphicsOffset ~= nil then
      gfx_y = car.graphicsOffset.y or 0
    end
  end
  compute_ground_offset()
  ready = true
  was_hidden = true
  last_y = nil
  ground_bias = ground_offset
  status = 'ok ' .. tostring(path:match('[^/\\]+$') or path)
  return true
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
  stop_sound()
  spin[1], spin[2], spin[3], spin[4] = 0, 0, 0, 0
  steer_smooth = 0
  last_y = nil
  ground_bias = 0
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
  local speed = pose.speed or (speed_ms(pose.vel) * 3.6)
  local y = snap_y(raw.y, raw, dt, speed)
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
  apply_steer_wheel((pose.steer or 0) * math.rad(450))

  local spd = speed_ms(pose.vel)
  local radius = 0.33
  for i = 1, 4 do
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

  update_wipers(dt)
  -- Head/tail stay off unless we add a lights toggle later; only brake glow when braking.
  if lights_on then
    set_running_lights(false)
  end
  set_brake_visual((pose.brake or 0) > 0.08, look, up, side, pos)
  update_smoke(pose, look, side, pos, dt)
  update_wetness()
  update_sound(pose, look, pos)
end

function M.draw_glows()
  if not ready or was_hidden or render == nil or render.mesh == nil then return end
  if brake_on then
    glow_brake.meshes = brake_meshes or tail_meshes
    if glow_brake.meshes ~= nil then
      pcall(render.mesh, glow_brake)
    end
  end
end

return M
