dofile("urlcode.lua")
dofile("table_show.lua")

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')

local username = nil
local username_escaped = nil
local username_id_urls = {}
local allowed_strings = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

allowed_strings[item_value] = true

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
     or string.match(url, "[<>\\]")
     or string.match(url, "//$")
     or not string.match(url, "^https?://[^/]*ipernity%.com") then
    return false
  end

  if string.match(url, "%?lc=[01]")
     or string.match(url, "/in/favorite/") then
    return false
  end

  --if username_escaped ~= nil and (string.match(url, "^(.+[^a-zA-Z0-9%.%-_])" .. username_escaped .. "$")
  --   or string.match(url, "^(.+[^a-zA-Z0-9%.%-_])" .. username_escaped .. "([^a-zA-Z0-9%.%-_].+)")) then
  --  for s in string.gmatch(url, "([0-9]+)") do
  --    allowed_strings[s] = true
  --  end
  --end

  for s in string.gmatch(url, "([0-9]+)") do
    if allowed_strings[s] == true then
      return true
    end
  end

  for s in string.gmatch(url, "([a-zA-Z0-9%-%._]+)") do
    if allowed_strings[s] == true then
      return true
    end
  end

  if string.match(url, "^https?://api%.ipernity%.com") then
    return true
  end

  if string.match(url, "^https?://cdn%.ipernity%.com")
     and parenturl ~= nil
     and not (string.match(parenturl, "/favorite/")
      or string.match(parenturl, "/favorite$")
      or string.match(url, "%.buddy%.jpg$")) then
    return true
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if username_escaped ~= nil
     and (string.match(parent["url"], "/favorite/") or string.match(parent["url"], "/favorite$")) then
    return false
  end

  if string.match(url, "%.buddy%.jpg$") then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    if (downloaded[url] ~= true and addedtolist[url] ~= true)
       and allowed(url, origurl) then
      table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
      addedtolist[url] = true
      addedtolist[string.gsub(url, "&amp;", "&")] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  if string.match(url, "&amp;") then
    check(string.gsub(url, "&amp;", "&"))
  end

  if string.match(url, "[^0-9]75x") and string.match(url, "%?r2$") then
    check(string.match(url, "^([^%?]+)"))
  end
  
  if (allowed(url, nil) or username == nil) and not string.match(url, "^https?://cdn%.ipernity%.com") then
    html = read_file(file)

    for newuserid in string.gmatch(html, '"user_id":"([0-9]+)"') do
      if newuserid ~= tostring(item_value) then
        return urls
      end
    end

    if string.match(url, "^https?://api%.ipernity%.com") then
      os.execute("sleep 0.2")

      if string.match(html, 'ok="0"') or string.match(html, 'status="error"') then
        abortgrab = true
      end
    end

    if username == nil and string.match(url, "^https?://[^/]*ipernity%.com/home/") then
      username = string.match(html, '"user_id"%s*:%s*' .. item_value .. '%s*,%s*"folder"%s*:%s*"([^"]+)"')
      username_escaped = string.gsub(username, "([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
      allowed_strings[username] = true
    end

    if string.match(html, '"mediakey"%s*:%s*"[^"]+"') then
      local mediakey = string.match(html, '"mediakey"%s*:%s*"([^"]+)"')
      local is_image = true
      for embed_extension in string.gmatch(html, '"embed"%s*:%s*"([^"]*)"') do
        if embed_extension ~= "jpg" then
          is_image = false
        end
      end
      if not is_image then
--        for _, lang in ipairs({"ca", "cs", "zh", "de", "en", "es", "eo", "el", "fr", "gl", "it", "nl", "pt", "pl", "sv", "ru"}) do
        for _, lang in ipairs({"en"}) do
--          for _, external in ipairs({"0", "1"}) do
          for _, external in ipairs({"0"}) do
--            for _, autostart in ipairs({"true", "false"}) do
            for _, autostart in ipairs({"true"}) do
              check("http://api.ipernity.com/media.php/" .. mediakey .. "?lang=" .. lang .. "&external=" .. external .. "&autostart=" .. autostart)
              check("http://api.ipernity.com/media.php/" .. mediakey .. "?lang=" .. lang .. "&external=" .. external)
            end
          end
        end
      end
    end

    for start in string.gmatch(url, "^(.+[^a-zA-Z0-9%.%-_])" .. username_escaped .. "$") do
      check(start .. item_value)
    end 
    for start, end_ in string.gmatch(url, "^(.+[^a-zA-Z0-9%.%-_])" .. username_escaped .. "([^a-zA-Z0-9%.%-_].+)") do
      check(start .. item_value ..  end_)
    end 

    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
  end

  if status_code == 302 and username_id_urls[url["url"]] == true then
    return wget.actions.EXIT
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 403 and status_code ~= 404 and status_code ~= 410) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end