local SERVICES <const> = {
  cache = Siku.cache,
  permissions = Siku.permissions,
  bucket = Siku.bucket,
  command = Siku.command,
  migration = Siku.migration,
  persistence = Siku.persistence,
}

exports('objectExport', function()
  return SERVICES
end)
