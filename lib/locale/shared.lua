local DEFAULT_LANGUAGE <const> = 'en'
local TRANSLATION_PATH <const> = 'translations/%s.lua'

local translations = nil

--- Resolve the language configured by the current resource, falling back
--- to the default one when it declares none.
---@return string language The language code.
local function resolveLanguage()
  local config <const> = TranslationConfig

  if type(config) == 'table' and type(config.language) == 'string' and config.language ~= '' then
    return config.language
  end

  return DEFAULT_LANGUAGE
end

--- Read the translation file of the current resource once, on first use.
---@return table translations The translation table, empty when the file is missing or invalid.
local function loadTranslations()
  if translations then
    return translations
  end

  translations = {}

  local language <const> = resolveLanguage()
  local path <const> = TRANSLATION_PATH:format(language)
  local source <const> = LoadResourceFile(Siku.name, path)

  if not source then
    Siku.log.warn('locale.missing', ("No translation file found for language '%s'"):format(language), {
      resource = Siku.name,
      language = language,
      path = path,
    }, { entities = { { type = 'resource', id = Siku.name, role = 'subject', label = Siku.name } } })
    return translations
  end

  local chunk <const>, err <const> = load(source, ('@@%s/%s'):format(Siku.name, path))

  if not chunk then
    Siku.log.error('locale.invalid', ("Unable to compile the translation file for language '%s': %s"):format(language, err), {
      resource = Siku.name,
      language = language,
      path = path,
      error = tostring(err),
    }, { file = path, entities = { { type = 'resource', id = Siku.name, role = 'subject', label = Siku.name } } })
    return translations
  end

  local loaded <const> = chunk()

  if type(loaded) == 'table' then
    translations = loaded
  end

  return translations
end

--- Get a translated string by key. Supports string.format placeholders.
---@param key string The translation key.
---@param ... any Format arguments.
---@return string text The translated text, or the key itself when it is unknown.
local function translate(key, ...)
  local text <const> = loadTranslations()[key]

  if not text then
    return key
  end

  if select('#', ...) > 0 then
    return text:format(...)
  end

  return text
end

return {
  translate = translate,
  translations = loadTranslations,
}
