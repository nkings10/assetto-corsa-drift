-- Paste the body of apply_lead into the Stream Deck listener's apply_effect.
-- A deck key sends one effect name. This writes the matching action for the lead chase app.
-- Both sides use ac.connect key leadChase.v1: seq int32, action int32.

local LEAD = {
  lead_record = 1,
  lead_appear = 2,
  lead_spot = 3,
  lead_teleport = 4,
  lead_start = 5,
  lead_clear = 6,
}

local lead_link = nil

local function apply_lead(effect)
  local action = LEAD[effect]
  if action == nil then return false end
  if ac == nil or ac.connect == nil or ac.StructItem == nil then return false, 'no shared state' end
  if lead_link == nil then
    local ok, link = pcall(ac.connect, {
      ac.StructItem.key('leadChase.v1'),
      seq = ac.StructItem.int32(),
      action = ac.StructItem.int32(),
    })
    if not ok or link == nil then return false, 'no shared state' end
    lead_link = link
  end
  lead_link.action = action
  lead_link.seq = lead_link.seq + 1
  return true
end

return {
  apply_lead = apply_lead,
}
