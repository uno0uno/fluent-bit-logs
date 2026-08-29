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

local function keep_fluentbit_signal(log)
  if type(log) ~= 'string' then
    return false
  end
  -- Fluent Bit levels look like: [error]  [ warn]  [ info]
  if log:find('%[error%]') or log:find('%[ warn%]') then
    return true
  end
  local lower = log:lower()
  return lower:find('failed connecting', 1, true)
      or lower:find('overlimit', 1, true)
      or lower:find('output initialization failed', 1, true)
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
    -- Drop Fluent Bit *info* self-tail (feedback loop). Keep warn/error
    -- so Postgres-down / mem-buf-overlimit at boot remains queryable.
    if name:find('fluent%-bit', 1, false) or name == 'fluent-bit-logs' then
      if keep_fluentbit_signal(record['log']) then
        return 2, timestamp, record
      end
      return -1, timestamp, record
    end
  end

  return 2, timestamp, record
end

-- Host journal/syslog: keep reboot/OOM/panic/reset signals only.
function keep_host(tag, timestamp, record)
  local msg = record['MESSAGE'] or record['log'] or record['message'] or ''
  if type(msg) ~= 'string' then
    msg = tostring(msg)
  end
  local m = msg:lower()
  local needles = {
    'reboot',
    'shutdown',
    'power-off',
    'out of memory',
    'oom-kill',
    'oom-killer',
    'kernel panic',
    'hardware error',
    'device reset',
    'power-on or device reset',
    'hypervisor detected',
    'unattended-upgrade',
    'watchdog',
  }
  for i = 1, #needles do
    if m:find(needles[i], 1, true) then
      record['source'] = 'host'
      if record['MESSAGE'] and not record['log'] then
        record['log'] = record['MESSAGE']
      end
      return 2, timestamp, record
    end
  end
  return -1, timestamp, record
end
