local SERVICES <const> = {
  cache = Siku.cache,
  permissions = Siku.permissions,
  bucket = Siku.bucket,
  command = Siku.command,
  migration = Siku.migration,
  persistence = Siku.persistence,
  jobs = Siku.jobs,
  accounts = Siku.accounts,
  licenses = Siku.licenses,
}

exports('objectExport', function()
  return SERVICES
end)
