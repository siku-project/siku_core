local STATES <const> = {
  VALID = 'valid',
  SUSPENDED = 'suspended',
  REVOKED = 'revoked',
  EXPIRED = 'expired',
}

local CLIENT_EVENT <const> = 'siku:client:licensesUpdated'

local CALLBACKS <const> = {
  MY_LICENSES = 'siku:callback:myLicenses',
  DEFINITION = 'siku:callback:licenseDefinition',
  DEFINITIONS = 'siku:callback:licenseDefinitions',
}

internal.STATES = STATES
internal.CLIENT_EVENT = CLIENT_EVENT
internal.CALLBACKS = CALLBACKS

function internal.findHolding(holdings, licenseName)
  for index = 1, #holdings do
    if holdings[index].license == licenseName then
      return holdings[index]
    end
  end

  return nil
end

return {
  STATES = STATES,
}
