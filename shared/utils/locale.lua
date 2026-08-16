local translations = {}

local file <const> =
  LoadResourceFile(GetCurrentResourceName(), ('translations/%s.lua'):format(TranslationConfig.language))

if file then
  local fn <const> = load(file)
  if fn then
    translations = fn() or {}
  end
end

--- Get a translated string by key. Supports string.format placeholders.
---@param key string The translation key.
---@vararg any Format arguments.
---@return string text The translated text or the key itself if not found.
function T(key, ...)
  local text <const> = translations[key]
  if not text then
    return key
  end
  if select('#', ...) > 0 then
    return text:format(...)
  end
  return text
end
