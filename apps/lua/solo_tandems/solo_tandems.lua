-- Record a lead run and play it as a visual KN5 lead. The player is the chase car.
-- Custom Shaders Patch 0.2.11. No second physics car — wheels/lights animate on the lead.

local function app_file(name)
  local folder = 'apps/lua/solo_tandems/'
  if ac.getFolder and ac.FolderID and ac.FolderID.ACApps then
    local apps = ac.getFolder(ac.FolderID.ACApps)
    if type(apps) == 'string' and apps ~= '' then
      folder = apps .. '/lua/solo_tandems/'
    end
  end
  return folder .. name
end

local logic = dofile(app_file('logic.lua'))
local lead_visual = dofile(app_file('lead_visual.lua'))
local setup_slot = dofile(app_file('setup_slot.lua'))
local setups = dofile(app_file('setups.lua'))

local state = logic.create()
local deck = nil
local deck_link = { seen = false, seq = 0 }
local recorded_car_id = nil
local recorded_skin = ''
local setup_loaded = false
local run_name = 'run'
local run_files = nil
local run_pick = 1
local run_folder_edit = nil
local setup_name = ''
local setup_entries = {}
local setup_pick = 1
local setup_selected = nil

local settings = nil
if ac.storage ~= nil then
  local ok, stored = pcall(ac.storage, { runsFolder = '', contact = false }, 'soloTandems.')
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
    return apps .. '/lua/solo_tandems/runs'
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

local function file_exists(path)
  if io == nil then return false end
  if io.fileExists ~= nil then
    return io.fileExists(path) == true
  end
  if io.load == nil then return false end
  local ok, text = pcall(io.load, path)
  return ok and type(text) == 'string'
end

local function setups_root()
  if ac.getFolder == nil or ac.FolderID == nil or ac.FolderID.UserSetups == nil then
    return nil
  end
  local ok, folder = pcall(ac.getFolder, ac.FolderID.UserSetups)
  if ok and type(folder) == 'string' and folder ~= '' then
    return normalize_folder(folder)
  end
  return nil
end

local function current_track_folder()
  if ac.getTrackID == nil then return '' end
  local ok, id = pcall(ac.getTrackID)
  if ok and type(id) == 'string' then return id end
  return ''
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
  [2] = logic.SPAWN,
  [3] = logic.CHASE,
  [4] = logic.TELEPORT,
  [5] = logic.START,
  [6] = logic.CLEAR,
}

local NAMES = {
  record = logic.RECORD,
  spawn = logic.SPAWN,
  chase = logic.CHASE,
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
  { key = 'record', button = bind('Solo Tandems/Record Lead Run') },
  { key = 'spawn', button = bind('Solo Tandems/Spawn Lead Car') },
  { key = 'chase', button = bind('Solo Tandems/Set Chase Car') },
  { key = 'teleport', button = bind('Solo Tandems/Teleport') },
  { key = 'start', button = bind('Solo Tandems/Start') },
  { key = 'clear', button = bind('Solo Tandems/Clear Lead Run') },
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

local function read_slip(car)
  local slip = { 0, 0, 0, 0 }
  if car.wheels == nil then return slip end
  for i = 0, 3 do
    local wheel = car.wheels[i]
    if wheel ~= nil and type(wheel.ndSlip) == 'number' then
      slip[i + 1] = wheel.ndSlip
    end
  end
  return slip
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
    slip = read_slip(car),
    wipers = car.wiperProgress or 0,
    lights = {
      head = car.headlightsActive and 1 or 0,
      high = car.highBeams and 1 or 0,
      left = (car.turningLeftLights or car.hazardLights) and 1 or 0,
      right = (car.turningRightLights or car.hazardLights) and 1 or 0,
      blink = car.turningLightsActivePhase and 1 or 0,
    },
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

local function player_skin()
  if ac.getCarSkin == nil then return '' end
  local ok, name = pcall(ac.getCarSkin, 0)
  if ok and type(name) == 'string' then return name end
  return ''
end

local function setup_files(folder)
  local files = {}
  if io == nil or io.scanDir == nil or folder == nil or folder == '' then return files end
  local ok, list = pcall(io.scanDir, folder, '*.ini')
  if not ok or type(list) ~= 'table' then return files end
  for i = 1, #list do
    files[#files + 1] = list[i]
  end
  return files
end

local function refresh_setup_entries()
  local car = player_car_id()
  local root = setups_root()
  if car == nil or root == nil then
    setup_entries = {}
    setup_pick = 1
    return
  end
  local base = root .. '/' .. car .. '/'
  local track = current_track_folder()
  local track_files = nil
  if track ~= '' and track ~= 'generic' then
    track_files = setup_files(base .. track)
  end
  setup_entries = setups.entries(track, setup_files(base .. 'generic'), track_files)
  setup_pick = 1
  if setup_selected ~= nil then
    for i = 1, #setup_entries do
      if setup_entries[i].path == setup_selected then
        setup_pick = i
        return
      end
    end
  end
  if #setup_entries == 0 then
    setup_selected = nil
    return
  end
  setup_selected = setup_entries[1].path
end

local function setup_change_allowed()
  if ac.isCarResetAllowed == nil then return true end
  local ok, allowed = pcall(ac.isCarResetAllowed)
  return ok and allowed == true
end

local function save_setup(relative, notice)
  if relative == nil then
    state.notice = 'No track for a track default'
    return
  end
  if not setup_change_allowed() then
    state.notice = 'Setup changes in practice'
    return
  end
  if ac.saveCurrentSetup == nil then
    state.notice = 'Setup save failed'
    return
  end
  local ok, saved = pcall(ac.saveCurrentSetup, relative)
  if not ok or saved == false then
    state.notice = 'Setup save failed'
    return
  end
  if ac.refreshSetups ~= nil then pcall(ac.refreshSetups) end
  refresh_setup_entries()
  state.notice = notice
end

local function load_chosen_setup(relative, notice)
  if relative == nil then
    state.notice = 'No setup selected'
    return
  end
  if not setup_change_allowed() then
    state.notice = 'Setup changes in practice'
    return
  end
  if ac.loadSetup == nil then
    state.notice = 'Setup load failed'
    return
  end
  local ok, loaded = pcall(ac.loadSetup, relative)
  if not ok or loaded == false then
    state.notice = 'Setup load failed'
    return
  end
  state.notice = notice
end

local function read_text_input(a, b, current)
  if type(a) == 'string' then return a end
  if type(b) == 'string' then return b end
  return current
end

local function apply_final_drive(drive, value)
  if not setup_change_allowed() then
    state.notice = 'Setup changes in practice'
    return
  end
  if physics ~= nil and physics.awakeCar ~= nil then
    pcall(physics.awakeCar, 0)
  end
  if ac.setSetupSpinnerValue == nil then
    state.notice = 'Diff ratio is not available'
    return
  end
  local ok, applied = pcall(ac.setSetupSpinnerValue, drive.name, value)
  if not ok or applied == false then
    state.notice = 'Diff ratio is not available'
  end
end

local function draw_diff_ratio()
  if ac.getSetupSpinners == nil then return end
  local ok, spinners = pcall(ac.getSetupSpinners)
  if not ok then return end
  local drive = setups.final_drive(spinners)
  if drive == nil then return end
  ui.separator()
  ui.text('Diff ratio')
  local label = setups.final_drive_label(drive)
  if type(drive.items) == 'table' and #drive.items > 0 and ui.combo ~= nil and ui.selectable ~= nil then
    ui.combo('##diff', label, function()
      for i = 1, #drive.items do
        if ui.selectable(tostring(drive.items[i]), i - 1 == drive.value) then
          apply_final_drive(drive, i - 1)
        end
      end
    end)
    return
  end
  if ui.slider == nil then
    ui.text(label)
    return
  end
  local multiplier = drive.displayMultiplier or 1
  if multiplier == 0 then multiplier = 1 end
  local shown = ui.slider(
    '##diff',
    (drive.value or 0) * multiplier,
    (drive.min or 0) * multiplier,
    (drive.max or 0) * multiplier,
    'Diff ratio: %.3f'
  )
  if ui.itemEdited ~= nil and ui.itemEdited() and type(shown) == 'number' then
    apply_final_drive(drive, shown / multiplier)
  end
end

local function draw_setups()
  ui.separator()
  ui.text('Setup')
  if ui.inputText ~= nil then
    local ok, a, b = pcall(ui.inputText, 'Name', setup_name)
    if ok then setup_name = read_text_input(a, b, setup_name) end
  end
  if ui.button('Save') then
    local typed = (setup_name:match('^%s*(.-)%s*$')) or ''
    local path = setups.named_file(setup_name)
    if path ~= nil then
      local leaf = path:match('([^/]+)$') or path
      save_setup(path, 'Saved ' .. setups.display_name(leaf))
    elseif typed:lower():gsub('%.ini$', '') == 'solo tandems' then
      state.notice = 'Solo Tandems is saved with the default buttons'
    else
      state.notice = 'Type a setup name'
    end
  end
  if ui.button('Save Car Default') then
    save_setup(setups.car_default(), 'Saved car default')
  end
  ui.sameLine(0, 8)
  if ui.button('Save Track Default') then
    save_setup(setups.track_default(current_track_folder()), 'Saved track default')
  end

  ui.text('Setups')
  refresh_setup_entries()
  local current = setup_entries[setup_pick]
  local preview = current and current.label or 'No setups'
  if ui.combo ~= nil and ui.selectable ~= nil and #setup_entries > 0 then
    local width_pushed = false
    if ui.pushItemWidth ~= nil and ui.availableSpaceX ~= nil then
      ui.pushItemWidth(math.max(80, ui.availableSpaceX() - 70))
      width_pushed = true
    end
    ui.combo('##setups', preview, function()
      for i = 1, #setup_entries do
        if ui.selectable(setup_entries[i].label, i == setup_pick) then
          setup_pick = i
          setup_selected = setup_entries[i].path
        end
      end
    end)
    if width_pushed and ui.popItemWidth ~= nil then ui.popItemWidth() end
  else
    ui.text(preview)
  end
  ui.sameLine(0, 8)
  if ui.button('Load') then
    if current == nil then
      state.notice = 'No setup selected'
    else
      load_chosen_setup(current.path, 'Loaded ' .. current.label)
    end
  end
  draw_diff_ratio()
end

local function load_saved_setup()
  if setup_loaded or ac.loadSetup == nil then
    setup_loaded = true
    return
  end
  if ac.isCarResetAllowed ~= nil then
    local ok, allowed = pcall(ac.isCarResetAllowed)
    if not ok or allowed ~= true then return end
  end
  local car = player_car_id()
  local root = setups_root()
  if car == nil or root == nil then return end
  local base = root .. '/' .. car .. '/'
  local relative = setup_slot.relative(current_track_folder(), function(path)
    return file_exists(base .. path)
  end)
  setup_loaded = true
  if relative == nil then return end
  pcall(ac.loadSetup, relative)
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
  local chase_start = state.chase_start
  if chase_start == nil or physics == nil then return end
  local pose = { pos = chase_start.pos, dir = chase_start.dir, vel = { x = 0, y = 0, z = 0 } }
  move_car(0, pose, pose.vel)
  call(physics.engageGear, 0, 0)
end

local function lead_car_id()
  return recorded_car_id or player_car_id()
end

local function ensure_lead()
  local id = lead_car_id()
  if id == nil then return false end
  if recorded_car_id == nil then recorded_car_id = id end
  return lead_visual.ensure(id)
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
    state.notice = 'No lead run recorded'
    return
  end
  local folder = ensure_runs_folder()
  local name = sanitize_name(run_name)
  local path = folder .. '/' .. name .. '.lead'
  local payload, err = logic.pack(state, {
    carId = recorded_car_id or player_car_id() or '',
    trackId = track_id(),
    skinName = recorded_skin,
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
    state.notice = err or 'Bad lead run file'
    return
  end
  local ok_pack, meta, aerr = pcall(logic.apply_pack, state, payload, { trackId = track_id() })
  if not ok_pack or meta == nil then
    state.notice = aerr or 'Bad file'
    return
  end
  if meta.carId ~= nil and meta.carId ~= '' then
    recorded_car_id = meta.carId
  end
  recorded_skin = meta.skinName or ''
  lead_visual.set_skin(recorded_skin)
  lead_visual.hide()
  if not ensure_lead() then
    state.notice = lead_visual.status()
    return
  end
  lead_visual.hide()
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
    recorded_skin = player_skin()
    lead_visual.set_skin(recorded_skin)
  end
  if action == logic.CLEAR or (action == logic.RECORD and state.recording) then
    lead_visual.hide()
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
    ac.StructItem.key('soloTandems.v1'),
    seq = ac.StructItem.int32(),
    action = ac.StructItem.int32(),
  })
  if ok then deck = link end
end

local function deck_action()
  ensure_deck()
  if deck == nil then return end
  if not logic.sync_deck(deck_link, deck.seq) then return end
  local action = ACTIONS[deck.action]
  if action ~= nil then press(action) end
end

function script.update(dt)
  load_saved_setup()
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

  lead_visual.set_contact(settings ~= nil and settings.contact == true)
  local pose = logic.lead_position(state, dt)
  if pose == nil then
    lead_visual.hide()
  elseif ensure_lead() then
    if lead_visual.is_model_notice(state.notice) then
      state.notice = state.playing and 'Lead is running' or 'Lead is waiting'
    end
    lead_visual.show(pose, dt)
  else
    lead_visual.show_stand_in(pose, dt)
    state.notice = lead_visual.status()
  end
end

function script.draw3D()
  lead_visual.draw_glows()
  lead_visual.draw_stand_in()
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
  ui.text('Lead: ' .. tostring(lead_visual.status()))
  ui.text('Lead car: ' .. tostring(lead_car_id() or 'none'))
  if ui.checkbox ~= nil then
    local shown = settings ~= nil and settings.contact == true
    ui.checkbox('Lead contact', shown)
    if ui.itemClicked ~= nil and ui.itemClicked() then
      if settings ~= nil then settings.contact = not shown end
      lead_visual.set_contact(not shown)
    end
  end

  ui.separator()
  if ui.button('Record') then press(logic.RECORD) end
  ui.sameLine(0, 8)
  if ui.button('Spawn') then press(logic.SPAWN) end
  ui.sameLine(0, 8)
  if ui.button('Start') then press(logic.START) end
  if ui.button('Chase') then press(logic.CHASE) end
  ui.sameLine(0, 8)
  if ui.button('Teleport') then press(logic.TELEPORT) end
  ui.sameLine(0, 8)
  if ui.button('Clear') then press(logic.CLEAR) end

  draw_setups()

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
