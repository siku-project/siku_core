PermissionSeedConfig = {
  --- Default roles and permissions seeded into the database on first boot.
  --- After seeding, the database is the source of truth — changes made via
  --- the API (createRole, addPermissionToRole, etc.) persist in the DB.
  ---
  --- Role types:
  ---   isPrimary = true  → hierarchical role, only ONE per character, uses inheritance chain
  ---   isPrimary = false → secondary role, MULTIPLE per character, no inheritance, additive permissions
  ---
  --- Permission format: something.something (e.g., "chat.staff", "police.mdt_access").
  --- The dot separator is required for wildcards to work.
  ---
  --- Wildcards:
  ---   "chat.*"   → all permissions starting with "chat."
  ---   "*.staff"  → any permission ending with ".staff"
  ---   "*"        → ALL permissions (superadmin)
  --- Negation:
  ---   "-chat.staff" → explicitly denies this permission even if a wildcard grants it
  ---
  --- Inheritance: inheritsFrom creates a hierarchy chain.
  ---   Owner > Admin > Dev > Moderator > User
  ---   Each role inherits ALL permissions from its parent (and parent's parent, etc.)
  roles = {
    -- Primary Roles (hierarchical, one per character, inheritance chain)

    {
      name = 'user',
      label = 'User',
      isPrimary = true,
      permissions = {},
    },
    {
      name = 'moderator',
      label = 'Moderator',
      isPrimary = true,
      inheritsFrom = 'user',
      permissions = {
        'chat.staff',
      },
    },
    {
      name = 'dev',
      label = 'Developer',
      isPrimary = true,
      inheritsFrom = 'moderator',
      permissions = {},
    },
    {
      name = 'admin',
      label = 'Administrator',
      isPrimary = true,
      inheritsFrom = 'dev',
      permissions = {},
    },
    {
      name = 'owner',
      label = 'Owner',
      isPrimary = true,
      inheritsFrom = 'admin',
      permissions = {
        '*',
      },
    },

    -- Secondary Roles (flat, multiple per character, no inheritance, additive)

    {
      name = 'event_manager',
      label = 'Event Manager',
      isPrimary = false,
      permissions = {},
    },
    {
      name = 'support',
      label = 'Support',
      isPrimary = false,
      permissions = {},
    },
    {
      name = 'recruiter',
      label = 'Recruiter',
      isPrimary = false,
      permissions = {},
    },
  },
}
