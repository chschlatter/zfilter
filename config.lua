
options.zfilter = {
	min_update_interval = 60 * 60 * 6, -- seconds,
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

-- Return a timezone string in ISO 8601:2000 standard form (+hhmm or -hhmm)
local function get_tzoffset()
  local now = os.time()
  local tz = os.difftime(now, os.time(os.date("!*t", now)))
  local h, m = math.modf(tz / 3600)
  return string.format("%+.4d", 100 * h + 60 * m)
end

-- Print msg and insert it into loglines
-- to_email == True: send email with loglines and reset loglines
local function log (msg, to_email)
	loglines = loglines or {}

	if msg then
		print(msg)
		table.insert(loglines, os.date("%y-%m-%d %H%M ") .. get_tzoffset() .. " " .. msg)
	end

	if to_email then
		table.insert(loglines, 1, "From: log@imapfilter")
  	table.insert(loglines, 2, "Subject: imapfilter log")
  	table.insert(loglines, 3, "Date: " .. os.date("%a, %d %b %Y %X ") .. get_tzoffset())
  	table.insert(loglines, 4, "")
  	if not account.INBOX:append_message(table.concat(loglines, "\r\n")) then
  		print("log_email(): account.INBOX:append_message() failed.")
  	end
  	loglines = {}
	end
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

local function update_folder_rules (folder, old_rules)
	local new_rules = {}
	old_rules = old_rules or {}
	local mails = account[folder]:select_all()

	-- check existing rules
	for _, from_addr in ipairs(old_rules) do
		local results = mails:contain_from(from_addr)
		if #results > 0 then
			new_rules[#new_rules + 1] = from_addr
			mails = mails - results
		else
			log("update_rules(): DELETE 'From: " .. from_addr .. "' -> " .. folder)
		end
	end

	-- check remaining messages in folder
	while #mails > 0 do
		local mbox, uid = table.unpack(table.remove(mails))
		local from_addr = get_from_addr(mbox, uid)
		new_rules[#new_rules + 1] = from_addr
		log("update_rules(): ADD 'From: " .. from_addr .. "' -> " .. folder)
		mails = mails - mails:contain_from(from_addr)
	end

	return new_rules
end

local function update_all_rules (root_folder, old_rules)
	local new_rules = {}
	old_rules = old_rules or {}
	local start_time = os.time()

	for _, folder in ipairs(get_subfolders(root_folder)) do
		new_rules[folder] = update_folder_rules(folder, old_rules[folder])
	end
	log("update_all_rules(): completed in " ..
		os.difftime(os.time(), start_time) .. " seconds.")

	local conso_rules = {}
	for folder, folder_rules in pairs(new_rules) do
		for _, from_addr in ipairs(folder_rules) do
			if conso_rules[from_addr] then
				log("update_all_rules(): found DUPLICATE rule 'From: " ..
					from_addr .. "' -> " .. conso_rules[from_addr] .. " and " ..
					folder .. "\n  IGNORING " .. folder)
			else
				conso_rules[from_addr] = folder
			end
		end
	end

	log("update_all_rules(): listing all rules ...")
	for from_addr, folder in pairs(conso_rules) do
		log("  'From: " .. from_addr .. "' -> " .. folder)
	end

	return new_rules, conso_rules
end

local function apply_rules_all (mbox, conso_rules)
	conso_rules = conso_rules or {}
	local start_time = os.time()
	local rules_count = 0

	for from_addr, folder in pairs(conso_rules) do
		rules_count = rules_count + 1
		local mails = mbox:contain_from(from_addr)
		if #mails > 0 then
			log("apply_rules_all(): Moving " .. #mails .. " mail(s) with From: " ..
				from_addr .. " to folder " .. folder .. ".")
			mails:move_messages(account[folder])
		end
	end
	log("apply_rules_all(): applied " .. rules_count .. " rules in " .. 
		os.time() - start_time .. " secs.")
end

local function apply_rules_unseen (mbox, conso_rules)
	conso_rules = conso_rules or {}
	local start_time = os.time()
	local rules_count = 0
	local mails = account.INBOX:is_unseen()
	local unseen_mails = #mails

	while #mails > 0 do
		local mbox, uid = table.unpack(mails[1])
		local from_addr = get_from_addr(mbox, uid)
		local folder = conso_rules[from_addr]
		if folder then
			rules_count = rules_count + 1
			local results = mails:contain_from(from_addr)
			if #resulst > 0 then
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


local rules, conso_rules
local timers = { 
	rules_last_updated = 0,
	rules_last_applied_all = 0,
	email_last_sent = 0 }

while true do
	-- UPDATE rules
	if os.difftime(os.time(), timers.rules_last_updated) >
		options.zfilter.min_update_interval
	then
		rules, conso_rules = update_all_rules(options.zfilter.root_imap_folder, rules)
		timers.rules_last_updated = os.time()
	end

  -- APPLY rules
	if os.difftime(os.time(), timers.rules_last_applied_all) > 
		options.zfilter.min_apply_rules_all_interval 
	then
		apply_rules_all(account.INBOX, conso_rules)
		timers.rules_last_applied_all = os.time()
	else
		apply_rules_unseen(account.INBOX, conso_rules)
	end

	-- SEND log email
	if os.difftime(os.time(), timers.email_last_sent) >
		options.zfilter.min_email_log_interval
	then
		log(nil, true)
		timers.email_last_sent = os.time()
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
