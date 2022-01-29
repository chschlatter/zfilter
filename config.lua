
options.zfilter = {
	min_update_interval = 60 * 60 * 6, -- seconds,
	root_imap_folder = "Topics",
	min_email_log_interval = 60 * 60 * 24 -- seconds
}

-- global IMAP account
local account = IMAP {
  server = "secure.emailsrvr.com",
  username = "ch@schlatter.net",
  password = "Unti 0001",
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

local function parse_from_addr (from_field)
	local from_addr = nil
	if (string.find(from_field, "(<.+>)")) then
    	_, _, from_addr = string.find(from_field, "(<.+>)")
    else
        _, _, from_addr = string.find(from_field, "From: (.+)")
    end
    return from_addr
end

local function update_rules (folder, existing_rules)
	local new_rules = {}
	local messages = account[folder]:select_all()
	existing_rules = existing_rules or {}

	local function log_rule(action, from_addr, folder, msg_count)
		log("update_rules(): " .. action .. " [" .. folder .. "] " .. 
			from_addr .. " ( " .. msg_count .. " message(s))")
	end

	-- check existing rules
	for _, from_addr in ipairs(existing_rules) do
		local results = account[folder]:contain_from(from_addr)
		if #results > 0 then
			table.insert(new_rules, from_addr)
			-- log_rule("KEEP", from_addr, folder, #results)
			messages = messages - results
		else
			log_rule("DELETE", from_addr, folder, 0)
		end
	end

	-- check remaining messages in folder
	while #messages > 0 do
		local mbox, uid = table.unpack(table.remove(messages))
		local from_field = mbox[uid]:fetch_field("From")
		local from_addr = parse_from_addr(from_field)
		if from_addr then
			local results = account[folder]:contain_from(from_addr)
			if #results > 0 then
				table.insert(new_rules, from_addr)
				messages = messages - results
				log_rule("ADD", from_addr, folder, #results)
			end -- else: malformed From: address
		end
	end

	return new_rules
end

local function update_all_rules(root_folder, existing_rules)
	local rules = {}
	local start_time = os.time()
	existing_rules = existing_rules or {}

	for _, folder in ipairs(get_subfolders(root_folder)) do
		rules[folder] = update_rules(folder, existing_rules[folder])
	end
	log("update_all_rules(): completed in " ..
		os.difftime(os.time(), start_time) .. " seconds.")

	log("update_all_rules(): All rules:")
	for folder, folder_rules in pairs(rules) do
		log("Folder [" .. folder .. "]:")
		for _, from_addr in ipairs(folder_rules) do
			log(from_addr)
		end
	end

	return rules
end

local function apply_rules (mbox, rules)
	rules = rules or {}
	print("apply_rules(): #rules: " .. #rules)
	for folder, folder_rules in pairs(rules) do
		for _, from_addr in ipairs(folder_rules) do
			local results = mbox:contain_from(from_addr)
			if #results > 0 then
				log("apply_rules(): moved " .. #results .. " messages with From: addr " ..
					from_addr .. " to folder " .. folder .. ".")
				results:move_messages(account[folder])
			end
		end
	end
end

while true do
   	if (not rules_last_updated) or 
   		os.difftime(os.time(), rules_last_updated) > options.zfilter.min_update_interval then
      	rules = update_all_rules(options.zfilter.root_imap_folder, rules)
      	rules_last_updated = os.time()
   	end
   	if (not email_last_sent) or 
   		os.difftime(os.time(), email_last_sent) > options.zfilter.min_email_log_interval then
   			log(nil, true)
   			email_last_sent = os.time()
   	end

   	apply_rules(account.INBOX, rules)

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
