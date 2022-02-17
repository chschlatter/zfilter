
options.zfilter = {
  min_update_interval = 60 * 60 * 24, -- seconds,
  root_imap_folder = "Topics",
  min_email_log_interval = 60 * 60 * 24, -- seconds
  min_apply_rules_all_interval = 60 * 60 * 24 -- seconds
}

-- global IMAP account
local status, imap_password = pipe_from('cat .imap_password')
imap_password = string.match(imap_password, "(.+)[\n\r]$") -- remove trailing newline
local account = IMAP {
  server = "secure.emailsrvr.com",
  username = "ch@schlatter.net",
  password = imap_password,
  port = 993,
  ssl = "tls1"
}

local Log = { loglines = {} }

-- timezone string in ISO 8601:2000 standard form (+hhmm or -hhmm)
function Log:get_tz_str()
  local tz_secs = os.difftime(os.time(), os.time(os.date("!*t", now)))
  local h, m = math.modf(tz_secs / 3600)
  return string.format("%+.4d", 100 * h + 60 * m)
end

-- print msg and add to loglines array for later inclusion in log email
function Log:add(msg)
  if not msg then return nil, "no msg provided to log" end

  local tz_secs = os.difftime(os.time(), os.time(os.date("!*t", now)))
  local h, m = math.modf(tz_secs / 3600)
  local tz_str = string.format("%+.4d", 100 * h + 60 * m)

  print(msg)
  table.insert(self.loglines, os.date("%y-%m-%d %H%M ") .. self:get_tz_str() .. " " .. msg)
end

-- shortcut for Log:add()
local function log(msg) Log:add(msg) end

-- append log email to mbox including loglines
function Log:mail(mbox)
  table.insert(self.loglines, 1, "From: log@imapfilter")
  table.insert(self.loglines, 2, "Subject: imapfilter log")
  table.insert(self.loglines, 3, "Date: " .. os.date("%a, %d %b %Y %X ") .. self:get_tz_str())
  table.insert(self.loglines, 4, "")
  if not mbox:append_message(table.concat(self.loglines, "\r\n")) then
    print("Log:mail(): mbox:append_message() failed.")
  end
  self.loglines = {}
end

local function get_subfolders (folder, result)
  result = result or {}
  local mbox_names, folders = account:list_all(folder)
  for _, sub_folder in ipairs(folders) do
    get_subfolders(sub_folder, result)
  end
  for _, mbox_name in ipairs(mbox_names) do
    table.insert(result, mbox_name)
  end
  return result
end

local function get_from_addr (mbox, uid)
  local from_field = mbox[uid]:fetch_field("From")
  -- (very) loose addr-spec parsing here (see details at 
  -- https://datatracker.ietf.org/doc/html/rfc5322#section-3.4.1,
  -- and "loose" spec at http://hm2k.com/posts/what-is-a-valid-email-address )
  return string.match(from_field, "<?(%S+@[%w%.-]+)>?")
end

local Rules = {
  rules = {},
  conso_rules = {},
  old_rules = {},
  root_folder = options.zfilter.root_imap_folder
}

function Rules:update_by_folder (folder)
  local new_rules = {}
  local old_folder_rules = self.old_rules[folder] or {}
  local mails = account[folder]:select_all()

  -- check existing rules
  for _, from_addr in ipairs(old_folder_rules) do
    local results = mails:contain_from(from_addr)
    if #results > 0 then
      new_rules[#new_rules + 1] = from_addr
      mails = mails - results
    else
      log("Rules:update_by_folder(): DELETE 'From: " .. from_addr .. "' -> " .. folder)
    end
  end    

  -- check remaining messages in folder
  while #mails > 0 do
    local mbox, uid = table.unpack(table.remove(mails))
    local from_addr = get_from_addr(mbox, uid)
    new_rules[#new_rules + 1] = from_addr
    log("Rules:update_by_folder(): ADD 'From: " .. from_addr .. "' -> " .. folder)
    mails = mails - mails:contain_from(from_addr)
  end

  self.rules[folder] = new_rules
end

function Rules:update_all ()
  local start_time = os.time()
  self.old_rules = self.rules
  self.rules = {}

  for _, folder in ipairs(get_subfolders(self.root_folder)) do
    self:update_by_folder(folder)
  end
  log("Rules:update_all(): completed in " ..
    os.difftime(os.time(), start_time) .. " seconds.")

  local conso_rules = {}
  for folder, folder_rules in pairs(self.rules) do
    for _, from_addr in ipairs(folder_rules) do
      if conso_rules[from_addr] then
        log("Rules:update_all(): found DUPLICATE rule 'From: " ..
          from_addr .. "' -> " .. conso_rules[from_addr] .. " and " ..
          folder .. "\n  IGNORING " .. folder)
      else
        conso_rules[from_addr] = folder
      end
    end
  end
  self.conso_rules = conso_rules
end

function Rules:apply_all (mbox)
  local start_time = os.time()
  local rules_count = 0

  for from_addr, folder in pairs(self.conso_rules) do
    rules_count = rules_count + 1
    local mails = mbox:contain_from(from_addr)
    if #mails > 0 then
      log("Rules:apply_all(): Moving " .. #mails .. " mail(s) with From: " ..
        from_addr .. " to folder " .. folder .. ".")
      mails:move_messages(account[folder])
    end
  end
  log("Rules:apply_all(): applied " .. rules_count .. " rules in " .. 
    os.time() - start_time .. " secs.")
end

function Rules:apply_unseen (mbox)
  local start_time = os.time()
  local rules_count = 0
  local mails = mbox:is_unseen()
  local unseen_mails = #mails

  while #mails > 0 do
    local _, uid = table.unpack(mails[#mails])
    local from_addr = get_from_addr(mbox, uid)
    local folder = self.conso_rules[from_addr]

    if folder then
      rules_count = rules_count + 1
      local results = mails:contain_from(from_addr)
      if #results > 0 then
        log("apply_rules_unseen(): Moving " .. #results .. " mail(s) with From: " ..
          from_addr .. " to folder " .. folder .. ".")
        results:move_messages(account[folder])
        mails = mails - results
      end
    else
      table.remove(mails)
    end
  end
  log("apply_rules_unseen(): applied " .. rules_count .. " rules " ..
    " on " .. unseen_mails .. " unseen mails, in " .. 
    os.time() - start_time .. " secs.")
end

local function interval_timer (min_interval)
  local reset_time = 0
  return function ()
    if os.difftime(os.time(), reset_time) > min_interval then
      reset_time = os.time()
      return true
    else
      return false
    end
  end
end

local timers = {
  update = interval_timer(options.zfilter.min_update_interval),
  apply = interval_timer(options.zfilter.min_apply_rules_all_interval),
  email = interval_timer(options.zfilter.min_email_log_interval),
}

while true do
  -- UPDATE rules
  if timers.update() then
    Rules:update_all()
  end

  -- APPLY rules
  if timers.apply() then
    Rules:apply_all(account.INBOX)
  else
    Rules:apply_unseen(account.INBOX)
  end

  -- SEND log email
  if timers.email() then
    Log:mail(account.INBOX)
  end

  update, event = account.INBOX:enter_idle()
  if not update then
    print("Server does not support IMAP IDLE. Sleeping ...")
    sleep(600)
  elseif not event then
     print("*** SIGUSR1/2 received. ***")
  else
     print("*** IMAP Event [" .. event .. "] ***")
  end
end
