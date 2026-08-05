-- Enrich Docker json-file logs with container_id + container_name.
-- Reads /var/lib/docker/containers/<id>/config.v2.json (already mounted read-only).
-- Caches successful name lookups in-process.
-- Note: Lua patterns are NOT PCRE — do not use {64} quantifiers.

local DOCKER_DIR = '/var/lib/docker/containers/'
local cache = {}

local function container_id_from_tag(tag)
  if type(tag) ~= 'string' then
    return nil
  end
  -- Prefer Tag_Regex form: docker.<id>
  local id = tag:match('^docker%.(%x+)$')
  if id and #id >= 12 then
    return id
  end
  -- Fallback: first 64-char hex run anywhere in tag
  id = tag:match('(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)')
  return id
end

local function read_container_name(container_id)
  local path = DOCKER_DIR .. container_id .. '/config.v2.json'
  local fh = io.open(path, 'r')
  if not fh then
    return nil
  end
  local content = fh:read('*a')
  fh:close()
  if not content or content == '' then
    return nil
  end
  local name = content:match('"LogPath"%s*:%s*"[^"]*"%s*,%s*"Name"%s*:%s*"/?([^"]+)"')
  if not name then
    name = content:match('"Name"%s*:%s*"/?([^"]+)"')
  end
  return name
end

function enrich(tag, timestamp, record)
  local id = container_id_from_tag(tag)
  if not id then
    return 2, timestamp, record
  end

  record['container_id'] = id

  local name = cache[id]
  if name == nil then
    name = read_container_name(id)
    if name and name ~= '' then
      cache[id] = name
    end
  end

  if name and name ~= '' then
    record['container_name'] = name
  end

  return 2, timestamp, record
end
