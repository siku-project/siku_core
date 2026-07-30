local STATE_KEY <const> = 'siku:state:initVehicle'

---@class InitVehicleOptions
---@field placeOnGround? boolean Place the vehicle on the ground properly (default: true).
---@field freezePosition? boolean Freeze the vehicle position after init.
---@field props? VehicleProperties Vehicle properties to apply after init.
---@field fixVehicle? boolean Fix the vehicle after applying props.

--- Handle StateBag sync from server for vehicle initialization.
AddStateBagChangeHandler(STATE_KEY, '', function(bagName, _, value)
  if not value then return end

  while NetworkIsInTutorialSession() do Wait(0) end

  local vehicle <const> = Siku.WaitFor(function()
    local entity <const> = GetEntityFromStateBagName(bagName)
    if entity and entity > 0 then return entity end
  end, ('Failed to resolve entity from StateBag \'%s\''):format(bagName), 10000)

  if not vehicle then return end

  Siku.WaitFor(function()
    if not IsEntityWaitingForWorldCollision(vehicle) then return true end
  end, nil, 5000)

  if NetworkGetEntityIsNetworked(vehicle) and NetworkGetEntityOwner(vehicle) ~= PlayerId() then return end

  if value.placeOnGround ~= false then
    SetVehicleOnGroundProperly(vehicle)
  end

  if value.freezePosition then
    FreezeEntityPosition(vehicle, true)
  end

  if value.props then
    Siku.SetVehicleProperties(vehicle, value.props, value.fixVehicle)
  end

  Wait(200)
  Entity(vehicle).state:set(STATE_KEY, nil, true)
end)
