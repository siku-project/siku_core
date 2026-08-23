local INIT_STATE_KEY <const> = 'siku:state:initVehicle'
local PROPERTIES_STATE_KEY <const> = 'siku:state:setVehicleProperties'

--- Initialize a vehicle from the server via StateBag sync.
--- Handles placing on ground, freezing position, and applying properties on the client.
---@param networkId number The network ID of the vehicle.
---@param options? InitVehicleOptions Initialization options { placeOnGround?, freezePosition?, props?, fixVehicle? }.
local function initVehicle(networkId, options)
  local entity <const> = NetworkGetEntityFromNetworkId(networkId)

  if not entity or not DoesEntityExist(entity) then
    Siku.print.throw(('Cannot init vehicle: network ID %d does not resolve to an entity'):format(networkId))
  end

  Entity(entity).state:set(INIT_STATE_KEY, options or {}, true)
end

--- Apply vehicle properties from the server via StateBag sync.
--- The properties are automatically applied on the client that owns the entity.
---@param vehicle number The server-side vehicle entity handle.
---@param props VehicleProperties The vehicle properties to apply.
---@param fixVehicle? boolean Fix the vehicle after props have been set.
local function setVehicleProperties(vehicle, props, fixVehicle)
  if not DoesEntityExist(vehicle) then
    Siku.print.throw(('Cannot set vehicle properties: entity %d does not exist'):format(vehicle))
  end

  Entity(vehicle).state:set(PROPERTIES_STATE_KEY, {
    props = props,
    fixVehicle = fixVehicle or false,
  }, true)
end

return {
  init = initVehicle,
  setProperties = setVehicleProperties,
}
