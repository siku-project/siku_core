local CORE <const> = 'siku_core'
local SERVICES_EXPORT <const> = 'objectExport'

local service <const> = exports[CORE][SERVICES_EXPORT]().licenses

local License <const> = Siku.class('License')

function License:constructor(name)
  self.name = name
end

function License:register(definition)
  local declaration <const> = {}

  for key, value in pairs(definition) do
    declaration[key] = value
  end

  declaration.name = self.name

  return service.register(declaration)
end

function License:exists()
  return service.exists(self.name)
end

function License:isActive()
  return service.isActive(self.name)
end

function License:getDefinition()
  return service.getDefinition(self.name)
end

function License:getHolders()
  return service.getHolders(self.name)
end

function License:countHolders()
  return service.countHolders(self.name)
end

function License:isHeldBy(characterId)
  return service.has(characterId, self.name)
end

function License:isValidFor(characterId)
  return service.isValid(characterId, self.name)
end

function License:getHolding(characterId)
  return service.getHolding(characterId, self.name)
end

function License:getPoints(characterId)
  return service.getPoints(characterId, self.name)
end

function License:issue(characterId, options)
  return service.issue(characterId, self.name, options)
end

function License:suspend(characterId, options)
  return service.suspend(characterId, self.name, options)
end

function License:lift(characterId, context)
  return service.lift(characterId, self.name, context)
end

function License:revoke(characterId, context)
  return service.revoke(characterId, self.name, context)
end

function License:withdraw(characterId, context)
  return service.withdraw(characterId, self.name, context)
end

function License:setMetadata(characterId, metadata)
  return service.setMetadata(characterId, self.name, metadata)
end

function License:setExpiry(characterId, expiresAt, context)
  return service.setExpiry(characterId, self.name, expiresAt, context)
end

function License:addPoints(characterId, amount, context)
  return service.addPoints(characterId, self.name, amount, context)
end

function License:removePoints(characterId, amount, context)
  return service.removePoints(characterId, self.name, amount, context)
end

function License:setPoints(characterId, points, context)
  return service.setPoints(characterId, self.name, points, context)
end

local namespace <const> = {}

for key, value in pairs(service) do
  namespace[key] = value
end

function namespace.get(name)
  return License.new(name)
end

return namespace
