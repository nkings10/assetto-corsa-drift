-- Record a lead run and play it as a visual KN5 ghost. The player is the chase car.
-- Custom Shaders Patch 0.2.11. No second physics car — wheels/lights animate on the ghost.

local function app_file(name)
  local folder = 'apps/lua/solo_tandem/'
  if ac.getFolder and ac.FolderID and ac.FolderID.ACApps then
    local apps = ac.getFolder(ac.FolderID.ACApps)
    if type(apps) == 'string' and apps ~= '' then
      folder = apps .. '/lua/solo_tandem/'
    end
  end
  return folder .. name
end

local logic = dofile(app_file('logic.lua'))
local ghost = dofile(app_file('ghost_visual.lua'))

local state = logic.create()
local deck_seq = 0
local deck = nil
local recorded_car_id = nil
local ghost_override = nil
local all_cars = nil
local car_search = ''
local car_options = nil
local car_option_i = 1
local run_name = 'run'
local run_files = nil
local run_pick = 1
local run_folder_edit = nil

local settings = nil
if ac.storage ~= nil then
  local ok, stored = pcall(ac.storage, { runsFolder = '' }, 'soloTandem.')
  if ok then settings = stored end
end

local function documents_root()
  if ac.getFolder and ac.FolderID then
    if ac.FolderID.Documents then
      local docs = ac.getFolder(ac.FolderID.Documents)
      if type(docs) == 'string' and docs ~= '' then return docs end
    end
    if ac.FolderID.ACDocuments then
      local docs = ac.getFolder(ac.FolderID.ACDocuments)
      if type(docs) == 'string' and docs ~= '' then return docs end
    end
  end
  return nil
end

local function default_runs_folder()
  local docs = documents_root()
  if docs ~= nil then
    return docs .. '/Solo Tandems'
  end
  local apps = ac.getFolder and ac.FolderID and ac.getFolder(ac.FolderID.ACApps)
  if type(apps) == 'string' and apps ~= '' then
    return apps .. '/lua/solo_tandem/runs'
  end
  return 'Solo Tandems'
end

local function normalize_folder(path)
  path = tostring(path or '')
  path = path:gsub('\\', '/')
  path = path:gsub('/+$', '')
  return path
end

local function runs_folder()
  local custom = settings and settings.runsFolder or ''
  custom = normalize_folder(custom)
  if custom ~= '' then return custom end
  return normalize_folder(default_runs_folder())
end

local function set_runs_folder(path)
  path = normalize_folder(path)
  if path == '' then path = normalize_folder(default_runs_folder()) end
  if settings ~= nil then
    settings.runsFolder = path
  end
  run_folder_edit = path
  run_files = nil
  run_pick = 1
end

local function ensure_runs_folder()
  local folder = runs_folder()
  if io ~= nil and io.createDir ~= nil then
    pcall(io.createDir, folder)
  end
  return folder
end

local function sanitize_name(name)
  name = tostring(name or 'run')
  name = name:gsub('[^%w%-%_]+', '_')
  if name == '' then name = 'run' end
  return name
end

local function track_id()
  if ac.getTrackFullID ~= nil then
    local ok, id = pcall(ac.getTrackFullID, '_')
    if ok and type(id) == 'string' then return id end
  end
  if ac.getTrackID ~= nil then
    local ok, id = pcall(ac.getTrackID)
    if ok and type(id) == 'string' then return id end
  end
  return ''
end

local function refresh_run_files()
  run_files = {}
  local folder = ensure_runs_folder()
  if io == nil or io.scanDir == nil then return end
  local files = io.scanDir(folder, '*.lead')
  if files == nil then return end
  for i = 1, #files do
    run_files[#run_files + 1] = files[i]
  end
  table.sort(run_files)
  if run_pick > #run_files then run_pick = math.max(1, #run_files) end
end

local ACTIONS = {
  [1] = logic.RECORD,
  [2] = logic.APPEAR,
  [3] = logic.SPOT,
  [4] = logic.TELEPORT,
  [5] = logic.START,
  [6] = logic.CLEAR,
}

local NAMES = {
  record = logic.RECORD,
  appear = logic.APPEAR,
  spot = logic.SPOT,
  teleport = logic.TELEPORT,
  start = logic.START,
  clear = logic.CLEAR,
}

local function bind(id)
  if ac.ControlButton == nil then return nil end
  local ok, button = pcall(ac.ControlButton, id)
  if ok and button ~= nil then return button end
  return nil
end

local buttons = {
  { key = 'record', button = bind('Solo Tandems/Record') },
  { key = 'appear', button = bind('Solo Tandems/Appear') },
  { key = 'spot', button = bind('Solo Tandems/Chase spot') },
  { key = 'teleport', button = bind('Solo Tandems/Teleport') },
  { key = 'start', button = bind('Solo Tandems/Start') },
  { key = 'clear', button = bind('Solo Tandems/Clear lead') },
}

local function vec3_of(v)
  return vec3(v.x, v.y, v.z)
end

local function read_wheels(car)
  local wheels = { 0, 0, 0, 0 }
  if car.wheels == nil then return wheels end
  for i = 0, 3 do
    local wheel = car.wheels[i]
    if wheel ~= nil and wheel.angularSpeed ~= nil then
      wheels[i + 1] = wheel.angularSpeed
    end
  end
  return wheels
end

local function read_steer(car)
  local lock = car.steerLock
  if lock == nil or lock < 0.001 then return 0 end
  local steer = car.steer or 0
  local n = steer / lock
  if n > 1 then return 1 end
  if n < -1 then return -1 end
  return n
end

local function read_brake(car)
  local brake = car.brake or 0
  local hand = car.handbrake or 0
  if hand > brake then brake = hand end
  if brake < 0.05 then return 0 end
  if brake > 1 then return 1 end
  return brake
end

local function read_drift(car, vel, look)
  local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
  if speed < 5 then return 0 end
  local vx, vy, vz = vel.x / speed, vel.y / speed, vel.z / speed
  local lx, ly, lz = look.x, look.y, look.z
  local llen = math.sqrt(lx * lx + ly * ly + lz * lz)
  if llen > 0.001 then lx, ly, lz = lx / llen, ly / llen, lz / llen end
  local dot = vx * lx + vy * ly + vz * lz
  if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
  local angle = math.deg(math.acos(dot))
  local cy = vz * lx - vx * lz
  if cy < 0 then angle = -angle end
  return angle
end

local function read_pose(car)
  local vel = car.velocity or vec3(0, 0, 0)
  local dir = car.look or vec3(0, 0, 1)
  local up = car.up or vec3(0, 1, 0)
  local side = car.side
  if side == nil then
    side = vec3(dir.z * up.y - dir.y * up.z, dir.x * up.z - dir.z * up.x, dir.y * up.x - dir.x * up.y)
  end
  return {
    pos = { x = car.position.x, y = car.position.y, z = car.position.z },
    dir = { x = dir.x, y = dir.y, z = dir.z },
    up = { x = up.x, y = up.y, z = up.z },
    side = { x = side.x, y = side.y, z = side.z },
    vel = { x = vel.x, y = vel.y, z = vel.z },
    brake = read_brake(car),
    steer = read_steer(car),
    gas = car.gas or 0,
    rpm = car.rpm or 0,
    gear = car.gear or 0,
    drift = read_drift(car, vel, dir),
    speed = car.speedKmh or math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z) * 3.6,
    wheels = read_wheels(car),
  }
end

local function can_move()
  return physics ~= nil and physics.allowed ~= nil and physics.allowed()
end

local function car_count()
  if ac.getSim == nil then return 1 end
  local ok, sim = pcall(ac.getSim)
  if not ok or sim == nil or sim.carsCount == nil then return 1 end
  return sim.carsCount
end

local function player()
  if ac.getCar == nil then return nil end
  local ok, car = pcall(ac.getCar, 0)
  if not ok then return nil end
  return car
end

local function player_car_id()
  if ac.getCarID == nil then return nil end
  local ok, id = pcall(ac.getCarID, 0)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

local function call(fn, ...)
  if fn == nil then return false end
  return pcall(fn, ...)
end

local function move_car(index, pose, speed)
  if physics == nil or pose == nil then return false end
  local vel = speed or pose.vel
  local dir = vec3_of(pose.dir)
  call(physics.setCarVelocity, index, vec3_of(vel))
  local ok = call(physics.setCarPosition, index, vec3_of(pose.pos), -dir)
  call(physics.setCarVelocity, index, vec3_of(vel))
  return ok
end

local function teleport_player()
  local spot = state.spot
  if spot == nil or physics == nil then return end
  local pose = { pos = spot.pos, dir = spot.dir, vel = { x = 0, y = 0, z = 0 } }
  move_car(0, pose, pose.vel)
  call(physics.engageGear, 0, 0)
end

local function refresh_car_list()
  all_cars = {}
  if ac.getFolder == nil or ac.FolderID == nil or ac.FolderID.ContentCars == nil then return end
  local folder = ac.getFolder(ac.FolderID.ContentCars)
  if type(folder) ~= 'string' or folder == '' or io == nil or io.scanDir == nil then return end
  local dirs = io.scanDir(folder, '*')
  if dirs == nil then return end
  for i = 1, #dirs do
    local name = dirs[i]
    if type(name) == 'string' and name ~= '' then
      local path = folder .. '/' .. name
      local is_dir = true
      if io.dirExists ~= nil then
        is_dir = io.dirExists(path) == true
      end
      if is_dir then
        all_cars[#all_cars + 1] = name
      end
    end
  end
  table.sort(all_cars)
end

local function rebuild_car_options()
  if all_cars == nil then refresh_car_list() end
  car_options = {}
  local recorded = recorded_car_id or player_car_id() or '?'
  car_options[1] = { id = nil, label = 'Same as recorded (' .. tostring(recorded) .. ')' }
  local q = tostring(car_search or ''):lower()
  if all_cars ~= nil then
    for i = 1, #all_cars do
      local id = all_cars[i]
      if q == '' or id:lower():find(q, 1, true) then
        car_options[#car_options + 1] = { id = id, label = id }
      end
    end
  end
  if car_option_i < 1 then car_option_i = 1 end
  if car_option_i > #car_options then car_option_i = #car_options end
end

local function sync_car_option_index()
  if car_options == nil then rebuild_car_options() end
  if ghost_override == nil or ghost_override == '' then
    car_option_i = 1
    return
  end
  for i = 2, #car_options do
    if car_options[i].id == ghost_override then
      car_option_i = i
      return
    end
  end
  car_option_i = 1
end

local function effective_ghost_id()
  if ghost_override ~= nil and ghost_override ~= '' then
    return ghost_override
  end
  return recorded_car_id or player_car_id()
end

local function apply_car_option()
  if car_options == nil or car_options[car_option_i] == nil then return end
  local picked = car_options[car_option_i]
  local before = effective_ghost_id()
  ghost_override = picked.id
  local after = effective_ghost_id()
  if after ~= nil and after ~= before and state.placed then
    ghost.ensure(after)
  end
end

local function ensure_ghost()
  local id = effective_ghost_id()
  if id == nil then return false end
  if recorded_car_id == nil then recorded_car_id = id end
  return ghost.ensure(id)
end

local function context()
  local car = player()
  return {
    cars = car_count(),
    can_move = can_move(),
    pose = car and read_pose(car) or nil,
  }
end

local function export_run()
  if #state.samples == 0 then
    state.notice = 'No lead recorded'
    return
  end
  local folder = ensure_runs_folder()
  local name = sanitize_name(run_name)
  local path = folder .. '/' .. name .. '.lead'
  local payload, err = logic.pack(state, {
    carId = recorded_car_id or player_car_id() or '',
    trackId = track_id(),
  })
  if payload == nil then
    state.notice = err or 'Export failed'
    return
  end
  local text = logic.encode(payload)
  if text == nil or io == nil or io.save == nil then
    state.notice = 'Export failed'
    return
  end
  local ok = io.save(path, text)
  if ok then
    state.notice = 'Exported ' .. name .. '.lead'
    refresh_run_files()
  else
    state.notice = 'Export save failed'
  end
end

local function import_run()
  refresh_run_files()
  if run_files == nil or #run_files == 0 then
    state.notice = 'No .lead files in runs folder'
    return
  end
  local name = run_files[run_pick]
  if name == nil then
    state.notice = 'Pick a run file'
    return
  end
  local path = ensure_runs_folder() .. '/' .. name
  if io == nil or io.load == nil then
    state.notice = 'Import failed'
    return
  end
  local text = io.load(path)
  local payload, err = logic.decode(text)
  if payload == nil then
    state.notice = err or 'Bad lead file'
    return
  end
  local meta, aerr = logic.apply_pack(state, payload, { trackId = track_id() })
  if meta == nil then
    state.notice = aerr or 'Import failed'
    return
  end
  if meta.carId ~= nil and meta.carId ~= '' then
    recorded_car_id = meta.carId
  end
  ghost_override = nil
  car_options = nil
  ghost.hide()
  state.notice = 'Imported ' .. name
end

local function press(action)
  logic.handle(state, action, context())
  if state.pulse == 'teleport' then
    state.pulse = nil
    teleport_player()
  end
  if action == logic.RECORD and state.recording then
    recorded_car_id = player_car_id()
    ghost_override = nil
    car_options = nil
  end
  if action == logic.CLEAR or (action == logic.RECORD and state.recording) then
    ghost.hide()
  end
end

local function button_down(button)
  if button == nil or button.pressed == nil then return false end
  if type(button.pressed) == 'boolean' then return button.pressed end
  if type(button.pressed) == 'function' then
    local ok, down = pcall(button.pressed, button)
    return ok and down == true
  end
  return false
end

local function ensure_deck()
  if deck ~= nil or ac.connect == nil or ac.StructItem == nil then return end
  local ok, link = pcall(ac.connect, {
    ac.StructItem.key('leadChase.v1'),
    seq = ac.StructItem.int32(),
    action = ac.StructItem.int32(),
  })
  if ok then deck = link end
end

local function deck_action()
  ensure_deck()
  if deck == nil or deck.seq == deck_seq then return end
  deck_seq = deck.seq
  local action = ACTIONS[deck.action]
  if action ~= nil then press(action) end
end

function script.update(dt)
  deck_action()
  for i = 1, #buttons do
    local item = buttons[i]
    if button_down(item.button) then
      press(NAMES[item.key])
    end
  end

  local car = player()
  if state.recording and car ~= nil then
    logic.capture(state, dt, read_pose(car))
  end

  local pose = logic.lead_pose(state, dt)
  if pose == nil then
    ghost.hide()
  else
    if ensure_ghost() then
      ghost.show(pose, dt)
    end
  end
end

function script.draw3D()
  ghost.draw_glows()
end

function script.windowMain(dt)
  ui.text(state.notice)
  ui.text(state.recording and 'Recording' or 'Not recording')
  ui.text('Lead samples: ' .. tostring(#state.samples))
  if state.placed then
    ui.text(state.playing and 'Lead is running' or 'Lead is waiting')
  else
    ui.text('Lead is hidden')
  end
  ui.text(can_move() and 'Extended physics on' or 'Extended physics off (teleport only)')
  ui.text('Ghost: ' .. tostring(ghost.status()))
  ui.text('Lead car: ' .. tostring(effective_ghost_id() or 'none'))
  if recorded_car_id ~= nil then
    ui.text('Recorded car: ' .. recorded_car_id)
  end

  ui.separator()
  ui.text('Lead car')
  if ui.inputText ~= nil then
    local ok, a, b = pcall(ui.inputText, 'Filter', car_search)
    if ok then
      local next_search = car_search
      if type(a) == 'string' then
        next_search = a
      elseif type(b) == 'string' then
        next_search = b
      end
      if next_search ~= car_search then
        car_search = next_search
        rebuild_car_options()
        sync_car_option_index()
      end
    end
  end
  if car_options == nil then
    rebuild_car_options()
    sync_car_option_index()
  end
  if car_options ~= nil and #car_options > 0 then
    local preview = car_options[car_option_i] and car_options[car_option_i].label or 'Lead car'
    local flags = nil
    if ui.ComboFlags ~= nil and ui.ComboFlags.HeightLarge ~= nil then
      flags = ui.ComboFlags.HeightLarge
    end
    local function draw_car_combo()
      for i = 1, #car_options do
        local opt = car_options[i]
        if ui.selectable(opt.label, i == car_option_i) then
          if i ~= car_option_i then
            car_option_i = i
            apply_car_option()
          end
        end
      end
    end
    if flags ~= nil then
      pcall(ui.combo, '##lead_car', preview, flags, draw_car_combo)
    else
      pcall(ui.combo, '##lead_car', preview, draw_car_combo)
    end
  end

  ui.separator()
  if ui.button('Record') then press(logic.RECORD) end
  ui.sameLine(0, 8)
  if ui.button('Appear') then press(logic.APPEAR) end
  ui.sameLine(0, 8)
  if ui.button('Start') then press(logic.START) end
  if ui.button('Chase spot') then press(logic.SPOT) end
  ui.sameLine(0, 8)
  if ui.button('Teleport') then press(logic.TELEPORT) end
  ui.sameLine(0, 8)
  if ui.button('Clear') then press(logic.CLEAR) end

  ui.separator()
  ui.text('Share run')
  if run_folder_edit == nil then
    run_folder_edit = runs_folder()
  end
  if ui.inputText ~= nil then
    local ok, a, b = pcall(ui.inputText, 'Runs folder', run_folder_edit)
    if ok then
      if type(a) == 'string' then
        run_folder_edit = a
      elseif type(b) == 'string' then
        run_folder_edit = b
      end
    end
  end
  if ui.button('Apply folder') then
    set_runs_folder(run_folder_edit)
    refresh_run_files()
    state.notice = 'Runs folder set'
  end
  ui.sameLine(0, 8)
  if ui.button('Default folder') then
    set_runs_folder(default_runs_folder())
    refresh_run_files()
    state.notice = 'Runs folder reset'
  end
  ui.text(runs_folder())
  if ui.inputText ~= nil then
    local ok, a, b = pcall(ui.inputText, 'Name', run_name)
    if ok then
      if type(a) == 'string' and a ~= '' then
        run_name = a
      elseif type(b) == 'string' and b ~= '' then
        run_name = b
      end
    end
  end
  if run_name == nil or run_name == '' then run_name = 'run' end
  if ui.button('Export .lead') then export_run() end
  ui.sameLine(0, 8)
  if ui.button('Refresh list') then refresh_run_files() end
  if run_files == nil then refresh_run_files() end
  if run_files ~= nil and #run_files > 0 then
    if ui.button('<') then
      run_pick = math.max(1, run_pick - 1)
    end
    ui.sameLine(0, 8)
    ui.text(tostring(run_files[run_pick] or ''))
    ui.sameLine(0, 8)
    if ui.button('>') then
      run_pick = math.min(#run_files, run_pick + 1)
    end
  else
    ui.text('No .lead files yet')
  end
  if ui.button('Import .lead') then import_run() end
end
