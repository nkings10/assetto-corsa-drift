-- Paste the body of apply_solo_tandems into the Stream Deck listener's apply_effect.
-- A deck key sends one effect name. This writes the matching action for the Solo Tandems app.
-- Both sides use ac.connect key soloTandems.v1: seq int32, action int32.

local SOLO_TANDEMS = {
  solo_tandems_record = 1,
  solo_tandems_spawn = 2,
  solo_tandems_chase = 3,
  solo_tandems_teleport = 4,
  solo_tandems_start = 5,
  solo_tandems_clear = 6,
}

local solo_tandems_link = nil

local function apply_solo_tandems(effect)
  local action = SOLO_TANDEMS[effect]
  if action == nil then return false end
  if ac == nil or ac.connect == nil or ac.StructItem == nil then return false, 'no shared state' end
  if solo_tandems_link == nil then
    local ok, link = pcall(ac.connect, {
      ac.StructItem.key('soloTandems.v1'),
      seq = ac.StructItem.int32(),
      action = ac.StructItem.int32(),
    })
    if not ok or link == nil then return false, 'no shared state' end
    solo_tandems_link = link
  end
  solo_tandems_link.action = action
  solo_tandems_link.seq = solo_tandems_link.seq + 1
  return true
end

return {
  apply_solo_tandems = apply_solo_tandems,
}
