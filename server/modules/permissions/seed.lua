--- Seed default roles and permissions into the database if no roles exist yet.
function _SikuInternal.SeedPermissions()
  local existingRoles <const> = MySQL.query.await('SELECT * FROM roles')
  if #existingRoles > 0 then
    Siku.print.info('Roles already seeded, skipping')
    return
  end

  Siku.print.info('Seeding default roles and permissions')

  local roleNameToId <const> = {}

  for i = 1, #PermissionSeedConfig.roles do
    local seedRole <const> = PermissionSeedConfig.roles[i]
    local result <const> = MySQL.query.await(
      'INSERT INTO roles (name, label, is_primary) VALUES (?, ?, ?)',
      { seedRole.name, seedRole.label, seedRole.isPrimary and 1 or 0 }
    )
    roleNameToId[seedRole.name] = result.insertId
  end

  for i = 1, #PermissionSeedConfig.roles do
    local seedRole <const> = PermissionSeedConfig.roles[i]
    if seedRole.inheritsFrom then
      local roleId <const> = roleNameToId[seedRole.name]
      local parentId <const> = roleNameToId[seedRole.inheritsFrom]
      if roleId and parentId then
        MySQL.query.await('UPDATE roles SET inherits_from = ? WHERE id = ?', { parentId, roleId })
      end
    end
  end

  local permNameToId <const> = {}

  for i = 1, #PermissionSeedConfig.roles do
    local seedRole <const> = PermissionSeedConfig.roles[i]
    for j = 1, #seedRole.permissions do
      local permName <const> = seedRole.permissions[j]
      if not permNameToId[permName] then
        local existing <const> = MySQL.single.await('SELECT * FROM permissions WHERE name = ?', { permName })
        if existing then
          permNameToId[permName] = existing.id
        else
          local result <const> = MySQL.query.await('INSERT INTO permissions (name) VALUES (?)', { permName })
          permNameToId[permName] = result.insertId
        end
      end
    end
  end

  for i = 1, #PermissionSeedConfig.roles do
    local seedRole <const> = PermissionSeedConfig.roles[i]
    local roleId <const> = roleNameToId[seedRole.name]
    if roleId then
      for j = 1, #seedRole.permissions do
        local permId <const> = permNameToId[seedRole.permissions[j]]
        if permId then
          MySQL.query.await('INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)', { roleId, permId })
        end
      end
    end
  end

  local roleCount = 0
  for _ in pairs(roleNameToId) do roleCount = roleCount + 1 end
  local permCount = 0
  for _ in pairs(permNameToId) do permCount = permCount + 1 end

  Siku.print.success(('Seeded %d roles and %d permissions'):format(roleCount, permCount))
end
