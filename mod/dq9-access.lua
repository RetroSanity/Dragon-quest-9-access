-- dq9-access.lua  -  Dragon Quest IX: Sentinels of the Starry Skies (US, ROM code YDQE)
-- A screen reader for BizHawk (melonDS core). Open this file from Tools > Lua Console.
--
-- WHAT IT READS OUT
--   * Every message box, page by page, with the speaker's name  (story, people, battle messages)
--   * Cursor menus: field menu, battle commands, spells, items, the bag, the church, and others
--     built the same way, plus the title screen
--   * Yes / No questions
--   * The place name whenever you enter a new area or room
--   * "Blocked" when you walk into a wall (can be switched off)
--   * People who come right next to you
--
-- KEYBOARD COMMANDS (play the game on your controller, or on the keyboard with Z X A S Q E, Enter
-- and the arrow keys; these other keys are the mod's)
--   R  repeat the last thing said            Ctrl (on its own)  stop speaking
--   W  where am I (area, room, position)     H  everyone's HP      M  everyone's MP
--   G  gold                                  I  repeat the last information window
--   O  read every option in the current menu
--   N  next nearby thing (people, doors you have used, your marks)
--   B  previous nearby thing                 D  directions to the selected thing again
--   J  walk to the thing you picked with N or B (any controller button stops it)
--   Shift+M  mark this spot, so you can find it again later
--   Page Down / Page Up          next / previous nearby thing in the category
--   Ctrl+Page Down / Page Up     next / previous category of nearby things
--   Ctrl+Home  the route to the thing picked      Ctrl+End  walk there (again to stop)
--   U  what everyone is wearing and holding   L  attributes one at a time (Shift+L back)
--   T  switch wall bump and "someone nearby" alerts on or off
--   C  capture a debug snapshot to dq9-access-log.txt (send me that file if something is silent)
--   K  list these keys
--
-- DIRECTIONS are given the way you walk: "up" means push up on the D-pad, "right" means push right.
-- The script turns the game's camera into those words for you, so they stay right even when the
-- camera is at an angle.
--
-- HOW IT WORKS (for whoever maintains this)
-- Everything here was found by running the US ROM and watching memory change. The game builds all
-- of its text as plain ASCII with small <TAG> codes before drawing it, so the script reads the
-- game's own finished words straight out of RAM:
--   0x0211819C  the message box text (pages separated by bytes 0D FF)
--   0x02115348  pointer to the start of the page on screen, 0x0211534C to its end
--   0x02118FFC  the menu markup buffer, e.g. "<CURSOR=1><N=0>Fight</N>\n<N=1>Examine</N>..."
--   0x020FB3FC  current map code, e.g. "M01M0100";  0x022A4266  map name shown on screen
--   0x020F33E0  pointer to the player object; position (fixed point /4096) at +0x44 +0x48 +0x4C
--   0x0210A134  camera position (x, y, z) - used to work out which way "up" is on screen
--   0x02107600  table of people/objects on the map, count at 0x02107680, position at +0x24
--   0x020F3888  first party record name; records are 0x964 bytes apart
--   0x020F6D48  gold;  0x020EF0E8  1 while a battle is running
-- Anything read from memory is checked before it is spoken; a check that fails stays silent.

------------------------------------------------------------------------------ settings ------
MOD_VERSION = "0.52"
MENU_DEBUG = false   -- true: log the menu buffer and look for the yes/no box in snapshots
WALK_DEBUG = false   -- true: log auto walk's route and position (in the speech log)
KEYS = {
	repeat_last = "R", stop = "", where = "W", party = "H", gold = "G", info = "I",
	options = "O", next_thing = "N", prev_thing = "B", directions = "D", mark = "M", mp = "M",
	alerts = "T", capture = "C", help = "K", equipment = "U", walk = "J", stats = "L", category = "V", route = "P", beacon = "F", guide = "Y",
}
SAY_POSITION_IN_MENUS = true   -- add "2 of 6" after a menu option
ALERTS_ON = true               -- wall bumps
NEARBY_ALERTS = false          -- people and monsters coming close (true: say them)
DIR = ACCESS_DIR or (DQIX_PC and "access/" or "")   -- the mod's folder (the PC game says where it is)
-- the mod's sounds (Mod settings, at the end of the Misc. menu; kept in dq9-access-settings.txt)
WALK_BEEP_ON = true
WALK_BEEP_VOL = 6              -- 0 to 10
BEACON_VOL = 8                 -- 0 to 10
TURN_CHIME_ON = true
TURN_SPEECH_ON = false         -- the beacon says each turn of the way ("then 5 steps left")
BUMP_SOUND_ON = true           -- a thud from the way you pushed when you walk into something
PLACES_FILE = DIR .. "dq9-access-places.txt"
LOG_FILE = DIR .. "dq9-access-log.txt"

------------------------------------------------------------------------------ memory --------
BASE, SIZE = 0x02000000, 0x400000
local function inram(a, n) return a and a >= BASE and a + (n or 1) <= BASE + SIZE end
local function u8(a)  if not inram(a, 1) then return 0 end return mainmemory.read_u8(a - BASE) end
local function u16(a) if not inram(a, 2) then return 0 end return mainmemory.read_u16_le(a - BASE) end
local function u32(a) if not inram(a, 4) then return 0 end return mainmemory.read_u32_le(a - BASE) end
local function s32(a) if not inram(a, 4) then return 0 end return mainmemory.read_s32_le(a - BASE) end

-- read_bytes_as_array is 1-based in BizHawk; this also copes if a build hands back 0-based.
local function read_bytes(a, n)
	if not inram(a, n) then return {} end
	local t = mainmemory.read_bytes_as_array(a - BASE, n)
	if t[0] ~= nil then
		local o = {}
		for i = 0, n - 1 do o[i + 1] = t[i] end
		return o
	end
	return t
end

-- The PC version can hand over a run of memory as a string and search memory itself, which is
-- far quicker than reading byte by byte (scans that took a frame or more no longer stutter).
FAST_MEM = mainmemory.read_string ~= nil and mainmemory.find_u32 ~= nil
function mem_str(a, n)
	if not inram(a, n) then return "" end
	if FAST_MEM then return mainmemory.read_string(a - BASE, n) end
	local parts = {}
	for off = 0, n - 1, 4096 do
		local t = read_bytes(a + off, math.min(4096, n - off))
		for i = 1, #t, 1024 do parts[#parts + 1] = string.char(table.unpack(t, i, math.min(i + 1023, #t))) end
	end
	return table.concat(parts)
end
-- the 4-byte-aligned addresses in a range holding a value
function find_words(from, len, value, max)
	local out = {}
	if not inram(from, len) then return out end
	if FAST_MEM then
		for _, o in ipairs(mainmemory.find_u32(from - BASE, len, value, max or 4096)) do out[#out + 1] = o + BASE end
		return out
	end
	local b0, b1, b2, b3 = value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF
	for off = 0, len - 4, 4096 do
		local t = read_bytes(from + off, math.min(4096, len - off))
		for i = 1, #t - 3, 4 do
			if t[i] == b0 and t[i + 1] == b1 and t[i + 2] == b2 and t[i + 3] == b3 then
				out[#out + 1] = from + off + i - 1
				if max and #out >= max then return out end
			end
		end
	end
	return out
end
-- the aligned addresses x in a range whose word points at x + rel (a structure's pointer back
-- into itself)
function find_selfptr(from, len, rel, max)
	local out = {}
	if not inram(from, len) then return out end
	if FAST_MEM then
		for _, o in ipairs(mainmemory.find_rel(from - BASE, len, rel & 0xFFFFFFFF, max or 4096)) do out[#out + 1] = o + BASE end
		return out
	end
	for off = 0, len - 4, 4096 do
		local t = read_bytes(from + off, math.min(4096, len - off))
		for i = 1, #t - 3, 4 do
			local x = from + off + i - 1
			if t[i + 3] == 0x02 and t[i] + t[i + 1] * 256 + t[i + 2] * 65536 + 0x02000000 == x + rel then
				out[#out + 1] = x
				if max and #out >= max then return out end
			end
		end
	end
	return out
end

-- A zero-terminated string, raw bytes kept (the game's control codes use bytes like 0xFF).
local function cstring(a, maxlen)
	maxlen = maxlen or 600
	if FAST_MEM then
		if a and a >= BASE and a < BASE + SIZE then
			local s = mainmemory.read_string(a - BASE, math.min(maxlen, BASE + SIZE - a))
			local z = s:find("\0", 1, true)
			return z and s:sub(1, z - 1) or s
		end
		return ""
	end
	local parts, got = {}, 0
	while got < maxlen do
		local n = math.min(64, maxlen - got)
		local t = read_bytes(a + got, n)
		if #t == 0 then break end
		local stop
		for i = 1, #t do if t[i] == 0 then stop = i break end end
		if stop then
			if stop > 1 then parts[#parts + 1] = string.char(table.unpack(t, 1, stop - 1)) end
			break
		end
		parts[#parts + 1] = string.char(table.unpack(t, 1, #t))
		got = got + n
	end
	return table.concat(parts)
end

local function printable(s)
	return s ~= "" and not s:find("[^%w%s%p]")
end

------------------------------------------------------------------------------ speech --------
-- This project's EmuHawk build provides a global `speech` table: speech.say(text, interrupt) and
-- speech.stop(). interrupt true cuts off what is being said; false queues behind it.
local last_said, frame = "", 0
SPEECH_LOG = DIR .. "dq9-access-speech.txt"
local speech_log_on = false   -- turned on when a file called dq9-access-debug.txt is in this folder
do local f = io.open(DIR .. "dq9-access-debug.txt", "r") if f then speech_log_on = true f:close() end end
local function log_line(text)
	if not speech_log_on then return end
	local f = io.open(SPEECH_LOG, "a")
	if f then f:write(os.date("%H:%M:%S "), text, "\n") f:close() end
end
-- DLG_SPOKEN_FRAME: when a message was last read; USER_INPUT_FRAME: when you last pressed a
-- button or key. Something that comes up on its own after a message (the options, a yes or no,
-- a window) waits for the message to finish instead of cutting it off.
DLG_SPOKEN_FRAME, USER_INPUT_FRAME = -1000, -1000
local function say(text, interrupt)
	if not text or text == "" then return end
	if interrupt ~= false and frame - DLG_SPOKEN_FRAME < 600 and USER_INPUT_FRAME < DLG_SPOKEN_FRAME then interrupt = false end
	-- something that came up in the same moment and was waiting its turn (the sample of a
	-- speech style) is said again after this rather than cut off
	local requeue = nil
	if interrupt ~= false and say_queued_text and say_queued_text ~= text and frame - say_queued_frame <= 30 then requeue = say_queued_text end
	-- the same line waiting its turn twice in a moment (said again after being cut off, then
	-- asked for again) is said once
	if interrupt == false and text == say_last_queued and frame - (say_last_queued_frame or -1000) < 60 then return end
	if interrupt == false then say_queued_text, say_queued_frame = text, frame else say_queued_text = nil end
	if interrupt == false then say_last_queued, say_last_queued_frame = text, frame end
	if requeue then say_last_queued, say_last_queued_frame = requeue, frame end
	last_said = text
	if text:match("%?$") and not text:find("^Yes or no") then QUESTION_FRAME, QUESTION_TEXT = frame, text end
	if mon_note_said then pcall(mon_note_said, text) end
	if guide_hear then pcall(guide_hear, text) end
	console.log(text)
	log_line((interrupt == false and "+ " or "! ") .. text)
	if speech and speech.say then
		pcall(function() speech.say(text, interrupt ~= false) end)
		if requeue then pcall(function() speech.say(requeue, false) end) log_line("+ " .. requeue) end
	end
end
local function queue(text) say(text, false) end
local function stop_speech() if speech and speech.stop then pcall(function() speech.stop() end) end end

------------------------------------------------------------------------------ text ----------
-- The game's font has named glyphs written as <tags>. These are the ones that stand for characters.
GLYPH = {
	["1"] = "'", ["11"] = '"', [","] = ",", ["-"] = "-", ["/"] = "/", ["]"] = "[", ["..."] = "...",
	["_,"] = ",", [":"] = ":", [";"] = ";", ["%"] = "%", ["?"] = "?", ["!"] = "!", ["_%_"] = "%",
	["_66"] = '"', ["_99"] = '"', ["66_"] = '"', ["99_"] = '"', ["DE66"] = '"', ["DE99"] = '"',
	["_6"] = "'", ["_9"] = "'", ["6_"] = "'", ["9_"] = "'", ["6"] = "'", ["9"] = "'",
	["!_"] = "!", ["?_"] = "?", [",_"] = ",", [":_"] = ":", [";_"] = ";", ["%_"] = "%",
	["..._"] = "...", ["_,,"] = ",", [",,_"] = ",", ["^?"] = "?", ["_^?"] = "?", ["_^!"] = "!",
	["^?_"] = "?", ["^!_"] = "!", ["ss"] = "ss", ["ae"] = "ae", ["AE"] = "AE", ["x"] = " times ",
	["G"] = " gold", ["E"] = "E", ["A"] = "A", ["heart"] = " heart ", ["star"] = " star ",
	["blackstar"] = " star ", ["music"] = " ", ["deg"] = " degrees", ["degree"] = " degrees",
	["c"] = "(c)", ["R"] = "(R)", ["+-"] = "+/-", ["r_arrow"] = " to ", ["l_arrow"] = " to ",
}

local function tag_text(tag)
	local g = GLYPH[tag]
	if g then return g end
	local letter = tag:match("^[`'%^:~,](%a)$")          -- accented letters such as <^a> in Grace
	if letter then return letter end
	return " "                                          -- layout tags (<X=74>, <PLTT=3>, <N=0> ...)
end

-- Turn game markup or a message into something a speech engine reads well.
local function clean(s)
	if not s or s == "" then return "" end
	-- control codes are a byte and 255: new line, wait, end ... (also ones above 31, such as
	-- the jingle of finding something, "K" or "<" and 255, which used to be read out)
	s = s:gsub("[\1-\254]\255", " ")
	s = s:gsub("\\n", " "):gsub("[\r\n]", " ")
	s = s:gsub("<([^<>]*)>", tag_text)
	s = s:gsub("^%s*//(.-)//%s*", "%1: ")                -- "//Aquila// text" -> "Aquila: text"
	s = s:gsub("//(.-)//", "%1: ")
	s = s:gsub("^%s*%*:%s*", "")                        -- "*:" marks an unnamed speaker
	s = s:gsub("%s*%*:%s*", " ")
	s = s:gsub("[\128-\255]", "")
	s = s:gsub("[\1-\31]", "")
	s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	s = s:gsub(" ([,%.!%?])", "%1")
	s = s:gsub(":,%s*", ": ")                             -- "Erinn:,Guardian" (a pause after the name)
	return s
end

clean_text_g = clean
------------------------------------------------------------------------------ state ---------
local pad_prev, last_button_frame = {}, -1000
local last_button_name, battle_menu_said, battle_round, round_phase = nil, {}, 0, 0
local held_dir = nil
local last_dialogue_frame = -1000
local last_menu_frame = -1000
local last_menu_spoken = -1000
-- A battle is running while the game holds a battle object in the second actor slot.
-- 1 = walking about, 3 = a battle waiting for your command, 4 = a battle turn playing out
local function battle_phase() return mainmemory.read_u8(0x02109DA6 - 0x02000000) end
local function in_battle() local p = battle_phase() return p >= 2 and p <= 8 end

-- Monster letters in a battle's target lists. The game's list shows each group as a name and a
-- count ("Slime x1", "Cruelcumber x1", "Slime x1"), while its messages call them slime A, slime B.
-- The letters go to the monsters of a kind in the order of the groups, so the first list of a
-- battle gives every kind its letters; "Slime A is defeated" takes a letter away, and the
-- groups left keep the letters still standing, in order.
mon = { total = nil, dead = {} }
function mon_reset() if mon.total then mon.total, mon.dead = nil, {} end end
MON_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
function mon_note_said(text)
	if not mon.total or not in_battle() then return end
	local low = text:lower()
	for kind, n in pairs(mon.total) do
		if n > 1 then
			for i = 1, n do
				local l = MON_LETTERS:sub(i, i)
				local who = kind .. " " .. l:lower()
				local at = low:find(who, 1, true)
				if at and low:sub(at + #who):match("^ is defeated") or (at and low:sub(at + #who):match("^ is killed")) then
					mon.dead[kind .. "|" .. l] = true
				end
			end
		end
	end
end
function mon_letters_text(name, list)
	if #list == 1 then return name .. " " .. list[1] end
	return name .. " " .. table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
-- items: the parsed menu (by index); m: its markup. Rewrites the group names in place.
function mon_label_list(items, m)
	if not in_battle() or not m:find("<x>", 1, true) then return end
	local groups = {}
	for i = 0, 15 do
		local it = items[i]
		if not it then break end
		local name, n = it.text:match("^(.-)%s+times%s+(%d+)$")
		if not name then return end                                -- not a list of monsters
		groups[#groups + 1] = { it = it, name = name, kind = name:lower(), n = tonumber(n) }
	end
	if #groups == 0 then return end
	mon.total = mon.total or {}
	local now = {}
	for _, g in ipairs(groups) do now[g.kind] = (now[g.kind] or 0) + g.n end
	for kind, c in pairs(now) do
		local dead = 0
		for i = 1, mon.total[kind] or 0 do if mon.dead[kind .. "|" .. MON_LETTERS:sub(i, i)] then dead = dead + 1 end end
		if c > (mon.total[kind] or 0) - dead then mon.total[kind] = c + dead end   -- first look, or more arrived
	end
	local standing = {}
	for kind, n in pairs(mon.total) do
		local l = {}
		for i = 1, n do local c = MON_LETTERS:sub(i, i) if not mon.dead[kind .. "|" .. c] then l[#l + 1] = c end end
		standing[kind] = l
	end
	for _, g in ipairs(groups) do
		if (mon.total[g.kind] or 0) > 1 then
			local take = {}
			for _ = 1, g.n do take[#take + 1] = table.remove(standing[g.kind], 1) end
			g.it.text = mon_letters_text(g.name, take)
			g.it.letters, g.it.mname = take, g.name
		elseif g.n == 1 then
			g.it.text = g.name
		end
	end
end

-- Picking which one of a group to attack (left and right move the arrow between "Slime A" and
-- "Slime B" while the list shows the group): the game keeps the one picked, counted within the
-- group, here. Say each one as the arrow moves.
TARGET_SUB = 0x02395354
tgt_watch = { key = nil, sub = nil }
function watch_target_sub(items, cursor, raw)
	if not in_battle() then tgt_watch.key = nil return end
	-- (the buffer can show another window between frames: the list is gone only after a while)
	local c = raw:find("<x>", 1, true) and tonumber(raw:match("<CURSOR=(%d+)>") or "")
	if not c then
		if frame - (tgt_watch.seen or -1000) > 90 then tgt_watch.key = nil end
		if not tgt_watch.key then return end
		c, raw = tgt_watch.c, tgt_watch.raw
	end
	tgt_watch.seen, tgt_watch.c, tgt_watch.raw = frame, c, raw
	-- the group the list's cursor is on, from the list itself (the menu reader may not have
	-- taken this list in yet: just after the mod starts, say)
	local it = items and items[c]
	if not (it and it.letters) then
		local name, n
		for idx, body in raw:gmatch("<N=(%d+)>(.-)</N>") do
			if tonumber(idx) == c then name, n = body:match("^(.-)<X=%d+><x>%s*(%d+)") end
		end
		n = tonumber(n or "")
		if not name or not n or n < 2 then return end
		local letters = {}
		for i = 1, n do letters[i] = MON_LETTERS:sub(i, i) end
		it = { text = name .. " x" .. n, letters = letters, mname = name }
	end
	if #it.letters < 2 then return end
	local sub = mainmemory.read_u32_le(TARGET_SUB - 0x02000000)
	if sub > 25 then return end
	local key = it.text .. "|" .. c
	if tgt_watch.key ~= key then tgt_watch.key, tgt_watch.sub = key, sub return end
	if sub ~= tgt_watch.sub then
		tgt_watch.sub = sub
		local l = it.letters[sub + 1]
		if l then say(it.mname .. " " .. l, true) end
	end
end
-- menu state lives here because the message reader resets it
MENU = 0x02118FFC
local menu_raw_seen, menu_seen_count = "", 0
local menu_raw_done, menu_sig, menu_cursor = "", "", -1
local menu_items, menu_title = {}, nil
local last_info, last_info_frame, last_info_title = "", -1000, nil
-- A window filling in line by line ("retro +9 Exp." then "retro +9 Exp. lebon +4 Exp."): the new
-- part only, compared word by word (the spacing round the numbers can differ); nil if it is not
-- the last window grown
function info_growth(body)
	if frame - last_info_frame >= 300 then return nil end
	local function words(x) local w = {} for t in x:gmatch("[^%s]+") do w[#w + 1] = (t:gsub("[%.,]+$", "")) end return w end
	local pw, bw = words(last_info_body or ""), words(body)
	if #pw == 0 or #bw <= #pw then return nil end
	for i = 1, #pw do if pw[i] ~= bw[i] then return nil end end
	local rest = {}
	for t in body:gmatch("[^%s]+") do rest[#rest + 1] = t end
	return table.concat(rest, " ", #pw + 1)
end

local function pad_state()
	local ok, j = pcall(function() return joypad.get() end)
	if not ok or type(j) ~= "table" then return {} end
	local function b(n) return j[n] == true or j["P1 " .. n] == true end
	return { up = b("Up"), down = b("Down"), left = b("Left"), right = b("Right"),
	         a = b("A"), b = b("B"), x = b("X"), y = b("Y"), l = b("L"), r = b("R"),
	         start = b("Start"), select = b("Select") }
end

------------------------------------------------------------------------------ dialogue ------
DLG = 0x0211819C
PAGE_START, PAGE_END = 0x02115348, 0x0211534C
local dlg_last_raw, dlg_last_page, dlg_last_text = "", -1, ""

-- Pages end at a page break (13), a yes or no question (4: what follows are the answers, each
-- ending with 1) or the end of a message (1).
-- (10: the inn's and shops' yes or no box comes after the question; what follows is the answer's)
PAGE_ENDS = { [13] = true, [4] = true, [1] = true, [10] = true }
local function split_pages(raw)
	local pages, from = {}, 1
	local i = 1
	while i < #raw do
		local b, n = raw:byte(i), raw:byte(i + 1)
		if n == 255 and PAGE_ENDS[b] then
			if i > from then pages[#pages + 1] = { from, i - 1 } end
			from = i + 2
			i = i + 2
		elseif n == 255 and (b == 0x14 or b == 0x15) and i > from + 1 then
			-- the start of the answer to a yes or no (20 for yes, 21 for no): the other answer
			-- before it is not part of it (the page starts at the code, where the game points)
			pages[#pages + 1] = { from, i - 1 }
			from = i
			i = i + 2
		else
			i = i + 1
		end
	end
	if from <= #raw then pages[#pages + 1] = { from, #raw } end
	if #pages == 0 then pages[1] = { 1, #raw } end
	return pages
end

local dlg_sig = nil
local on_new_message = nil     -- set further down: learns who you talked to
local experience_fix = nil     -- set further down: puts the amount into "receives some experience"
local function read_dialogue()
	-- Cheap check first: the first bytes and the page pointers change whenever anything does
	-- (the game also blanks the buffer for a frame between messages).
	local head = mem_str(DLG, 48)
	local sig = head .. ":" .. u32(PAGE_START) .. ":" .. u32(PAGE_END)
	if sig == dlg_sig then return end
	dlg_sig = sig
	local raw = cstring(DLG, 1200)
	if raw == "" then dlg_last_raw, dlg_last_page = "", -1 return end
	local pages = split_pages(raw)
	local offset = u32(PAGE_START) - DLG             -- 0-based byte offset of the page on screen
	local idx = 1
	if offset > 0 and offset < #raw then
		for k, p in ipairs(pages) do if offset + 1 >= p[1] then idx = k end end
	end
	if raw == dlg_last_raw and idx == dlg_last_page then return end
	local new_message = raw ~= dlg_last_raw
	dlg_last_raw, dlg_last_page = raw, idx
	if new_message then menu_sig = "" msg_serial = (msg_serial or 0) + 1 end   -- the next menu after a new message is news
	-- a shopkeeper greeting you again: the Buy / Sell menu that follows is news even if it looks
	-- the same as last time (the game leaves the old menu in memory, so only these lines re-arm it)
	if new_message then
		local low = clean(raw):lower()
		if low:find("welcome", 1, true) or low:find("anything else", 1, true) or low:find("help you", 1, true)
			or low:find("what can i do", 1, true) then
			dialogue_serial = (dialogue_serial or 0) + 1
		end
	end
	local p = pages[idx]
	-- a message that ends in a list of choices (<ADD>, "\x0A\xFF"): the list is news even if
	-- it is the same as the last time it was up, so let the screen reader say it again
	if idx == #pages and raw:find("\x0A\xFF", 1, true) then UI_SAID_RESET = frame end
	local text = clean(raw:sub(p[1], p[2]))
	if text == "" then return end
	-- the same words written again with different control codes are not a new message
	if new_message and text == dlg_last_text and frame - last_dialogue_frame < 180 then last_dialogue_frame = frame return end
	dlg_last_text = text
	-- Pressing a button to get here means you want it now; a message that arrives on its own
	-- (battle messages, cut scenes) waits its turn behind whatever is being said.
	local pressed_recently = frame - last_button_frame < 45
	if new_message and experience_fix then text = experience_fix(text) end
	-- an information window (experience, attributes going up) that just came up is not cut off
	if new_message and (not pressed_recently or frame - last_info_frame < 90) then queue(text) else say(text, true) end
	DLG_SPOKEN_FRAME = frame
	if new_message and pressed_recently and on_new_message and not in_battle() and frame - last_dialogue_frame > 30 then
		pcall(on_new_message, text, clean(raw))
	end
	last_dialogue_frame = frame
end

------------------------------------------------------------------------------ menus ---------

MONTHS = { JAN = "January", FEB = "February", MAR = "March", APR = "April", MAY = "May", JUN = "June",
	JUL = "July", AUG = "August", SEP = "September", OCT = "October", NOV = "November", DEC = "December" }
-- a value shown in a menu, as words: "???" is something not chosen yet, months in full
function menu_value_words(v)
	if v:match("^%?+$") then return "not set" end
	v = v:gsub("%f[%a](%u%u%u)%f[%A]", function(m) return MONTHS[m] or m end)
	return v
end
local function parse_menu(m)
	local items = {}
	for s, idx, e in m:gmatch("()<N=(%d+)>()") do items[#items + 1] = { s = s, idx = tonumber(idx), e = e } end
	for k, it in ipairs(items) do
		local nxt = items[k + 1] and items[k + 1].s or #m + 1
		local seg = m:sub(it.e, nxt - 1)
		local nl = seg:find("\\n", 1, true) or seg:find("\n", 1, true)
		if nl then seg = seg:sub(1, nl - 1) end
		-- a number drawn after the item (how many there are in the bag): "Horse manure, 5"
		seg = seg:gsub("^(.-)</N>%s*<XR=%d+>([^<]*)</XR>", "%1</N>, %2")
		-- a column of values drawn beside the list (<XY=x,y>value ...) is not part of the item
		local side = seg:find("<XY=", 1, true) or seg:find("<LINE", 1, true)
		if side then seg = seg:sub(1, side - 1) end
		it.text = clean(seg)
		if it.text == "???" then it.text = "??? (keep it secret)" end
		if it.text:match("^%-%-%-+$") then it.text = "none" end            -- (no tactics set: dashes)
		-- a name written just before the item (Tactics: each party member, then their tactics)
		local label = m:sub(math.max(1, it.s - 60), it.s - 1):match("<PLTT=%d+>([^<>]+)<X=%d+><PLTT=%d+>$")
		if label and printable(clean(label)) then it.text = clean(label) .. ": " .. it.text end
		local before = m:sub(math.max(1, it.s - 10), it.s - 1)
		it.disabled = before:find("<PLTT=3>", 1, true) ~= nil
	end
	local by_index, count = {}, 0
	for _, it in ipairs(items) do
		if not by_index[it.idx] then by_index[it.idx] = it count = count + 1 end
	end
	-- the column of values beside a list (Profile Settings: Location ... Europe, Birthday ...
	-- 1 JAN 2000): one value for each item from the top, read with the item
	if #items > 0 then
		local last = items[#items].s
		local vals, starts = {}, {}
		for p in m:gmatch("()<XY=%d+,%d+>") do if p > last then starts[#starts + 1] = p end end
		for k, p in ipairs(starts) do
			local stop = starts[k + 1] or #m + 1
			local v = clean(m:sub(p, stop - 1))
			vals[#vals + 1] = v
		end
		if #vals >= 2 and #vals >= count - 1 and #vals <= count then
			local order = {}
			for i, it in pairs(by_index) do order[#order + 1] = i end
			table.sort(order)
			for k, v in ipairs(vals) do
				local it = by_index[order[k]]
				if it and v ~= "" then it.text = it.text .. ": " .. menu_value_words(v) end
			end
		end
	end
	local title = m:match("<TITLE=%d+>(.-)</TITLE>")
	return by_index, count, title and clean(title) or nil
end
parse_menu_g = parse_menu
-- Number pickers (the birthday in Profile Settings: Day, Month, Year): the menu buffer holds only
-- the one picked, as "<N=0>value</N><XY=..>Day". A number is a message variable (<val_1>), whose
-- value the game keeps at 0x02115BA0 + 4 * n.
MSG_VALS = 0x02115BA0
spin = { label = nil, value = nil, frame = -1000 }
function watch_spinner()
	if frame % 2 ~= 0 then return end
	local m = cstring(MENU, 200)
	local v, label = m:match("^[^\n]-<N=0>(.-)</N>.-<XY=%d+,%d+>([%a ]+)$")
	if not v or m:find("<CURSOR=", 1, true) or m:find("<TITLE=", 1, true) or #label > 14 then
		if spin.label and frame - spin.frame > 30 then spin.label, spin.value = nil, nil end
		return
	end
	spin.frame = frame
	local n = v:match("<val_(%d+)>")
	local value
	if n then value = tostring(u32(MSG_VALS + 4 * tonumber(n))) else value = menu_value_words(clean(v)) end
	if label ~= spin.label then
		local first = spin.label == nil
		spin.label, spin.value = label, value
		say(label .. ": " .. value .. (first and ". Up and down change it, left and right go to the next one, A when done." or ""), true)
	elseif value ~= spin.value then
		spin.value = value
		say(value, true)
	end
end

-- MP costs. The game keeps its spells and abilities in tables of 0x3C-byte records: a pointer
-- to the name (+0) and the MP cost (+8, 255 for "all your MP"). The spells you can cast outside
-- battle are always at 0x02304E38; the full list is only loaded for a battle, somewhere near
-- 0x02358000, so that one is looked for when a battle starts. Costs never change, so once read
-- they are kept by name.
SPELL_TABLE_FIELD = 0x02304E38
spell_cost = {}
costscan = { co = nil, battle = false, addr = nil, first = nil }
function learn_cost_table(a)
	local function rec_ok(r)
		local p = u32(r)
		return inram(p, 2) and u8(p) >= 0x20 and u8(p) < 0x7F
	end
	-- back to the first record (records with no name have a pointer to an empty string)
	local guard = 0
	while guard < 1000 and inram(u32(a - 0x3C), 1) do a, guard = a - 0x3C, guard + 1 end
	local n, first = 0, nil
	guard = 0
	while guard < 1000 and inram(u32(a), 1) do
		if rec_ok(a) then
			local name = cstring(u32(a), 40):lower()
			local c = u8(a + 8)
			if not first then first = a end
			if name ~= "" and (spell_cost[name] == nil or (spell_cost[name] == 0 and c > 0)) then spell_cost[name] = c end
			if c > 0 then n = n + 1 end
		end
		a, guard = a + 0x3C, guard + 1
	end
	return n, first
end
function cost_table_looks_right(a)
	local p1, p2, p3 = u32(a), u32(a + 0x3C), u32(a + 0x78)
	return inram(p1, 1) and p2 - p1 > 0 and p2 - p1 < 64 and p3 - p2 > 0 and p3 - p2 < 64
end
function costscan_run()
	-- still where it was in the last battle?
	if costscan.addr and cost_table_looks_right(costscan.addr) and u32(costscan.addr) == costscan.first then
		learn_cost_table(costscan.addr)
		return
	end
	local from, len = 0x02300000, 0x100000
	for off = 0, len - 4096, 4096 do
		if coroutine.isyieldable() and off % 8192 == 0 then coroutine.yield() end
		local t = read_bytes(from + off, 4096)
		for i = 1, 4096 - 0x7C, 4 do
			if t[i + 3] == 0x02 and t[i + 0x3F] == 0x02 and t[i + 0x7B] == 0x02 and t[i + 2] < 0x40 then
				local p1 = t[i] + t[i + 1] * 256 + t[i + 2] * 65536
				local p2 = t[i + 0x3C] + t[i + 0x3D] * 256 + t[i + 0x3E] * 65536
				local p3 = t[i + 0x78] + t[i + 0x79] * 256 + t[i + 0x7A] * 65536
				if p2 - p1 > 0 and p2 - p1 < 64 and p3 - p2 > 0 and p3 - p2 < 64 then
					local a = from + off + i - 1
					-- the battle list starts with "Attack"
					local b, guard = a, 0
					while guard < 1000 and inram(u32(b - 0x3C), 1) do b, guard = b - 0x3C, guard + 1 end
					if cstring(u32(b), 8) == "Attack" then
						local n, first = learn_cost_table(b)
						if n >= 20 then costscan.addr, costscan.first = first, u32(first) return end
					end
				end
			end
		end
	end
end
function spell_cost_tick()
	if not costscan.field_done then
		local p = u32(SPELL_TABLE_FIELD)
		if inram(p, 4) and cstring(p, 8) == "Heal" then learn_cost_table(SPELL_TABLE_FIELD) costscan.field_done = true end
	end
	if in_battle() then
		if not costscan.battle then
			costscan.battle = true
			costscan.co = coroutine.create(costscan_run)
		end
	else
		costscan.battle = false
	end
	if costscan.co then
		local ok = coroutine.resume(costscan.co)
		if not ok or coroutine.status(costscan.co) == "dead" then costscan.co = nil end
	end
end
-- "2 MP" for a spell or ability (and in a battle, how much the one casting it has left)
function spell_cost_of(name)
	if not name or name == "" then return nil end
	local c = spell_cost[name:lower()]
	if not c or c == 0 then return nil end
	local t = c == 255 and "uses all MP" or (c .. " MP")
	if in_battle() and BATTLE_ACTOR_IDX then
		local idx = u8(BATTLE_ACTOR_IDX)
		local b = BATTLE_FIGHTER0 + idx * 0x448
		if idx <= 3 and u32(b - 8) - u32(b - 4) == 0x18 then
			local mp = u16(b + 6)
			if mp < 1000 then t = t .. ", you have " .. mp end
		end
	end
	return t
end

-- "HP 27 of 43" for a party member picked as a target in a battle (from the fighter records,
-- which change as the battle goes on); "dead" when they are down.
function battle_member_hp(name)
	if not name or name == "" or not in_battle() or not BATTLE_FIGHTER0 then return nil end
	local want = name:lower()
	if not party_records_g then return nil end
	for _, r in ipairs(party_records_g()) do
		if r.name:lower() == want then
			for k = 0, 3 do
				local b = BATTLE_FIGHTER0 + k * 0x448
				if u32(b - 8) - u32(b - 4) == 0x18 and u16(b) == r.maxhp and u16(b + 2) == r.maxmp then
					local hp = u16(b + 4)
					if hp == 0 then return "dead" end
					return "HP " .. hp .. " of " .. r.maxhp
				end
			end
			if r.hp == 0 then return "dead" end
			return "HP " .. r.hp .. " of " .. r.maxhp
		end
	end
	return nil
end

local function describe_item(it, cursor, count)
	local s = it.text ~= "" and it.text or "blank"
	local cost = spell_cost_of(it.text)
	if cost then s = s .. ", " .. cost end
	local hp = battle_member_hp(it.text)
	if hp then s = (s:gsub("^%l", string.upper)) .. ", " .. hp end
	if it.disabled then s = s .. ", unavailable" end
	if SAY_POSITION_IN_MENUS and count > 1 then s = s .. ", " .. (cursor + 1) .. " of " .. count end
	return s
end

local menu_head = nil
menu_hist, menu_hist_n, menu_cursor_frame = {}, 0, -1000

-- What each picture on the character screens looks like (checked on the game's own previews).
CREATE_LOOKS = {
	[2] = { any = { "tallest and slim", "tall", "average height", "short and stocky", "shortest and small" } },
	[3] = {
		Male = { "short and messy", "wide, flicked out at the sides", "bowl cut", "short crop with a fringe",
			"long, wild and spiky", "straight, shoulder length, parted in the middle", "tall and spiky",
			"neat, with a side-swept fringe", "swept up on top, short at the sides", "bald" },
		Female = { "bob with a straight fringe", "bob with a fringe over one eye", "bunches sticking out",
			"big curly up-do", "short and swept to the side", "shoulder length, flicked out",
			"long and curly", "short and spiky", "high ponytail", "short rounded bob" },
	},
	[4] = { any = { "very dark brown", "reddish brown", "red", "pink", "blonde", "green", "blue", "purple",
		"light blue", "grey" } },
	[5] = {
		Male = { "big round friendly eyes", "determined eyes, bold eyebrows", "narrow, stern eyes",
			"fierce eyes, heavy eyebrows", "sleepy, half-closed eyes", "small round eyes, surprised look",
			"tiny dot eyes", "round eyes, gentle look", "intense, angry eyes", "eyes closed, smiling" },
		Female = { "big round sweet eyes", "determined eyes, raised eyebrows", "tall oval eyes, calm",
			"narrow eyes with long lashes", "sharp eyes, arched eyebrows", "eyes closed, smiling",
			"sleepy, half-closed eyes", "made-up, with eye shadow and lipstick", "small round eyes and freckles",
			"wide round eyes, rosy cheeks" },
	},
	[6] = { any = { "very fair", "fair", "light, rosy", "light tan", "tan", "medium brown", "dark brown",
		"deep brown" } },
	[7] = { any = { "black", "brown", "red", "gold", "green", "blue", "purple", "grey" } },
}
function create_look(field, value, m)
	local looks = CREATE_LOOKS[field]
	local n = tonumber((value or ""):match("Type (%d+)"))
	if not looks or not n then return nil end
	local gender = (m or ""):match("^<PLTT=%d+><X=%d+>(%a+)") or "Male"
	local list = looks.any or looks[gender] or looks.Male
	return list[n]
end
local creation_last = nil
local function read_creation(m)
	if not m:match("^<PLTT=1[45]><X=%d+>") then return false end
	local i, field, value = 0, nil, nil
	for pltt, v in m:gmatch("<PLTT=(%d+)>([^\\]*)") do
		i = i + 1
		if pltt == "14" then field, value = i, (v:gsub("<[XW]=%d+>", "")) end
	end
	if field then
		local names = { "Gender", "Body type", "Hairstyle", "Hair colour", "Face", "Skin colour", "Eye colour", "Name" }
		local text = (names[field] or ("Choice " .. field)) .. ": " .. clean(value)
		local look = create_look(field, clean(value), m)
		if look then text = text .. ", " .. look end
		if create then create.step = field end
		-- the name is read out by the keyboard as you type it
		-- (and the keyboard says "Name entry" when it comes up)
		if field == 8 then creation_last = text return true end
		-- your own hero's Male / Female is said from its picture list (read_create)
		if field == 1 and create and create.grid == HERO_CREATE_GRID then return true end
		if text ~= creation_last then
			creation_last = text
			-- on Patty's companion screen, say which of the pictures this is
			local g = create and create.grid
			if g and create_grid_ok(g) then
				local cols, rows, cx, cy = u32(g + 8), u32(g + 0xC), u32(g + 0x18), u32(g + 0x1C)
				if not (cols == 8 and rows == 1) and cols * rows > 1 and field ~= 8 then
					text = text .. ", " .. (cy * cols + cx + 1) .. " of " .. (cols * rows)
					create.last = "field"
				end
			end
			say(text, true)
		end
	end
	return true
end

-- Allocate Skill Points: five skills, each with the points you are adding now and its total,
-- then Confirm and the points you have left. All of it is in the menu text.
local skill_said = nil
plain_said = nil
function read_skill_points(m, cursor)
	local names = {}
	for k, name in m:gmatch("<N=(%d+)>(.-)</N>") do
		k = tonumber(k)
		if k <= 5 and not names[k] then names[k] = clean(name) end
	end
	local nums = {}
	for n in m:gmatch("<XR=%d+>(%d+)</XR>") do nums[#nums + 1] = tonumber(n) end
	local left = m:match("Points Remaining:%s*(%d+)")
	local text
	if cursor <= 4 then
		local add, total = nums[cursor * 2 + 1], nums[cursor * 2 + 2]
		text = (names[cursor] or "skill") .. (add and (", adding " .. add) or "") ..
			(total and ((add and add > 0) and (", from " .. total .. " to " .. (total + add)) or (", total " .. total)) or "")
	else
		text = names[5] or "Confirm"
	end
	local pos = ", " .. (math.min(cursor, 5) + 1) .. " of 6"
	local tail = left and (". " .. left .. (tonumber(left) == 1 and " point left" or " points left")) or ""
	local key = cursor .. "|" .. table.concat(nums, ",") .. "|" .. tostring(left)
	if key == skill_said then return end
	local first = skill_said == nil
	local same_row = skill_said and skill_said:match("^(%d+)|") == tostring(cursor)
	skill_said = key
	menu_cursor = cursor
	if first then
		say("Allocate skill points. Left and right change how many go into a skill. " .. text .. tail .. pos, true)
	elseif same_row and cursor <= 4 then
		say(text:gsub("^[^,]*, ", "") .. tail, true)       -- only the numbers changed
	else
		say(text .. pos .. tail, true)
	end
end

-- a quick look at whether the menu text changed: BizHawk can fingerprint memory itself, which
-- is much cheaper than copying it into Lua every frame
menu_hash_ok = nil
function menu_fingerprint()
	if menu_hash_ok ~= false then
		local ok, h = pcall(function() return mainmemory.hash_region(MENU - 0x02000000, 256) end)
		if ok and type(h) == "string" and #h > 0 then menu_hash_ok = true return h end
		menu_hash_ok = false
	end
	return table.concat(read_bytes(MENU, 256), ",")
end
-- The label of a button in the menus the game has set up ("Learn more about other worlds."):
-- the game passes these through the menu buffer while it builds a window; they are not news.
function is_layout_label(t)
	local p = u32(LAYOUT_PTR)
	if not layout_box_g or not inram(p, 0x40) then return false end
	local L = p - 4
	local W, count = u32(L + 4), u16(L + 8)
	if count == 0 or count > 1000 or not inram(W, count * 0x30) then return false end
	for i = 0, count - 1 do
		local bt = layout_box_g(L, W, i)
		if bt and clean(bt) == t then return true end
	end
	return false
end
local function read_menu()
	-- a window's sentence (a spell's description) waits a moment: the list item it goes with is
	-- often read in the next frames, and the description should come after it, once
	if PLAIN_PENDING and frame - PLAIN_PENDING.at >= 4 then
		local t, pm = PLAIN_PENDING.t, PLAIN_PENDING.m
		PLAIN_PENDING = nil
		-- (gone from the screen meanwhile: the last spell's, as the cursor moved on)
		local current = pm == nil or menu_raw_seen == pm or frame - (menu_hist[pm] or -1000) <= 6
		local recent = RECENT_DSC and RECENT_DSC[t] and frame - RECENT_DSC[t] < 900
		if t ~= last_said and current and not recent then queue(t) end
	end
	local head = menu_fingerprint()
	if head == menu_head and menu_seen_count > 1 then return end
	menu_head = head
	local m = cstring(MENU, 2400)
	local has_cursor = m:find("<CURSOR=", 1, true) ~= nil
	-- A menu is only trusted once it has stayed the same for two frames: the game sometimes
	-- writes a half-built list into this buffer for a single frame.
	-- Some screens share the buffer between two windows drawn in turn ("To who?" and the HP of
	-- the one picked): a list that keeps coming back every few frames is steady too.
	if m ~= menu_raw_seen then
		if MENU_DEBUG then log_line("MENU " .. frame .. " " .. m:gsub("[^\32-\126]", function(c) return string.format("\\x%02X", c:byte()) end):sub(1, 400)) end
		local back = has_cursor and menu_hist[m] and frame - menu_hist[m] <= 8
		menu_hist_n = menu_hist_n + 1
		if menu_hist_n > 40 then menu_hist, menu_hist_n = {}, 0 end
		menu_hist[m] = frame
		menu_raw_seen, menu_seen_count = m, 0
		last_menu_frame = frame
		if has_cursor then menu_cursor_frame = frame end
		if read_creation(m) then return end
		-- the HP (and MP) of the one picked in "To who?"
		if not has_cursor and menu_title == "To who?" then
			local nums = {}
			for v in m:gmatch("<XR=%d+>(%d+)</XR>") do nums[#nums + 1] = v end
			local label = m:match("(%u%u):")
			if label and #nums >= 2 then
				local key = menu_cursor .. "|" .. table.concat(nums, ",")
				if key ~= towho_said then
					towho_said = key
					queue(nums[1] .. " of " .. nums[2] .. " " .. label .. (nums[4] and (", " .. nums[3] .. " of " .. nums[4] .. " MP") or ""))
				end
			end
		end
		if not back then
			-- Anything other than a cursor menu passing through this buffer (the gold window when the
			-- menu opens, a message, an information window) means the next menu is a fresh arrival
			-- (but not the other half of a pair of windows drawn in turn).
			if not has_cursor and frame - menu_cursor_frame > 8 then menu_sig, menu_raw_done = "", "" end
			return
		end
	else
		menu_hist[m] = frame
		if has_cursor then menu_cursor_frame = frame end
	end
	menu_seen_count = menu_seen_count + 1
	if menu_seen_count ~= 1 or m == menu_raw_done then return end
	menu_raw_done = m
	if m == "" then return end

	local cursor = tonumber(m:match("<CURSOR=(%d+)>") or "")
	if not cursor then
		-- A window with a title and no cursor is information (experience earned, status ...).
		local title = m:match("<TITLE=%d+>(.-)</TITLE>")
		if not title then
			-- a window with a sentence in it and nothing to pick (an accolade, a notice)
			-- (the text of a conversation also passes through here; the message box reads that)
			-- (also a message the game has not filled in yet: "<IF_SING>... draws near<ELSE>... draw near")
			local script = m:find("<PAGE>", 1, true) or m:find("<END>", 1, true) or m:find("<YESNO>", 1, true) or m:find("<N_TURN>", 1, true)
				or m:find("<IF_", 1, true) or m:find("<ELSE", 1, true) or m:find("_NAME>", 1, true)
			local t = script and "" or clean(m)
			-- an item's description: the menu reader says it with the item (the box can lag a
			-- frame behind and show the last item's); on "Mod settings" the box still shows a
			-- game item's
			if not ITEM_DESC_SET then
				ITEM_DESC_SET = {}
				for _, d in pairs(ITEM_DESC) do ITEM_DESC_SET[clean_text_g(d)] = true end
			end
			local skip = (ITEM_DESC_SET[t] and frame - (last_dsc_frame or -1000) < 120) or (MS and (MS.on_item or MS.open))
				or (RECENT_DSC and RECENT_DSC[t] and frame - RECENT_DSC[t] < 900)
			if not skip and #t > 12 and t:match("%a%a%a") and t:match("[%.!%?]$") and t ~= plain_said and t ~= dlg_last_text and t ~= last_said
				and not is_layout_label(t) then
				plain_said = t
				-- the experience window filling in after its first line came with the title
				local add = info_growth(t)
				if add then queue(add) last_info_body, last_info_frame = t, frame else PLAIN_PENDING = { t = t, at = frame, m = m } end
			end
			return
		end
		if title then
			-- numbers in the window are message variables (<val_1>): put their values in
			local mv = m:gsub("<val_(%d+)>", function(n) return " " .. u32(MSG_VALS + 4 * tonumber(n)) .. " " end)
			local body = clean((mv:gsub("<TITLE=%d+>.-</TITLE>", ""))):gsub("(%d)(%a)", "%1 %2"):gsub("Lv%. ", "level ")
			local t = clean(title)
			-- a window that updates line by line (attributes going up): say its title only once
			local recent = frame - last_info_frame < 300
			local repeat_title = t == last_info_title and recent
			last_info = t .. (body ~= "" and ((t ~= "" and ". " or "") .. body) or "")
			last_info_title, last_info_frame = t, frame
			local prev = last_info_body or ""
			local add = recent and info_growth(body)
			if add then
				queue(add)
			elseif repeat_title then
				if body ~= "" and body ~= prev then queue(body) end
			else
				queue(last_info)
			end
			last_info_body = body
		end
		return
	end
	-- (the Misc. menu has "Allocate Skill Points" as one of its items: that is not the screen)
	if m:find("Allocate Skill Points", 1, true) and not m:find("<N=%d+>Allocate Skill Points</N>") then read_skill_points(m, cursor) return end
	skill_said = nil
	-- In a battle the game builds its command lists before it shows them; only trust a list
	-- while the battle is waiting for your command.
	if in_battle() and (battle_phase() ~= 3 or frame - last_button_frame > 30) then return end
	local items, count, title = parse_menu(m)
	-- the Misc. menu has one more item, the mod's own settings, after the last (misc_step)
	if joypad.getraw and m:find("^<CURSOR=%d+>Misc%.") then count = count + 1 end
	pcall(mon_label_list, items, m)
	-- The little Equip / Move / Discard / Cancel list on the equipment screen. Its text stays in
	-- this buffer afterwards, and the list of who to equip moves the old cursor through it.
	if items[0] and items[0].text == "Equip" and items[2] and items[2].text == "Discard" then
		if not equip_popup_open and frame - (equip_popup_arm or -1000) < 60 then equip_popup_open = true end
		if not equip_popup_open then
			if equip_who_items and equip_who_count == count then
				items, title = equip_who_items, "Equip"
			else
				return
			end
		end
	elseif title == "Equip" then
		equip_who_items, equip_who_count = items, count
	end
	local it = items[cursor]
	if not it then return end                        -- a list that is shown but not in use
	local sig = m:gsub("<CURSOR=%d+>", "")
	local same_menu = sig == menu_sig
	if same_menu and cursor == menu_cursor then return end   -- redrawn, nothing moved
	-- In a battle, picking a command redraws the list you picked from: that is not news.
	if in_battle() then
		-- a new battle opens on Fight / Flee; until then the list on screen is the last
		-- battle's command list, still in the buffer: not news
		if items[0] and items[0].text == "Fight" then battle_fight_seen = true end
		if not battle_fight_seen and items[0] and items[0].text == "Attack"
			and frame - (battle_start_frame or frame) < 240 then
			menu_sig = ""            -- so the real one, when it comes, is news
			return
		end
		-- a fresh set of commands each round
		if battle_phase() ~= 3 or battle_menu_said.round ~= battle_round then battle_menu_said = { round = battle_round } end
		if last_button_name == "a" and battle_menu_said[sig .. cursor] then
			menu_sig, menu_cursor = sig, cursor
			return
		end
		battle_menu_said[sig .. cursor] = true
	end
	menu_sig, menu_cursor, menu_items, menu_title = sig, cursor, items, title
	local text = describe_item(it, cursor, count)
	-- the list of commands: say whose turn it is when that changes
	if in_battle() and items[0] and items[0].text == "Attack" then
		local who = battle_actor_name()
		if who and who ~= battle_actor_said then
			battle_actor_said, battle_actor_seen = who, who
			battle_actor_text, battle_actor_frame = text, frame
			last_menu_spoken = frame
			last_menu_item = it.text
			say(turn_text(who) .. text, true)
			return
		end
		-- just said with the turn a moment ago
		if who == battle_actor_said and text == battle_actor_text and frame - battle_actor_frame < 60 then return end
	end
	last_menu_spoken_prev = last_menu_spoken
	last_menu_spoken = frame
	last_menu_item = it.text
	local prev_count = last_menu_count
	last_menu_count = count
	local dsc = item_desc_of(it.text)
	if dsc then
		last_dsc_frame = frame
		-- (the description box lags behind the cursor: when it catches up, or still shows the
		-- last item's, that text is not news)
		RECENT_DSC = RECENT_DSC or {}
		RECENT_DSC[clean_text_g(dsc)] = frame
	end
	if same_menu then
		say(text, true)
		if dsc then queue(dsc) end
	else
		if title then text = title .. (title:find("[%.%?!:]$") and " " or ". ") .. text end
		-- left and right turn the page of a long list (titles, countries)
		-- (not in battle: left and right there move between monsters)
		if not title and not in_battle() and frame - last_button_frame < 40 and (last_button_name == "right" or last_button_name == "left")
			and prev_count and frame - (last_menu_spoken_prev or -1000) < 600 then
			text = (last_button_name == "right" and "Next page. " or "Previous page. ") .. text
		end
		-- A menu that opens together with a question waits for the question to be read.
		if frame - last_dialogue_frame < 150 then queue(text) else say(text, true) end
		if dsc then queue(dsc) end
	end
end

local function read_all_options()
	if menu_sig == "" then say("No menu.") return end
	local list, n = {}, 0
	for i = 0, 40 do
		local it = menu_items[i]
		if it then
			n = n + 1
			list[#list + 1] = it.text .. (it.disabled and " (unavailable)" or "")
		end
	end
	if n == 0 then say("No menu.") return end
	say((menu_title and (menu_title .. ": ") or "") .. table.concat(list, ", "))
end

-- When a battle turn is over and the game asks for your command again, the command list is not
-- rewritten, so say it here. The list and its cursor live in the battle's menu (checked by count).
BATTLE_COMMANDS = { [0] = "Fight", "Examine", "Flee", "Misc." }
local last_phase, cmd_pending = 1, false
local function read_battle_phase()
	local ph = battle_phase()
	if ph == 3 and last_phase ~= 3 then
		-- a new battle waits for its "... draws near!" message; a new turn does not
		cmd_pending = { since = frame, need_message = last_phase < 2 or last_phase > 8 }
	end
	if ph ~= 3 then cmd_pending = false end
	last_phase = ph
	-- say the command list once the battle messages have gone quiet, unless you already moved
	if cmd_pending and cmd_pending.need_message and last_dialogue_frame > cmd_pending.since then
		cmd_pending.need_message = false
	end
	if cmd_pending and not cmd_pending.need_message and frame - last_dialogue_frame > 40
	   and frame - cmd_pending.since > 20 and last_menu_spoken < cmd_pending.since then
		cmd_pending = false
		local cur = 0
		if mainmemory.read_u32_le(0x0239533C - 0x02000000) == 4 then
			local c = mainmemory.read_u32_le(0x02395358 - 0x02000000)
			if c <= 3 then cur = c end
		end
		menu_sig = "<N=0>Fight</N>\\n<N=1>Examine</N>\\n<N=2>Flee</N>\\n<N=3>Misc.</N>"
		menu_cursor, menu_title = cur, nil
		menu_items = {}
		for i = 0, 3 do menu_items[i] = { text = BATTLE_COMMANDS[i] } end
		battle_actor_said, battle_fight_seen = nil, true
		queue(BATTLE_COMMANDS[cur] .. ", " .. (cur + 1) .. " of 4")
	end
end

------------------------------------------------------------------------------ yes / no ------
YESNO_VTABLE = 0x0214E628
local yesno_obj = 0x0239CA5C
local yesno_visible, yesno_choice, yesno_search_frame = false, -1, -1000
PLAYER_PTR = 0x020F33E0

local function find_yesno()
	-- The yes/no box lives in the field menu heap. It is normally at the same place, but if a
	-- different map moves it, look for it again (it is recognised by its class pointer).
	if u32(yesno_obj) == YESNO_VTABLE then return true end
	-- one look per message is enough (the search reads a lot of memory)
	if yesno_search_frame == (msg_serial or 0) then return false end
	yesno_search_frame = msg_serial or 0
	-- the field heap, and further up where the field menu keeps it (Quick Save's question:
	-- seen at 023B19C8 on the PC version)
	local found = nil
	for _, r in ipairs({ { 0x02388B6C, 0x17000, true }, { 0x023A0000, 0x30000 } }) do
		local heap, len, header = r[1], r[2], r[3]
		if not header or u32(heap) == 0x46524D48 then     -- "HMRF" heap header
			for _, a in ipairs(find_words(heap, len, YESNO_VTABLE)) do
				if not found or (u8(a + 0x28) == 1 and u8(found + 0x28) ~= 1) then found = a end
			end
		end
	end
	if found then yesno_obj = found return true end
	return false
end

-- Story scenes ask their yes or no questions with a different box: a two-line cursor list
-- whose count and cursor sit at fixed places.
EVENT_CHOICE_COUNT, EVENT_CHOICE_CURSOR = 0x021153A4, 0x021153C0
local yesno_question = nil
local function read_yesno()
	-- a Yes / No list in the menu buffer is read by the menu reader (with its cursor): saying it
	-- here as well gave "Yes or no? No" next to "Yes, 1 of 2"
	local menu_yesno = menu_raw_seen:find("<CURSOR=", 1, true) and menu_raw_seen:find("<N=0>Yes</N>", 1, true) and menu_raw_seen:find("<N=1>No</N>", 1, true)
	if menu_yesno then yesno_menu_frame = frame end
	local visible = false
	if u32(yesno_obj) == YESNO_VTABLE or (dlg_last_raw:find("\10\255", 1, true) and find_yesno()) then
		visible = u8(yesno_obj + 0x28) == 1
		-- the box stays marked as showing after a menu's question: a message that asks nothing
		-- (Heal All's "Retro casts Heal.") is not a yes or no
		if visible and not (dlg_last_raw:find("\4\255", 1, true) or clean_text_g(dlg_last_raw):find("?", 1, true)) then visible = false end
		-- the next question while the box stays up (the church's "record your works?" then
		-- "continue on your adventure?"): announce it again
		if visible then
			if yesno_question and yesno_question ~= dlg_last_raw then yesno_visible = false end
			yesno_question = dlg_last_raw
		end
	end
	local player = u32(PLAYER_PTR)
	local choice = inram(player, 0x260) and u8(player + 0x250) or 0
	-- (the event's two choices stay counted after the question is gone: a message without a
	-- question in it, such as Heal All's "Retro casts Heal.", is not asking yes or no)
	if not visible and u32(EVENT_CHOICE_COUNT) == 2
		and (dlg_last_raw:find("\4\255", 1, true) or clean_text_g(dlg_last_raw):find("?", 1, true)) then
		visible = true
		choice = u32(EVENT_CHOICE_CURSOR) == 1 and 1 or 0
		-- a new question while the box stays up: announce it again
		if yesno_question and yesno_question ~= dlg_last_raw then yesno_visible = false end
		yesno_question = dlg_last_raw
	elseif not visible then
		yesno_question = nil
	end
	-- (the box the menu's Yes / No used stays marked as showing for a while after it closes: that
	-- is not a new question either)
	if menu_yesno or frame - (yesno_menu_frame or -1000) < 120 then
		if visible then yesno_seen_frame = frame end
		yesno_visible, yesno_choice = visible, choice
		return
	end
	if visible then
		local word = choice == 1 and "No" or "Yes"
		if not yesno_visible then
			-- the box can blink off for a moment as it is drawn: the same question is said only once
			if not (yesno_said_raw == dlg_last_raw and frame - (yesno_said_frame or -1000) < 600) then queue("Yes or no? " .. word) end
			yesno_said_raw, yesno_said_frame = dlg_last_raw, frame
		elseif choice ~= yesno_choice then say(word, true) end
	end
	if visible then yesno_seen_frame = frame
	elseif frame - (yesno_seen_frame or -1000) > 180 then yesno_said_raw = nil end   -- gone for good: next time it is new
	yesno_visible, yesno_choice = visible, choice
end


------------------------------------------------------------------------------ name entry ----
-- The name keyboard is drawn as pictures. Its cursor is a pixel position in the keyboard's
-- control (recognised by four pointers back into itself); the name typed so far is written into
-- the menu buffer as "<X=18>Retro****" with one star per free letter.
KB = 0x022A517C
KB_ROWS = { [64] = { 32, "1234567890-=" }, [80] = { 40, "qwertyuiop[]" },
	[96] = { 48, "asdfghjkl;'" }, [112] = { 56, "zxcvbnm,./" } }
KB_SPECIAL = { ["24,96"] = "Caps lock", ["24,112"] = "Shift, a capital for the next letter", ["24,136"] = "Change letters",
	["48,136"] = "Accented letters", ["72,136"] = "Symbols", ["96,136"] = "Space",
	["160,136"] = "question mark", ["184,136"] = "Delete", ["208,136"] = "OK, finish the name" }
KB_SAY = { ["-"] = "dash", ["="] = "equals", ["["] = "open bracket", ["]"] = "close bracket",
	[";"] = "semicolon", ["'"] = "apostrophe", [","] = "comma", ["."] = "full stop", ["/"] = "slash" }
local kb_last, kb_name = nil, nil
-- Capitals: the down arrow key is caps lock (on until pressed again), the up arrow key is shift
-- (a capital for the next letter only)
kb_case = { lock = false, shift = false }
function kb_case_press(st, key)
	if key == "Caps lock" then
		st.lock = not st.lock
		queue(st.lock and "Caps lock on" or "Caps lock off")
	elseif key == "Shift, a capital for the next letter" then
		st.shift = not st.shift
		queue(st.shift and "Shift on" or "Shift off")
	end
end
function kb_case_show(st, key)
	if key and #key == 1 and key:match("%a") and (st.lock ~= st.shift) then return "capital " .. key:upper() end
	return key
end
local function kb_key(x, y)
	local sp = KB_SPECIAL[x .. "," .. y]
	if sp then return sp end
	local row = KB_ROWS[y]
	if row then
		local i = math.floor((x - row[1]) / 16 + 0.5) + 1
		local ch = row[2]:sub(i, i)
		if ch ~= "" then return KB_SAY[ch] or ch end
	end
	if y >= 130 then
		if x < 36 then return KB_SPECIAL["24,136"] elseif x < 60 then return KB_SPECIAL["48,136"]
		elseif x < 84 then return KB_SPECIAL["72,136"] elseif x < 150 then return "Space"
		elseif x < 172 then return "question mark"
		elseif x < 196 then return "Delete" else return "OK, finish the name" end
	end
	return nil
end
kb_key_g = kb_key
function companion_name() return COMPANION_NAME and clean(cstring(COMPANION_NAME, 20)) or "" end
local function kb_ok(b)
	return u32(b + 0x20) == b + 0xC and u32(b + 0x24) == b + 8 and u32(b + 0x28) == b + 0x1C
		and u32(b + 0x2C) == b + 0x18
end
local function read_name_entry()
	local b = KB
	local valid = kb_ok(b)
	-- Patty's companion screen has its own keyboard (the same kind of control, elsewhere)
	local companion = false
	if create and create.grid and create.step == 8 and kb_ok(create.grid) and patty_creating() then
		b, valid, companion = create.grid, true, true
	end
	local name = menu_raw_seen:match("^<X=%d+>([^<%*]*)%**$")
	-- before the first letter is typed the buffer still holds the list of steps, with
	-- "Name" (the 8th line) highlighted: the name so far is on that line
	if not name and menu_raw_seen:match("^<PLTT=1[45]>") then
		local i = 0
		for pltt, v in menu_raw_seen:gmatch("<PLTT=(%d+)>([^\\]*)") do
			i = i + 1
			if pltt == "14" and i == 8 then name = (v:gsub("<[XW]=%d+>", "")):gsub("%*", "") end
		end
	end
	if not valid then kb_last, kb_name = nil, nil kb_case.lock, kb_case.shift = false, false return end
	if companion and not name then name = kb_name or "" end
	if not name then return end            -- the buffer is busy for a moment; keep what we had
	name = clean(name)
	local x, y = u16(b + 0x60), u16(b + 0x62)
	local key = kb_key(x, y)
	local pos = x .. "," .. y
	-- the up arrow key switches the letters to capitals, the down arrow key back to small ones
	if last_button_frame == frame and last_button_name == "a" then kb_case_press(kb_case, key) end
	key = kb_case_show(kb_case, key)
	if kb_name == nil then
		say("Name entry. " .. (name ~= "" and ("Name so far: " .. name .. ". ") or "") ..
			"Move with the D-pad, A types a letter. " .. (key or ""), true)
	else
		if name ~= kb_name then
			if #name > #kb_name then kb_case.shift = false say(name:sub(#kb_name + 1) .. ", name is now " .. name, true)
			else say("Deleted, name is now " .. (name ~= "" and name or "empty"), true) end
		end
		if pos ~= kb_last and key then
			say(key, true)
			-- moving on the keyboard again: "Begin your adventure...?" is news the next time
			if create and not menu_raw_seen:find("<N=0>Yes</N>", 1, true) then create.asked = false end
		end
	end
	kb_last, kb_name = pos, name
end

-- The greeting keyboard in Profile Settings (Misc.): the screen's object is pointed to from
-- 0x02108DC0; +0x34/+0x35 are its mode (4, 0x0E while typing the greeting) and +0x94 points to
-- the greeting typed so far. The cursor is a picture (an OAM sprite with tile 0x40, palette 3)
-- drawn 8 pixels up and left of where the name keyboard keeps its cursor; it blinks.
PROFILE_PTR = 0x02108DC0
gk = { on = false, key = nil, text = nil, lock = false, shift = false }
function greeting_key(x, y)
	if y >= 130 then
		if x < 36 then return "Change letters" elseif x < 60 then return "Accented letters"
		elseif x < 84 then return "Symbols" elseif x < 160 then return "Space"
		elseif x < 196 then return "Delete" else return "OK, finish the greeting" end
	end
	return kb_key_g(x, y)
end
function read_greeting_entry()
	local o = u32(PROFILE_PTR)
	local on = inram(o, 0x100) and u8(o + 0x34) == 4 and u8(o + 0x35) == 0x0E and ui_string(14) == "Write your greeting."
	if not on then gk.on, gk.key, gk.text, gk.lock, gk.shift = false, nil, nil, false, false return end
	local tp = u32(o + 0x94)
	local text = inram(tp, 1) and clean(cstring(tp, 80)) or ""
	-- the key the cursor is on: the screen's object +0x184 points to that key's record, which
	-- starts with the key's position (the same positions as the name keyboard: q at 40,80)
	local x, y = nil, nil
	local kr = u32(o + 0x184)
	if inram(kr, 4) then
		local kx, ky = u16(kr), u16(kr + 2)
		if kx < 256 and (ky == 64 or ky == 80 or ky == 96 or ky == 112 or ky == 136) then x, y = kx, ky end
	end
	-- or else the cursor picture (it blinks, and is not drawn on the bottom row)
	if not x then
		for a = 0x02105000, 0x021057F8, 4 do
			local a0, a1, a2 = u16(a), u16(a + 2), u16(a + 4)
			if a2 == 0x3040 and a1 & 0xC000 == 0x8000 and a0 & 0x300 == 0 then x, y = (a1 & 0x1FF) + 8, (a0 & 0xFF) + 8 break end
		end
	end
	local key = x and greeting_key(x, y) or gk.key
	if last_button_frame == frame and last_button_name == "a" then kb_case_press(gk, key) end
	local shown = kb_case_show(gk, key)
	if not gk.on then
		gk.on, gk.key, gk.text = true, key, text
		say("Greeting entry. " .. (text ~= "" and ("Greeting so far: " .. text .. ". ") or "") ..
			"Move with the D-pad, A types a letter. Delete and OK are on the bottom row. " .. (shown or ""), true)
		return
	end
	if text ~= gk.text then
		if #text > #gk.text then gk.shift = false say(text:sub(#gk.text + 1) .. ", greeting is now " .. text, true)
		else say("Deleted, greeting is now " .. (text ~= "" and text or "empty"), true) end
		gk.text = text
	end
	if key and key ~= gk.key then gk.key = key say(shown, true) end
end
------------------------------------------------------------------------------ places --------
MAPCODE, MAPNAME, MAPID = 0x020FB3FC, 0x022A4266, 0x020FB3F0
CAMERA = 0x0210A134
OBJ_TABLE, OBJ_COUNT = 0x02107600, 0x02107680

------------------------------------------------------------------------------ title ---------
-- The title menu is run by the game's script engine, not the menu system, so it has its own reader.
-- Two script variables hold the cursor: one for a cartridge with no adventure log, one with a log.
TITLE_VAR_CLASS = 0x021FE80C
TITLE_MENUS = {
	{ obj = 0x0231624C, id = 0x12D, items = { "Create a new adventure log", "Configure Nintendo Wi-Fi Connection settings" } },
	{ obj = 0x023162D4, id = 0x12E, items = { "Continue your adventure", "Delete adventure log", "Configure Nintendo Wi-Fi Connection settings" } },
}
local title_last, title_frames, title_menu = nil, 0, nil
title_movie = 0
local function read_title()
	if cstring(MAPCODE, 12) ~= "" or u32(PLAYER_PTR) ~= 0 then
		title_last, title_frames, title_deleted, title_moved, title_rebuild = nil, 0, false, nil, false
		for _, m in ipairs(TITLE_MENUS) do m.seen = nil end
		return
	end
	-- the opening movie ("Begin your adventure. START" on the lower screen): the title menus
	-- are not built yet and their memory holds the film
	local o1, o2 = u32(TITLE_MENUS[1].obj), u32(TITLE_MENUS[2].obj)
	if o1 ~= TITLE_VAR_CLASS and o2 ~= TITLE_VAR_CLASS then
		if o1 ~= 0 and cstring(MENU, 8) == "" then
			title_movie = title_movie + 1
			if title_movie == 90 then queue("Opening movie. Press Start to begin your adventure.") end
		else
			title_movie = 0
		end
	elseif title_movie >= 90 then
		title_movie = 0
	end
	if title_last == nil and cstring(MENU, 8) ~= "" then return end   -- character creation, not the title
	-- "Quick save log found ...": its own choice (Load quick save data / Cancel) is up, not the title menu
	-- (nor while the game says it is "Creating backup" on the way into the adventure)
	local pg = cstring(u32(PAGE_START), 200):lower()
	if pg:find("quick save", 1, true) or pg:find("backup", 1, true) then title_last, title_frames = nil, 0 return end
	-- Which of the two menus is up: a log on the cartridge leaves its hero's name in memory, but
	-- deleting the log from this menu does not clear the name, so remember that it was deleted.
	if last_said == "Adventure log deleted." and not title_deleted then title_deleted, title_moved, title_rebuild = true, nil, true end
	-- the menu is built again once the message is closed: wait for that before saying it
	if title_rebuild then
		local m1, m2 = TITLE_MENUS[1], TITLE_MENUS[2]
		if u16(m1.obj + 0x74) ~= 0 and u16(m2.obj + 0x74) == 0 then title_rebuild, title_frames, title_last = false, 0, nil end
		return
	end
	local has_log = cstring(0x020FB258, 12) ~= "" and not title_deleted
	local menu = TITLE_MENUS[has_log and 2 or 1]
	-- and whichever menu's cursor moves is the one on screen
	for _, m in ipairs(TITLE_MENUS) do
		local c = u32(m.obj + 0x28)
		local pressed = (last_button_name == "up" or last_button_name == "down") and frame - last_button_frame < 15
		if pressed and m.seen and c ~= m.seen and u32(m.obj) == TITLE_VAR_CLASS then title_moved = m end
		m.seen = c
	end
	if title_moved then menu = title_moved end
	-- best of all: only the menu on screen has its list of choices filled in
	local filled = {}
	for _, m in ipairs(TITLE_MENUS) do
		if u32(m.obj) == TITLE_VAR_CLASS and u16(m.obj + 6) == m.id and u16(m.obj + 0x74) ~= 0 then filled[#filled + 1] = m end
	end
	if #filled == 1 then menu = filled[1] end
	if u32(menu.obj) ~= TITLE_VAR_CLASS or u16(menu.obj + 6) ~= menu.id then title_last, title_frames = nil, 0 return end
	if menu ~= title_menu then title_menu, title_frames, title_last = menu, 0, nil end
	title_frames = title_frames + 1
	if title_frames < 40 then return end            -- let the adventure log panel finish loading
	local cursor = u32(menu.obj + 0x28)
	local item = menu.items[cursor + 1]
	if not item then return end
	if title_last == nil then queue("Title screen. " .. item)
	elseif cursor ~= title_last then say(item, true) end
	title_last = cursor
end


-- map id -> { code, name }  (names from the game's own debug map list)
MAPIDS = {
	[1]={"K01"}, [3]={"K03"}, [100]={"C01","Stornway"}, [103]={"C01M03","House 3"},
	[104]={"C01M04","Weapon Shop"}, [105]={"C01M05","House 1"}, [106]={"C01M06","House 2"},
	[107]={"C01M07","Armour Shop"}, [108]={"C01M08","Item Shop"}, [109]={"C01M09","Church"},
	[110]={"C01M10"}, [112]={"C01M12","Basement"}, [114]={"C01M14","Interior"},
	[115]={"C01M15","Interior B1 - Dungeon"}, [116]={"C01M16","Interior B1 - Training Room"},
	[117]={"C01M17","Interior Lv 2 - Barracks"}, [118]={"C01M18","Interior Lv 2 - Throneroom"},
	[119]={"C01M19","Interior Lv 2 - Princess"}, [120]={"C01M20","Interior Lv 3"},
	[121]={"C01M21","Interior Lv 3 - Treasure Room"}, [123]={"C01M23","Well"},
	[124]={"C01M24","Underground Passage"}, [125]={"C01M25","Sealed Room"}, [198]={"C01M98","Exterior"},
	[200]={"C02","Gleeba"}, [201]={"C02M01"}, [202]={"C02M02","Palace Lv 1-1"},
	[203]={"C02M03","Palace Lv 1-2"}, [204]={"C02M04","Palace Lv 1-3"}, [205]={"C02M05","Palace Lv 2-1"},
	[206]={"C02M06","Palace Lv 2-2"}, [207]={"C02M07","Palace Lv 3"}, [208]={"C02M08"}, [209]={"C02M09"},
	[210]={"C02M10","New Well"}, [211]={"C02M11","Inn"}, [212]={"C02M12","Inn Lv 2"},
	[213]={"C02M13","Barracks"}, [214]={"C02M14","Barracks Lv 2"}, [215]={"C02M15","Dried-Up Well"},
	[216]={"C02M16"}, [217]={"C02M17","Casino Lv 1 (Old)"}, [218]={"C02M18","Casino Lv 2 (Old)"},
	[219]={"C02M19","Dance Hall"}, [400]={"C04","Gittingham Palace"}, [401]={"C04M01","South"},
	[402]={"C04M02","East"}, [403]={"C04M03","West"}, [404]={"C04M04","North"}, [405]={"C04M05","North Lv 2"},
	[406]={"C04M06"}, [407]={"C04M07","Lv 2"}, [408]={"C04M08","Lv 3"}, [409]={"C04M09","Lv 4"},
	[410]={"C04M10"}, [1100]={"M01","Angel Falls"}, [1101]={"M01M01","House A"}, [1102]={"M01M02","Inn"},
	[1103]={"M01M03"}, [1104]={"M01M04","Stable"}, [1105]={"M01M05","Mayor's House"}, [1106]={"M01M06"},
	[1107]={"M01M07","Erinn's House"}, [1108]={"M01M08"}, [1109]={"M01M09","Mayor's House Lv 2"},
	[1110]={"M01M10","Erinn's House Lv 2"}, [1111]={"M01M11"}, [1112]={"M01M12"}, [1200]={"M02","Zere"},
	[1201]={"M02M01","Petra's House"}, [1202]={"M02M02"}, [1203]={"M02M03"}, [1204]={"M02M04","House"},
	[1205]={"M02M05","Cave"}, [1206]={"M02M06","Petra's house B1"}, [1207]={"M02M07"},
	[1300]={"M03","Coffinwell"}, [1301]={"M03M01"}, [1302]={"M03M02","Inn Roof"}, [1303]={"M03M03"},
	[1304]={"M03M04","House B"}, [1305]={"M03M05","House B Lv 2"}, [1306]={"M03M06","Weapon & Armour Shop"},
	[1307]={"M03M07"}, [1308]={"M03M08","House C"}, [1309]={"M03M09"}, [1310]={"M03M10"},
	[1311]={"M03M11","Scholar's House"}, [1312]={"M03M12","Scholar's Study"}, [1313]={"M03M13"},
	[1500]={"M05","Porth Llaffan"}, [1501]={"M05M01"}, [1502]={"M05M02"}, [1503]={"M05M03"},
	[1504]={"M05M04"}, [1505]={"M05M05","Mayor's House"}, [1506]={"M05M06"}, [1700]={"M07","Zere Rocks"},
	[1701]={"M07M01"}, [1705]={"M07M05"}, [1706]={"M07M06","Petra's House B1"},
	[1800]={"M08","Dourbridge"}, [1801]={"M08M01"}, [1802]={"M08M02"}, [1803]={"M08M03","Mason's House"},
	[1804]={"M08M04","Bar on Left Under Bridge"}, [1805]={"M08M05","Item shop on Right Under Bridge"},
	[1806]={"M08M06"}, [1807]={"M08M07","Cap'n Meddlin's 'Castle'"},
	[1808]={"M08M08","Basement on Right Under Bridge"}, [1900]={"M09","Basement on Right Under Bridge"},
	[1901]={"M09M01"}, [1902]={"M09M02","Workshop"}, [1903]={"M09M03"},
	[1904]={"M09M04","Marion's House"}, [1905]={"M09M05","Marion's House Lv 2"},
	[1906]={"M09M06","Marion's House garden"}, [1907]={"M09M07","Terrace House"},
	[1908]={"M09M08","Craftsman's House"}, [1909]={"M09M09"}, [1910]={"M09M10"},
	[1911]={"M09M11","Inn B1"}, [1912]={"M09M12","Haunted House"}, [1913]={"M09M13","Haunted House B1"},
	[1914]={"M09M14"}, [1915]={"M09M15","Marion Bloome (Sepia)"},
	[1916]={"M09M16","x Marion Bloome garden (Sepia)"}, [2000]={"M10","Batsureg"}, [2001]={"M10M01"},
	[2002]={"M10M02"}, [2003]={"M10M03","Yurt A"}, [2004]={"M10M04","Yurt B"}, [2005]={"M10M05"},
	[2006]={"M10M06","Yurt C (Batzorig)"}, [2007]={"M10M07","Village Head's Yurt"},
	[2100]={"M11","Swinedimples Academy"}, [2101]={"M11M01","School Hall"}, [2102]={"M11M02","Corridor"},
	[2103]={"M11M03","Main Building@"}, [2104]={"M11M04","Chapel"}, [2105]={"M11M05","Main Building@Lv 2"},
	[2106]={"M11M06","Roof (Small Room A)"}, [2107]={"M11M07","Dormitory Lv 1 (Cafeteria)"},
	[2108]={"M11M08","Dormitory Lv 2"}, [2109]={"M11M09","Dormitory Lv 3 (Small Room B)"},
	[2200]={"M12","Wormwood Creek"}, [2201]={"M12M01"}, [2202]={"M12M02"}, [2203]={"M12M03"},
	[2204]={"M12M04"}, [2205]={"M12M05"}, [2206]={"M12M06"}, [2207]={"M12M07","x Exterior (Sepia)"},
	[2208]={"M12M08","x House (Sepia)"}, [2209]={"M12M09","x Church (Sepia)"}, [2210]={"M12M10"},
	[2211]={"M12M11"}, [2300]={"M13","Upover"}, [2301]={"M13M01","House 01"}, [2302]={"M13M02","House 02"},
	[2303]={"M13M03","House 03"}, [2304]={"M13M04"}, [2305]={"M13M05"}, [2306]={"M13M06"},
	[2307]={"M13M07"}, [2308]={"M13M08"}, [2309]={"M13M09"},
	[2310]={"M13M10","Underground Passage & Cave"}, [2311]={"M13M11"}, [2399]={"M13M99"},
	[4100]={"X01","Observatory"}, [4101]={"X01M01","Exterior 1"}, [4103]={"X01M03","Exterior 3"},
	[4104]={"X01M04","Exterior 4"}, [4105]={"X01M05","Lv 1-1"}, [4106]={"X01M06","Lv 1-2"},
	[4107]={"X01M07"}, [4109]={"X01M09"}, [4110]={"X01M10"}, [4200]={"X02","Alltrades Abbey"},
	[4201]={"X02M01"}, [4202]={"X02M02","Interior B1"}, [4300]={"X03","Realm of the Almighty"},
	[4301]={"X03M01","Realm of the Almighty 1"}, [4302]={"X03M02","Realm of the Almighty 2"},
	[4303]={"X03M03","Temple of the Almighty"}, [4304]={"X03M04","Temple of the Almighty Lv 2"},
	[4305]={"X03M05","Small Temple 1"}, [4306]={"X03M06","Small Temple 2"},
	[4309]={"X03M09","Temple of the Almighty Lv 1 (Sepia)"}, [4400]={"X04","Realm of the Mighty"},
	[4401]={"X04M01","Exterior 2"}, [4402]={"X04M02"}, [4403]={"X04M03","Realm of the Mighty -"},
	[4404]={"X04M04","Interior 1"}, [4405]={"X04M05","Interior 1-A"}, [4406]={"X04M06","Interior 1-B"},
	[4407]={"X04M07","Interior 1-C"}, [4408]={"X04M08","Interior 2"}, [4409]={"X04M09","Interior 3"},
	[4410]={"X04M10","Interior 4"}, [4411]={"X04M11","Interior 5"}, [4412]={"X04M12","Interior 6"},
	[4413]={"X04M13","Interior 7"}, [4414]={"X04M14","Disc 1"}, [4415]={"X04M15","Exterior - Disc"},
	[4416]={"X04M16","Disc 2"}, [4417]={"X04M17","Disc 3"}, [4418]={"X04M18","Disc 4"},
	[4419]={"X04M19","Disc 5"}, [4420]={"X04M20","Disc 6"}, [4421]={"X04M21","Disc 7"},
	[4422]={"X04M22","Exterior - Summit"}, [4423]={"X04M23","Summit -"}, [4424]={"X04M24","Summit - Lv 2"},
	[4425]={"X04M25","Corvus Appears"}, [4498]={"X04M98"}, [4499]={"X04M99"},
	[4500]={"X05","Observatory (After Attack)"}, [4501]={"X05M01"}, [4503]={"X05M03"},
	[4504]={"X05M04"}, [4505]={"X05M05"}, [4506]={"X05M06"}, [4507]={"X05M07"},
	[4509]={"X05M09"}, [4510]={"X05M10"}, [4511]={"X05M11","Exterior 4 (Destroyed)"},
	[4512]={"X05M12","For Ending (All Together)"}, [4513]={"X05M13","Lv 2 (sepia)"}, [5101]={"S01M01"},
	[5102]={"S01M02"}, [5200]={"S02","Loch Storn"}, [5300]={"S03","Eastern Checkpoint"},
	[5301]={"S03M01","Barracks"}, [5400]={"S04","Hexagon Hill"}, [5500]={"S05","Cuddiedig Cliff"},
	[5600]={"S06","Hunters' Yurts"}, [5601]={"S06M01"}, [5602]={"S06M02","Gortress"},
	[5700]={"S07","Gortress"}, [5701]={"S07M01","Cells - Stairs"}, [5702]={"S07M02","Watchtower -"},
	[5703]={"S07M03","Watchtower - Lv 2"}, [5704]={"S07M04","Gortress - Lv 2"},
	[5705]={"S07M05","Gortress - B1"}, [5706]={"S07M06","Slurry Quay"}, [5707]={"S07M07","Exterior - Cells"},
	[5800]={"S08","Slurry Quay"}, [5801]={"S08M01"}, [5900]={"S09","Ship - Deck"},
	[5901]={"S09M01","Captain's Cabin"}, [5902]={"S09M02","Passenger Cabin"}, [5903]={"S09M03","Hold"},
	[6000]={"S10","Mountain Hut"}, [6001]={"S10M01","Interior"}, [6100]={"S11","Ulbaruun Cave"},
	[6101]={"S11M01","Interior of the cave"}, [6200]={"S12","Bloomingdale Region"}, [6201]={"S12M01"},
	[6202]={"S12M02","Hope Springs"}, [6302]={"S13M02"}, [6303]={"S13M03"},
	[6304]={"S13M04","Exterior (Sepia)"}, [6305]={"S13M05","Cave (Sepia)"}, [6401]={"S14M01"},
	[6402]={"S14M02","Starflight Express - Carriage 3"}, [6403]={"S14M03","Starflight Express - ???"},
	[6404]={"S14M04","Starflight Express - Carriage 3, Small Room"}, [6405]={"S14M05"},
	[6500]={"S15","Wyrmward"}, [7100]={"D01","The Hexagon"}, [7101]={"D01M01"}, [7102]={"D01M02","B1"},
	[7103]={"D01M03","B2"}, [7104]={"D01M04","B1-A"}, [7105]={"D01M05","B1-B"}, [7301]={"D03M01"},
	[7302]={"D03M02","Interior - North-Western Tower"}, [7303]={"D03M03","Interior - B1"},
	[7304]={"D03M04","Interior - Eastern Tower"}, [7305]={"D03M05","Interior - Western Tower"},
	[7306]={"D03M06","Interior - Lv 2, Northern Tower Throneroom"},
	[7307]={"D03M07","Interior - Lv 1, Princess's Room"}, [7400]={"D04","Quarantomb"},
	[7401]={"D04M01","Inside the Shrine"}, [7402]={"D04M02","Interior -"}, [7403]={"D04M03"},
	[7601]={"D06M01","Exterior 01"}, [7602]={"D06M02","Interior - Lv 1-01"},
	[7603]={"D06M03","Interior - Lv 1-02"}, [7604]={"D06M04","Interior - Lv 2"}, [7605]={"D06M05","Exterior 02"},
	[7700]={"D07","Heights of Loneliness"}, [7701]={"D07M01","Heights of Loneliness 2"},
	[7702]={"D07M02","Heights of Loneliness 3"}, [7703]={"D07M03","Heights of Loneliness 4"},
	[7704]={"D07M04","Heights of Loneliness 5"}, [7705]={"D07M05","Heights of Loneliness 6"},
	[7706]={"D07M06","Heights of Loneliness 7"}, [7707]={"D07M07","Heights of Loneliness 8"},
	[7708]={"D07M08","Heights of Loneliness 9"}, [7709]={"D07M09","Heights of Loneliness 10"},
	[7802]={"D08M02","Interior - B1-A"}, [7803]={"D08M03","Interior - B1-B"},
	[7804]={"D08M04","Interior - B1 Room"}, [7805]={"D08M05","Interior - B2"}, [7806]={"D08M06","Interior - B3"},
	[7807]={"D08M07","Interior - B1 Dungeon"}, [7808]={"D08M08","Interior - B2 Graves"},
	[7809]={"D08M09","Interior - B3 Boss Room"}, [7900]={"D09","The Bad Cave"}, [7901]={"D09M01"},
	[7902]={"D09M02"}, [7903]={"D09M03","Interior - Lv 1-03"}, [7904]={"D09M04"},
	[7905]={"D09M05","Interior - B2-01"}, [7906]={"D09M06","Interior - B2-02"}, [8201]={"D12M01"},
	[8202]={"D12M02"}, [8203]={"D12M03"}, [8204]={"D12M04"}, [8205]={"D12M05"},
	[8206]={"D12M06","Gerzuun - Underground Passage"}, [8207]={"D12M07","Hidden Passage"},
	[8208]={"D12M08","Depths"}, [8301]={"D13M01","Interior - B1 Library"}, [8302]={"D13M02"},
	[8303]={"D13M03","Interior - B2 Classroom"}, [8400]={"D14","The Bowhole"}, [8401]={"D14M01","Cave 2 -"},
	[8402]={"D14M02","Cave 3 - B1"}, [8403]={"D14M03","Cave 4 -"}, [8404]={"D14M04","Cave 5 - B2"},
	[8405]={"D14M05","Cave 6 - B3"}, [8406]={"D14M06","Cave 7 - B4"}, [8407]={"D14M07","Cave 8 - B4 Interior"},
	[8602]={"D16M02"}, [8603]={"D16M03","Exterior - Lv 2"}, [8604]={"D16M04","Interior - Lv 3"},
	[8605]={"D16M05","Interior - Lv 4-1"}, [8606]={"D16M06","Interior - Lv 4-2"},
	[8607]={"D16M07","Interior - Lv 4-3"}, [8608]={"D16M08","Interior - Lv 5"},
	[8609]={"D16M09","Interior - Lv 6"}, [8610]={"D16M10","Exterior - Lv 6"},
	[8611]={"D16M11","Interior - Lv 7"}, [8612]={"D16M12"}, [8613]={"D16M13","Interior - Summit Interior"},
	[8701]={"D17M01"}, [8702]={"D17M02","Oubliette - B3"}, [8703]={"D17M03","B3"}, [8704]={"D17M04","B4"},
	[8705]={"D17M05","B5"}, [8706]={"D17M06","B6"}, [8707]={"D17M07"}, [9000]={"T01","Tower of Trades"},
	[9001]={"T01M01"}, [9002]={"T01M02","Tower of Trades - Lv 3"},
	[9003]={"T01M03","Tower of Trades - Lv 4"}, [9004]={"T01M04","Tower of Trades - Lv 5"},
	[9005]={"T01M05","Lv 5"}, [9006]={"T01M06","Lv 6"}, [9007]={"T01M07","Lv 7"},
	[9008]={"T01M08","Ceremonial Chamber"}, [9100]={"T02","Tower of Nod"}, [9101]={"T02M01"},
	[9102]={"T02M02","Tower of Nod - Lv 3"}, [9103]={"T02M03","Tower of Nod - Lv 4"},
	[9104]={"T02M04","Tower of Nod - Lv 5"}, [9105]={"T02M05"}, [9106]={"T02M06","Lv 5 Exterior"},
	[9107]={"T02M07"}, [9108]={"T02M08","Exterior - Top"}, [9199]={"T02M99"}, [10000]={"O00","Ocean"},
	[10100]={"O01"}, [15100]={"H01","Island Shrine"}, [15200]={"H02","Way-Out Well"},
	[15300]={"H03","Pool of Spirits"}, [15400]={"H04","Forest Clearing"}, [15500]={"H05","Nicholas's Cabin"},
	[15600]={"H06","Woody Nickitt's House"}, [15700]={"H07","Tree in Lake"}, [15800]={"H08","Sequoia's Hideout"},
	[15900]={"H09","Uhohasis"}, [16000]={"H10","Herman's House"}, [16100]={"H11","Chris Cringle's Cottage"},
	[16200]={"H12","Chris Cringle's Paddock"}, [16300]={"H13","Brian's Cave"}, [16400]={"H14","Sealed Well"},
	[16500]={"H15","Doris's House"}, [16600]={"H16","Monster Research Institute"},
	[16700]={"H17","Eastern Wormwood"}, [16800]={"H18","Mountaintop Well - South"},
	[16900]={"H19","Western Wormwood"}, [17000]={"H20","Wyrmtail"}, [19997]={"F99M02"},
	[19998]={"F99M01"}, [19999]={"F99"}, [20000]={"K02"}, [20001]={"F01"},
	[20002]={"F02","Western Stornway Region"}, [20003]={"F03"}, [20004]={"F04","Doomingale Forest"},
	[20005]={"F05","Eastern Coffinwell Region"}, [20006]={"F06","Western Coffinwell Region"},
	[20007]={"F07","Newid Isle"}, [20008]={"F08"}, [20009]={"F09","Slurry Coast"},
	[20010]={"F10","Bloomingdale"}, [20011]={"F11","Dourbridge Region"}, [20012]={"F12","Lonely Plains"},
	[20013]={"F13"}, [20014]={"F14"}, [20015]={"F15","Djust Desert"}, [20016]={"F16","Hermany"},
	[20017]={"F17","Pluvi Isle"}, [20018]={"F18","Snowberia"}, [20019]={"F19","Cringle Coast"},
	[20020]={"F20","Urdus Marshland"}, [20021]={"F21","Iluugazar Plains"}, [20022]={"F22","Mt Ulzuun"},
	[20023]={"F23","Mt Ulbaruun"}, [20024]={"F24","Khaalag Coast"}, [20025]={"F25","Ondor Cliffs"},
	[20026]={"F26","Eastern Wormwood Region"}, [20027]={"F27","Western Wormwood Region"},
	[20028]={"F28","Wormwood Canyon"}, [20029]={"F29","Wyrmtail Region"}, [20030]={"F30","Wyrmwing Region"},
	[20031]={"F31"}, [20032]={"F32","Wyrmsmaw Region"}, [20033]={"F33","Wyrmneck Region"},
	[20034]={"F34","The Gittish Empire"}, [20038]={"F38","Eastern Stornway Region"},
	[20039]={"F39","Snowberian Coast"}, [20040]={"F40","Lonely Coast"}, [20041]={"F41"}, [20042]={"F42"},
	[20043]={"F43"}, [20044]={"F44"}, [20045]={"F45"}, [20046]={"F46"}, [20047]={"F47"},
	[20048]={"F48"}, [20049]={"F49"}, [20050]={"F50"}, [20051]={"F51"}, [20052]={"F52"},
	[20053]={"F53"}, [20054]={"F54"}, [20055]={"F55"}, [20056]={"F56"},
	[20057]={"F57","Hermany (Starflight)"}, [20058]={"F58"}, [20059]={"F59"}, [20060]={"F60"},
	[20061]={"F61"}, [20062]={"F62"}, [20063]={"F63","Zere Region"}, [20101]={"F01M01"},
	[20102]={"F01M02"}, [20111]={"F10M01","Bloomingdale (ending)"}, [20207]={"F07M02","Newid Isle (ending)"},
	[20341]={"F34M01","The Gittish Empire (ending)"}, [40001]={"Z00M01","Treasure Map -"},
	[40002]={"Z00M02","Treasure Map - Lv 2"}, [40003]={"Z00M03","Treasure Map - Lv 3"},
	[40004]={"Z00M04","Treasure Map - Lv 4"}, [40005]={"Z00M05","Treasure Map - Lv 5"},
	[40006]={"Z00M06","Treasure Map - Lv 6"}, [40007]={"Z00M07","Treasure Map - Lv 7"},
	[40008]={"Z00M08","Treasure Map - Lv 8"}, [40009]={"Z00M09","Treasure Map - Lv 9"},
	[40010]={"Z00M10","Treasure Map - Lv 10"}, [40011]={"Z00M11","Treasure Map - Lv 11"},
	[40012]={"Z00M12","Treasure Map - Lv 12"}, [40013]={"Z00M13","Treasure Map - Lv 13"},
	[40014]={"Z00M14","Treasure Map - Lv 14"}, [40015]={"Z00M15","Treasure Map - Lv 15"},
	[40016]={"Z00M16","Treasure Map - Lv 16"}, [40021]={"Z00M21"}, [40022]={"Z00M22"},
	[40023]={"Z00M23"}, [40024]={"Z00M24"}, [40025]={"Z00M25"}, [40026]={"Z00M26"},
	[40027]={"Z00M27"}, [40028]={"Z00M28"}, [40029]={"Z00M29"}, [40030]={"Z00M30"},
	[40031]={"Z00M31"}, [40032]={"Z00M32"}, [40033]={"Z00M33"}, [40034]={"Z00M34"},
	[40035]={"Z00M35"}, [40036]={"Z00M36"}, [40041]={"Z00M41"}, [40042]={"Z00M42"},
	[40043]={"Z00M43"}, [40044]={"Z00M44"}, [40045]={"Z00M45"}, [40046]={"Z00M46"},
	[40047]={"Z00M47"}, [40048]={"Z00M48"}, [40049]={"Z00M49"}, [40050]={"Z00M50"},
	[40051]={"Z00M51"}, [40052]={"Z00M52"}, [40053]={"Z00M53"}, [40054]={"Z00M54"},
	[40055]={"Z00M55"}, [40056]={"Z00M56"}, [40061]={"Z00M61"}, [40062]={"Z00M62"},
	[40063]={"Z00M63"}, [40064]={"Z00M64"}, [40065]={"Z00M65"}, [40066]={"Z00M66"},
	[40067]={"Z00M67"}, [40068]={"Z00M68"}, [40069]={"Z00M69"}, [40070]={"Z00M70"},
	[40071]={"Z00M71"}, [40072]={"Z00M72"}, [40073]={"Z00M73"}, [40074]={"Z00M74"},
	[40075]={"Z00M75"}, [40076]={"Z00M76"}, [40081]={"Z00M81"}, [40082]={"Z00M82"},
	[40083]={"Z00M83"}, [40084]={"Z00M84"}, [40085]={"Z00M85"}, [40086]={"Z00M86"},
	[40087]={"Z00M87"}, [40088]={"Z00M88"}, [40089]={"Z00M89"}, [40090]={"Z00M90"},
	[40091]={"Z00M91"}, [40092]={"Z00M92"}, [40093]={"Z00M93"}, [40094]={"Z00M94"},
	[40095]={"Z00M95"}, [40096]={"Z00M96"}, [40101]={"Z01M01","Natural Level 1"},
	[40102]={"Z01M02","Natural Level 2"}, [40103]={"Z01M03","Natural Level 3"},
	[40104]={"Z01M04","Natural Level 4"}, [40105]={"Z01M05","Natural Level 5"},
	[40106]={"Z01M06","Natural Level 6"}, [40107]={"Z01M07","Natural Level 7"},
	[40108]={"Z01M08","Natural Level 8"}, [40109]={"Z01M09","Natural Level 9"},
	[40110]={"Z01M10","Natural Level 10"}, [40111]={"Z01M11","Natural Level 11"},
	[40112]={"Z01M12","Natural Level 12"}, [40201]={"Z02M01","Man-Made Level 1"},
	[40202]={"Z02M02","Man-Made Level 2"}, [40203]={"Z02M03","Man-Made Level 3"},
	[40204]={"Z02M04","Man-Made Level 4"}, [40205]={"Z02M05","Man-Made Level 5"},
	[40206]={"Z02M06","Man-Made Level 6"}, [40207]={"Z02M07","Man-Made Level 7"},
	[40208]={"Z02M08","Man-Made Level 8"}, [40209]={"Z02M09","Man-Made Level 9"},
	[40210]={"Z02M10","Man-Made Level 10"}, [40211]={"Z02M11","Man-Made Level 11"},
	[40212]={"Z02M12","Man-Made Level 12"}, [40301]={"Z03M01","Icy Level 1"}, [40302]={"Z03M02","Icy Level 2"},
	[40303]={"Z03M03","Icy Level 3"}, [40304]={"Z03M04","Icy Level 4"}, [40305]={"Z03M05","Icy Level 5"},
	[40306]={"Z03M06","Icy Level 6"}, [40307]={"Z03M07","Icy Level 7"}, [40308]={"Z03M08","Icy Level 8"},
	[40309]={"Z03M09","Icy Level 9"}, [40310]={"Z03M10","Icy Level 10"}, [40311]={"Z03M11","Icy Level 11"},
	[40312]={"Z03M12","Icy Level 12"}, [40401]={"Z04M01","Watery Level 1"}, [40402]={"Z04M02","Watery Level 2"},
	[40403]={"Z04M03","Watery Level 3"}, [40404]={"Z04M04","Watery Level 4"},
	[40405]={"Z04M05","Watery Level 5"}, [40406]={"Z04M06","Watery Level 6"},
	[40407]={"Z04M07","Watery Level 7"}, [40408]={"Z04M08","Watery Level 8"},
	[40409]={"Z04M09","Watery Level 9"}, [40410]={"Z04M10","Watery Level 10"},
	[40411]={"Z04M11","Watery Level 11"}, [40412]={"Z04M12","Watery Level 12"},
	[40501]={"Z05M01","Fiery Level 1"}, [40502]={"Z05M02","Fiery Level 2"}, [40503]={"Z05M03","Fiery Level 3"},
	[40504]={"Z05M04","Fiery Level 4"}, [40505]={"Z05M05","Fiery Level 5"}, [40506]={"Z05M06","Fiery Level 6"},
	[40507]={"Z05M07","Fiery Level 7"}, [40508]={"Z05M08","Fiery Level 8"}, [40509]={"Z05M09","Fiery Level 9"},
	[40510]={"Z05M10","Fiery Level 10"}, [40511]={"Z05M11","Fiery Level 11"},
	[40512]={"Z05M12","Fiery Level 12"}, [41101]={"Z01M95","Natural Level Boss Floor"}, [41102]={"Z01M96"},
	[41103]={"Z01M97"}, [41104]={"Z01M98"}, [41105]={"Z01M99"},
	[41201]={"Z02M95","Man-Made Level Boss Floor"}, [41202]={"Z02M96"}, [41203]={"Z02M97"},
	[41204]={"Z02M98"}, [41205]={"Z02M99"}, [41301]={"Z03M95","Icy Level Boss Floor"},
	[41302]={"Z03M96"}, [41303]={"Z03M97"}, [41304]={"Z03M98"}, [41305]={"Z03M99"},
	[41401]={"Z04M95","Watery Level Boss Floor"}, [41402]={"Z04M96"}, [41403]={"Z04M97"},
	[41404]={"Z04M98"}, [41405]={"Z04M99"}, [41501]={"Z05M95","Fiery Level Boss Floor"},
	[41502]={"Z05M96"}, [41503]={"Z05M97"}, [41504]={"Z05M98"},
	[41505]={"Z05M99","R - Quester's Rest"}, [50101]={"R01M01","Lobby Interior 1"},
	[50102]={"R01M02","Lounge Interior 1"}, [50103]={"R01M03","Guest Room Interior 1"},
	[50107]={"R01M07","Guardian Fountain"}, [50108]={"R01M08","Royal Suites - Corridor"},
	[50109]={"R01M09","Royal Suites - East"}, [50110]={"R01M10","Royal Suites - West"},
	[50201]={"R02M01","Lobby Interior 2"}, [50202]={"R02M02","Lounge Interior 2"},
	[50203]={"R02M03","Guest Room Interior 2"}, [50204]={"R02M04","Cafeteria Interior 2"},
	[50205]={"R02M05","Executive Suite Interior 2"}, [50301]={"R03M01","Lobby Interior 3"},
	[50302]={"R03M02","Lounge Interior 3"}, [50303]={"R03M03","Guest Room Interior 3"},
	[50304]={"R03M04","Cafeteria Interior 3"}, [50305]={"R03M05","Executive Suite Interior 3"},
	[50306]={"R03M06","Library Interior 3"}, [50401]={"R04M01","Lobby Interior 4"},
	[50402]={"R04M02","Lounge Interior 4"}, [50403]={"R04M03","Guest Room Interior 4"},
	[50404]={"R04M04","Cafeteria Interior 4"}, [50405]={"R04M05","Executive Suite Interior 4"},
	[50406]={"R04M06","Library Interior 4"}, [50501]={"R05M01","VIP - Cannock"},
	[50502]={"R05M01","VIP - Cannock"}, [50503]={"R05M01","VIP - Cannock"}, [50504]={"R05M01","VIP - Cannock"},
	[50505]={"R05M01","VIP - Cannock"}, [50506]={"R05M01","VIP - Cannock"}, [50507]={"R05M01","VIP - Cannock"},
	[50508]={"R05M01","VIP - Cannock"}, [50509]={"R05M01","VIP - Cannock"}, [50510]={"R05M01","VIP - Cannock"},
	[50511]={"R05M01","VIP - Cannock"}, [50512]={"R05M01","VIP - Cannock"}, [50513]={"R05M01","VIP - Cannock"},
	[50514]={"R05M01","VIP - Cannock"}, [50515]={"R05M01","VIP - Cannock"}, [50516]={"R05M01","VIP - Cannock"},
	[50517]={"R05M01","VIP - Cannock"}, [50518]={"R05M01","VIP - Cannock"}, [50519]={"R05M01","VIP - Cannock"},
	[50520]={"R05M01","VIP - Cannock"}, [50521]={"R05M01","VIP - Cannock"}, [50522]={"R05M01","VIP - Cannock"},
	[50523]={"R05M01","VIP - Cannock"}, [51101]={"E01M01","Credits B"}, [51102]={"E01M02","Credits C"},
	[51103]={"E01M03","Credits D"}, [51104]={"E01M04","Credits F"}, [51105]={"E01M05","Credits H"},
	[51106]={"E01M06","Credits I"}, [51107]={"E01M07","Credits S"}, [51108]={"E01M08","Credits T"},
	[51109]={"E01M09","Credits J"}, [51110]={"E01M10","Credits K"}, [51111]={"E01M11","Credits L"},
}

-- Names the table above was missing, taken from the game's own map list (data/map/maplist9.bin):
-- each map's record gives its code and its name, such as M01M06 "Church" in Angel Falls.
MAP_NAMES_FROM_GAME = {
	[110]="Well", [201]="Exterior", [208]="House 1", [209]="House 2", [216]="Church",
	[406]="Lv 1", [410]="Metamorphosis Event", [1103]="Item Shop", [1106]="Church", [1108]="Well",
	[1111]="Opening Event", [1112]="Opening (Background)", [1202]="Church", [1203]="Inn", [1207]="Well",
	[1301]="Inn", [1303]="House A", [1307]="Church", [1309]="Mayor's House Lv 1", [1310]="Mayor's House Lv 2",
	[1313]="Well", [1501]="Inn", [1502]="House", [1503]="Item Shop", [1504]="Weapon & Armour Shop",
	[1506]="Church", [1701]="Petra's House", [1705]="Cave", [1801]="House 1", [1802]="House 2",
	[1806]="Inn", [1901]="Mayor's House", [1903]="Church", [1909]="Inn Lv 1", [1910]="Inn Lv 2",
	[1914]="Well", [2001]="Weapon & Armour Shop", [2002]="Inn", [2005]="Cave", [2201]="Inn",
	[2202]="Weapon & Armour Shop", [2203]="Item Shop", [2204]="House", [2205]="Church", [2206]="Well",
	[2210]="Serena Flashback Event", [2211]="Serena Flashback Event Cont.", [2304]="Inn", [2305]="Item Shop", [2306]="Weapon Shop",
	[2307]="Armour Shop", [2308]="Mayor's House", [2309]="Church", [2311]="Well", [2399]="All Events",
	[4107]="Lv 2", [4109]="Lv 4", [4110]="Lv 4 - For Events", [4201]="Interior Lv 1", [4402]="Exterior 3",
	[4498]="For Events", [4499]="All Events", [4501]="Exterior 3", [4503]="Exterior 3", [4504]="Exterior 4",
	[4505]="Lv 1-1", [4506]="Lv 1-2", [4507]="Lv 2", [4509]="Lv 4", [4510]="Lv 4 (For Events)",
	[5101]="Exterior", [5102]="Event", [5601]="Yurt A", [5801]="Inn", [6201]="Interior - Lv 1",
	[6302]="Exterior", [6303]="Cave", [6401]="Starflight Express - Carriage 1", [6405]="For Events", [7101]="Lv 1",
	[7301]="Exterior", [7403]="Interior - B1", [7901]="Interior - Lv 1-01", [7902]="Interior - Lv 1-02", [7904]="Interior - B1",
	[8201]="Exterior", [8202]="Church", [8203]="Interior - B1", [8204]="Yurt A", [8205]="Well",
	[8302]="Interior - B2", [8602]="Interior - Lv 2", [8612]="Exterior - Summit", [8701]="B1", [8707]="N - Scenario Events (All Together)",
	[9001]="Lv 1", [9101]="Lv 1", [9105]="Lv 5", [9107]="Lv 6", [9199]="For IN Events Only",
}
for id, name in pairs(MAP_NAMES_FROM_GAME) do
	if MAPIDS[id] and not MAPIDS[id][2] then MAPIDS[id][2] = name end
end

AREAS = {
	C01="Stornway", C02="Gleeba", C04="Gittingham Palace", D01="The Hexagon", D04="Quarantomb",
	D07="Heights of Loneliness", D09="The Bad Cave", D14="The Bowhole", F02="Western Stornway Region",
	F04="Doomingale Forest", F05="Eastern Coffinwell Region", F06="Western Coffinwell Region", F07="Newid Isle",
	F09="Slurry Coast", F10="Bloomingdale", F11="Dourbridge Region", F12="Lonely Plains", F15="Djust Desert",
	F16="Hermany", F17="Pluvi Isle", F18="Snowberia", F19="Cringle Coast", F20="Urdus Marshland",
	F21="Iluugazar Plains", F22="Mt Ulzuun", F23="Mt Ulbaruun", F24="Khaalag Coast", F25="Ondor Cliffs",
	F26="Eastern Wormwood Region", F27="Western Wormwood Region", F28="Wormwood Canyon", F29="Wyrmtail Region",
	F30="Wyrmwing Region", F32="Wyrmsmaw Region", F33="Wyrmneck Region", F34="The Gittish Empire",
	F38="Eastern Stornway Region", F39="Snowberian Coast", F40="Lonely Coast", F57="Hermany (Starflight)",
	F63="Zere Region", H01="Island Shrine", H02="Way-Out Well", H03="Pool of Spirits", H04="Forest Clearing",
	H05="Nicholas's Cabin", H06="Woody Nickitt's House", H07="Tree in Lake", H08="Sequoia's Hideout",
	H09="Uhohasis", H10="Herman's House", H11="Chris Cringle's Cottage", H12="Chris Cringle's Paddock",
	H13="Brian's Cave", H14="Sealed Well", H15="Doris's House", H16="Monster Research Institute",
	H17="Eastern Wormwood", H18="Mountaintop Well - South", H19="Western Wormwood", H20="Wyrmtail",
	M01="Angel Falls", M02="Zere", M03="Coffinwell", M05="Porth Llaffan", M07="Zere Rocks", M08="Dourbridge",
	M09="Basement on Right Under Bridge", M10="Batsureg", M11="Swinedimples Academy", M12="Wormwood Creek",
	M13="Upover", O00="Ocean", S02="Loch Storn", S03="Eastern Checkpoint", S04="Hexagon Hill",
	S05="Cuddiedig Cliff", S06="Hunters' Yurts", S07="Gortress", S08="Slurry Quay", S09="Ship - Deck",
	S10="Mountain Hut", S11="Ulbaruun Cave", S12="Bloomingdale Region", S15="Wyrmward", T01="Tower of Trades",
	T02="Tower of Nod", X01="Observatory", X02="Alltrades Abbey", X03="Realm of the Almighty",
	X04="Realm of the Mighty", X05="Observatory (After Attack)",
	-- from the game's own map list (the name before each area's first map)
	S01="Mountain Pass", D03="Brigadoom", D06="Tywll Cave", D12="Gerzuun", D13="Swinedimples Old School",
	D17="Oubliette", S14="Starflight Express", Z00="Grotto",
}
-- item number -> name, read from the game's own item table
ITEM_NAMES = {
	[12170]="wonder helm", [12171]="heavenly helm", [12180]="raging bull helm", [12181]="minotaur helm", [12182]="great helm", [12183]="veteran's helm",
	[12184]="skull helm", [12185]="liquid metal helm", [12186]="metal king helm", [12187]="rusty helmet", [12188]="hallowed helm", [12189]="blessed helm",
	[12191]="iron helmet", [12192]="Ragnar's helm", [12193]="Alefgard helm", [12194]="Erdrick's helmet", [12195]="Midenhall helm", [12197]="metal slime helm",
	[12198]="steel helmet", [12199]="gigasteel helmet", [12200]="feather headband", [12201]="circlet", [12202]="battler's band", [12204]="ravishing ribbon",
	[12205]="hairband", [12206]="crown of clarity", [12207]="steely sweatband", [12208]="silver tiara", [12209]="golden tiara", [12211]="gold circlet",
	[12212]="star circlet", [12290]="Aliahan headpiece", [12291]="spellward circlet", [12292]="Zenithian helm", [12295]="thinking cap", [12296]="scholar's circlet",
	[12400]="warrior's helm", [12401]="hocus hat", [12402]="hermetic hat", [12403]="musketeer hat", [12404]="cavalier hat", [12405]="Minerva's mitre",
	[12406]="canny cap", [12407]="hunter's hat", [12408]="ear cosy", [12409]="top hat", [12410]="bandana", [12411]="hardwood headwear",
	[12412]="sun crown", [12413]="Apollo's crown", [12414]="trailblazing bandana", [12415]="Mercury's bandana", [12416]="feathered cap", [12417]="magical hat",
	[12418]="mega-magical hat", [12419]="witch's hat", [12420]="unhappy hat", [12421]="happy hat", [12422]="spring breeze hat", [12423]="summer cloud hat",
	[12424]="autumn shower hat", [12425]="winter sky hat", [12426]="Kiryl's kamilavka", [12428]="Santa's hat", [12429]="holy hat", [12430]="Torneko's cap",
	[12431]="Yangus's titfer", [12432]="Erinn's headkerchief", [12433]="tip-top topper", [12434]="proper topper", [12436]="swashbuckler's bonnet", [12480]="mitre",
	[12491]="Trodain bandana", [12492]="Gothan turban", [12493]="Estard hood", [12494]="Alena's hat", [12495]="turban", [12496]="pointy hat",
	[12497]="slime crown", [12498]="leather hat", [12499]="wizard's hat", [12500]="thug's mug", [12501]="Trodeface", [12502]="pumpkin head",
	[12503]="skull cap", [12600]="tricky turban", [12700]="thief's turban", [12701]="disturbin' turban", [12702]="mail coif", [12780]="Moonbrooke hood",
	[12781]="Maribel's hood", [12785]="dragon warrior helm", [12790]="iron mask", [12791]="filigree mask", [12792]="platinum headgear", [12793]="mythril coif",
	[12794]="Hades' helm", [12795]="mythril helm", [12796]="fur hood", [12797]="slood", [12800]="bunny ears", [12801]="cat ears",
	[12802]="phantom mask", [12803]="stellar starflower", [12804]="Fleurette's floret", [12805]="halo", [12806]="Debora's damasks", [12807]="malleable mask",
	[12808]="papillon mask", [12809]="maid's mop", [12810]="silken veil", [12811]="supernatural specs", [12812]="sharp shades", [12813]="monarchic moustache",
	[12814]="x-ray specs", [12815]="silver specs", [12900]="Somnia hair", [12901]="Cannock helm", [12902]="Borya's bouffant", [12903]="Maya's mane",
	[12904]="Meena's mane", [12907]="Bianca's braid", [12908]="Nera's hair", [12909]="Carver's hair", [12910]="Milly's hair", [12911]="Ashlynn's hair",
	[12912]="Kiefer's hair", [12913]="Jess's tresses", [12914]="Templar's tresses", [12915]="Morrie's mullet", [12916]="brown afro", [12917]="red afro",
	[13000]="warrior's armour", [13001]="tussler's top", [13002]="flamenco shirt", [13003]="fur vest", [13004]="star's suit", [13005]="plain clothes",
	[13006]="training top", [13007]="celestial suit", [13009]="Swinedimples blazer", [13010]="tracksuit top", [13011]="garish garb", [13012]="cloak of evasion",
	[13013]="cloak of concealment", [13014]="gooey gear", [13015]="smart suit", [13016]="superstar's suit", [13017]="dragon top", [13018]="combat top",
	[13020]="twinkling tuxedo", [13021]="tropotoga", [13022]="stratotoga", [13023]="mesotoga", [13024]="exotoga", [13025]="Carver's vest",
	[13026]="Kiefer's clothes", [13027]="Yangus's billy", [13028]="GUSTO garb", [13031]="muscle belt", [13032]="best vest", [13033]="glombolero",
	[13034]="Aquila's armour", [13035]="white tuxedo", [13036]="Santa suit", [13037]="skeleton suit", [13038]="captain's coat", [13039]="white t-shirt",
	[13040]="jolly roger jumper", [13041]="shipmate's shirt", [13080]="Midenhall garb", [13095]="wayfarer's clothes", [13096]="Trodain togs", [13097]="Somnia clothes",
	[13098]="Estard clothes", [13099]="Zenithian clothes", [13100]="tactical vest", [13101]="leather armour", [13102]="scale armour", [13103]="chain mail",
	[13160]="mythical armour", [13161]="legendary armour", [13162]="dragon warrior armour", [13170]="sacrosanct armour", [13171]="veteran's armour", [13172]="mirror armour",
	[13173]="catoptric armour", [13174]="gigant armour", [13175]="liquid metal armour", [13176]="metal king armour", [13177]="rusty armour", [13178]="victorious armour",
	[13179]="glorious armour", [13180]="silver mail", [13181]="gold mail", [13182]="platinum mail", [13183]="heavy armour", [13184]="magic armour",
	[13185]="enchanted armour", [13186]="ethereal armour", [13187]="dragon mail", [13188]="spiked armour", [13189]="sacred armour", [13190]="metal slime armour",
	[13192]="iron armour", [13193]="Ragnar's armour", [13194]="Alefgard armour", [13195]="Erdrick's armour", [13196]="large-scale armour", [13197]="bronze armour",
	[13198]="full plate armour", [13199]="gigasteel armour", [13200]="holy mail", [13201]="fencing frock", [13202]="nomadic deel", [13203]="leather cape",
	[13204]="fur poncho", [13205]="velvet cape", [13206]="majestic mantle", [13207]="dark robe", [13208]="macabre mantle", [13209]="Pallium Regale",
	[13210]="cape of good karma", [13211]="Templar's togs", [13290]="Aliahan clothes", [13291]="Gothan robe", [13292]="divine dress", [13300]="ascetic robe",
	[13301]="rogue's robes", [13302]="roguess's robes", [13303]="fencing jacket", [13304]="sage's robe", [13305]="silk robe", [13306]="robe of serenity",
	[13307]="nightmare gown", [13308]="Celestria's gown", [13309]="Celestria's raiment", [13310]="dragon robe", [13311]="Xenlon robe", [13312]="angel's robe",
	[13313]="archangel's robe", [13314]="aeon's robe", [13315]="seraph's robe", [13316]="Kiryl's clothes", [13317]="Borya's robe", [13318]="Torneko's clothes",
	[13320]="Trode's robes", [13324]="robe of sweet dreams", [13325]="magical robes", [13326]="enchanted robes", [13327]="ethereal robes", [13328]="saintly robe",
	[13329]="flowing dress", [13390]="wizard's robe", [13391]="witch's robe", [13490]="surplice", [13491]="Cannock cloak", [13500]="strongsam",
	[13501]="priestess's pinafore", [13502]="dancer's dress", [13503]="maiden's mantle", [13504]="spangled dress", [13505]="dragon dress", [13506]="shimmering dress",
	[13507]="queen's robe", [13508]="empress's robe", [13509]="prince's pea coat", [13510]="king's coat", [13511]="emperor's attire", [13513]="Moonbrooke dress",
	[13514]="Meena's robe", [13515]="Nera's dress", [13516]="Milly's clothes", [13517]="Maribel's clothes", [13518]="Jessica's frock", [13519]="leather dress",
	[13520]="plain dress", [13521]="summer dress", [13522]="jaguarment", [13590]="princess's robe", [13600]="Fizzle-retardant blouse", [13601]="Femiscyran mail",
	[13602]="brawling byrnie", [13603]="holy femail", [13604]="tint-tastic tutu", [13605]="dancer's costume", [13606]="bunny suit", [13607]="technicolour tutu",
	[13608]="dangerous bikini top", [13609]="hot bikini top", [13610]="sizzling bikini top", [13612]="dangerous bustier", [13613]="silk bustier", [13614]="divine bustier",
	[13615]="Maya's outfit", [13616]="Bianca's clothes", [13617]="Ashlynn's clothes", [13618]="stellar suit", [13619]="Fleurette's frock", [13620]="maid outfit",
	[13621]="Debora's dress", [13622]="Erinn's outfit", [13623]="Patty's dirndl", [13624]="Sellma's frock", [13625]="wedding dress", [13626]="Santa's little helper suit",
	[13627]="combat costume", [13695]="Zenithian leotard", [13696]="Alena's dress", [13700]="Fizzle-retardant suit", [13701]="Fizzle-proof suit", [13790]="iron cuirass",
	[13791]="tortoise shell", [13793]="silver cuirass", [13794]="tortoiseshell armour", [15000]="warrior's gloves", [15001]="gorgeous gloves", [15002]="mental mittens",
	[15003]="cotton gloves", [15004]="linen gloves", [15005]="leather gloves", [15007]="riotous wristbands", [15008]="blessed bindings", [15009]="rubber gloves",
	[15010]="wayfarer's gloves", [15013]="mayoress's mittens", [15014]="marquess's mittens", [15015]="monarch's mittens", [15016]="veteran's gloves", [15017]="enchantress's gloves",
	[15018]="minister's mittens", [15019]="glommer's gloves", [15020]="guru's gloves", [15021]="gloomy gloves", [15022]="murky mittens", [15023]="matador's gloves",
	[15024]="apprentice's gloves", [15025]="master's gloves", [15026]="grandmaster's gloves", [15027]="godly gloves", [15028]="Zenithian gauntlet", [15029]="Gothan wristbands",
	[15030]="Maya's bracelets", [15031]="Meena's bracelets", [15032]="heavy handwear", [15033]="silver bracelets", [15034]="Bianca's bracelets", [15035]="Nera's bracelets",
	[15036]="Carver's bracers", [15037]="Milly's bracers", [15038]="Ashlynn's gloves", [15039]="ultramarine mittens", [15040]="blindin' bracers", [15041]="Angelo's gloves",
	[15042]="grandissimo gloves", [15043]="battler's bracers", [15045]="einhander", [15047]="crimson gauntlets", [15048]="lockpicker's mitts", [15091]="Kiefer's gloves",
	[15092]="Alefgard gloves", [15093]="Midenhall gloves", [15094]="Cannock gloves", [15095]="Aliahan gloves", [15096]="McRyan's mittens", [15097]="Alena's gloves",
	[15100]="fingerless gauntlets", [15101]="bruiser's bracers", [15102]="Femiscyran fingerwear", [15103]="metallic mitts", [15105]="light gauntlets", [15106]="archer's armguard",
	[15107]="sturdy gauntlets", [15108]="heavy gauntlets", [15109]="fingerless gloves", [15190]="Somnia gloves", [15200]="leather gauntlets", [15280]="ethereal gloves",
	[15281]="rusty gauntlets", [15282]="Vesta gauntlets", [15283]="Diana gauntlets", [15284]="Tempestes gauntlets", [15285]="Sol Invictus gauntlets", [15286]="dragon warrior gloves",
	[15291]="iron gauntlets", [15292]="Erdrick's gauntlets", [15293]="steel gauntlets", [15294]="gigasteel gauntlets", [15295]="metal slime gauntlets", [15296]="liquid metal slime gloves",
	[15297]="metal king slime gloves", [15298]="magic mittens", [15299]="enchanted gloves", [16093]="Somnia shorts", [16094]="boxer shorts", [16095]="leather kilt",
	[16100]="Femiscyran bottoms", [16103]="chainmail socks", [16104]="pop socks", [16191]="Zenithian leggings", [16200]="warrior's trousers", [16202]="nicker's knickers",
	[16203]="tussler's trousers", [16204]="wizard's trousers", [16205]="loud trousers", [16206]="battle britches", [16207]="swordsman's slacks", [16208]="red tights",
	[16209]="green tights", [16210]="steppe steppers", [16211]="blessed bottoms", [16212]="white tights", [16213]="cotton trousers", [16214]="training trousers",
	[16215]="celestial stockings", [16216]="boomer briefs", [16217]="wonder pants", [16218]="iron kneecaps", [16219]="steel kneecaps", [16220]="gigasteel kneecaps",
	[16221]="fancy pants", [16222]="transparent tights", [16223]="dragon trousers", [16224]="combat trousers", [16228]="tantric trousers", [16229]="sturdy slacks",
	[16230]="impregnable leggings", [16231]="invincible trousers", [16232]="immortal trousers", [16233]="eternity trousers", [16234]="infinity trousers", [16235]="Cannock trousers",
	[16236]="Kiryl's trousers", [16237]="Torneko's trousers", [16240]="Carver's shorts", [16241]="Milly's pants", [16243]="Kiefer's trousers", [16244]="cor blimey trousers",
	[16245]="PASSION tights", [16246]="stellar stockings", [16248]="Fleurette's chaussettes", [16251]="toughie trousers", [16252]="Templar's trousers", [16255]="tracky bottoms",
	[16256]="dragon warrior trousers", [16257]="Aquila's trousers", [16258]="Swinedimples slacks", [16259]="white tuxedo trousers", [16260]="Santa's slacks", [16261]="skeletal slacks",
	[16262]="pirate pantaloons", [16263]="blue jeans", [16283]="trinity tights", [16286]="Midenhall trousers", [16287]="Alefgard trousers", [16288]="Aliahan trousers",
	[16289]="Zenithian trousers", [16290]="Estard trousers", [16291]="Trodain trousers", [16300]="sorcerer's slacks", [16301]="slick slacks", [16302]="fishnet stockings",
	[16303]="dangerous midriff wrap", [16304]="hot bikini bottoms", [16305]="sizzling bikini bottoms", [16306]="Swinedimples skirt", [16307]="red skirt", [16308]="blue skirt",
	[16309]="kiltlet", [16310]="Maya's bottoms", [16311]="denim skirt", [16312]="blue knickers", [16313]="black knickers", [16316]="springtime skirt",
	[16317]="snazzy skirt", [16318]="magical skirt", [16319]="seabreeze skirt", [16390]="Alena's tights", [17091]="Gothan gumboots", [17092]="Somnia boots",
	[17093]="Estard shoes", [17094]="Zenithian boots", [17095]="Aliahan boots", [17096]="Trodainers", [17100]="warrior's boots", [17101]="frugal footwear",
	[17102]="bandit boots", [17103]="sneakers", [17104]="kung fu shoes", [17105]="wizard wellies", [17106]="acroboots", [17107]="wu shoes",
	[17108]="Femiscyran footwear", [17109]="cowboy boots", [17110]="hip boots", [17111]="safety shoes", [17112]="clever clogs", [17113]="shaman shoes",
	[17114]="agiliboots", [17115]="hiking boots", [17116]="bardic boots", [17117]="crimson boots", [17118]="leather boots", [17119]="wellington boots",
	[17120]="celestial shoes", [17140]="Erinn's boots", [17141]="Patty's pumps", [17142]="Aquila's boots", [17143]="white wing-tips", [17150]="Blahnolo Maniks",
	[17152]="chic chaussures", [17155]="thug boots", [17158]="Borya's boots", [17159]="spellspadrilles", [17160]="Ashlynn's shoes", [17163]="Kiefer's shoes",
	[17164]="Maribel's shoes", [17165]="Trode's treads", [17166]="bovver boots", [17167]="posh pumps", [17168]="Templar boots", [17169]="Casanova clogs",
	[17170]="pixie boots", [17171]="tricksie boots", [17172]="Moonbrooke shoes", [17173]="Kiryl's boots", [17176]="Bianca's boots", [17177]="Nera's boots",
	[17178]="Carver's shoes", [17179]="Milly's shoes", [17181]="brahman boots", [17182]="hero's boots", [17183]="basilic boots", [17184]="emperor's boots",
	[17185]="boots of beatitude", [17186]="safer shoes", [17187]="safest shoes", [17188]="depressing shoes", [17189]="elevating shoes", [17191]="valenki",
	[17192]="Alefgard boots", [17193]="Midenhall boots", [17194]="Cannock boots", [17195]="hobnail boots", [17196]="veteran's boots", [17197]="combat boots",
	[17198]="she-mage shoes", [17199]="blessed boots", [17300]="payback pumps", [17302]="saintly sollerets", [17303]="dragon warrior boots", [17391]="iron sabatons",
	[17392]="highland boots", [17394]="metal slime sollerets", [17395]="steel sabatons", [17396]="gigasteel sabatons", [17397]="liquid metal slime boots", [17398]="metal king slime boots",
	[17400]="siren sandals", [17401]="she-fu shoes", [17402]="sheepskin shoes", [17403]="starlet sandals", [17404]="leather shoes", [17405]="clogs",
	[17406]="sandals", [17407]="classy clogs", [17408]="high heels", [17409]="stiletto heels", [17410]="highness heels", [17411]="galvanised geta",
	[17412]="sorceress sandals", [17413]="high-class heels", [17414]="sensible sandals", [17415]="sagacious sandals", [17416]="sapient sandals", [17417]="sentient sandals",
	[17419]="Torneko's sandals", [17420]="Sattriya sandals", [17421]="Samhita sandals", [18000]="strength ring", [18001]="tough guy tattoo", [18002]="raging ruby",
	[18003]="mighty armlet", [18004]="gold bracer", [18005]="slime earrings", [18006]="dragon scale", [18007]="gold ring", [18008]="ruby of protection",
	[18009]="bunny tail", [18010]="pink pearl", [18011]="bow tie", [18012]="utility belt", [18013]="agility ring", [18014]="meteorite bracer",
	[18015]="sorcerer's ring", [18016]="gold rosary", [18017]="rosary", [18018]="sorcerer's stone", [18019]="brainy bracer", [18020]="life bracer",
	[18021]="spirit bracer", [18022]="monarchic mark", [18023]="prayer ring", [18024]="holy talisman", [18025]="sober ring", [18026]="contra band",
	[18027]="full moon ring", [18028]="rousing ring", [18029]="ring of clarity", [18030]="catholicon ring", [18031]="terrible tattoo", [18032]="skull ring",
	[18033]="elfin charm", [18034]="life ring", [18035]="Goddess ring", [18038]="reckless necklace", [18039]="lucky pendant", [18040]="Venus' tear",
	[18043]="soldier's medal", [18044]="lifesaving medal", [18045]="mager achievement", [18046]="Mercury prize", [18047]="honour among thieves", [18048]="wear-with-all award",
	[18049]="critical acclaim", [18050]="order of chivalry", [18051]="combat action medal", [18052]="medal of freedom", [18053]="legion of merit", [18054]="Noscar",
	[18055]="wedding ring", [19050]="paring knife", [19051]="bronze knife", [19052]="divine dagger", [19053]="poison moth knife", [19054]="batterfly knife",
	[19055]="dread dagger", [19057]="poison needle", [19058]="assassin's dagger", [19059]="icicle dirk", [19060]="Fenrir fang", [19061]="deadly nightblade",
	[19062]="sword breaker", [19063]="soul breaker", [19064]="falcon knife earring", [19065]="gladius", [19066]="flame tang", [19067]="pruning knife",
	[19068]="deft dagger", [19069]="darting dagger", [19070]="dashing dagger", [19071]="dynamo dagger", [19150]="oaken club", [19151]="ace of clubs",
	[19152]="sledgehammer", [19153]="war hammer", [19154]="Uber war hammer", [19155]="giant wrench", [19156]="terra tamper", [19157]="terra firmer",
	[19158]="terra hammer", [19159]="marauder's maul", [19160]="Hela's hammer", [19161]="giant's hammer", [19162]="titan's hammer", [19163]="megaton hammer",
	[19164]="warlord's hammer", [19165]="groundbreaker", [19166]="earthsplitter", [19167]="moonmasher", [19168]="starsmasher", [20000]="warrior's sword",
	[20001]="bandit blade", [20002]="Valkyrie sword", [20003]="rapier", [20004]="copper sword", [20005]="soldier's sword", [20006]="iron broadsword",
	[20007]="steel broadsword", [20008]="gigasteel broadsword", [20009]="Fizzle foil", [20010]="cautery sword", [20011]="aurora blade", [20012]="platinum sword",
	[20013]="dragonsbane", [20014]="dragon slayer", [20015]="falcon blade", [20016]="Uber falcon blade", [20017]="miracle sword", [20018]="Uber miracle sword",
	[20019]="fire blade", [20020]="inferno blade", [20021]="metal slime sword", [20022]="liquid metal sword", [20023]="metal king sword", [20024]="rusty sword",
	[20025]="Erdrick's sword", [20026]="stardust sword", [20027]="nebula sword", [20028]="supernova sword", [20029]="hypernova sword", [20100]="feather fan",
	[20101]="iron fan", [20102]="steel fan", [20103]="gigasteel fan", [20104]="war fan", [20105]="foehn fan", [20106]="gale force fan",
	[20107]="tortoiseshell fan", [20108]="Black Tortoise fan", [20109]="feline fan", [20110]="White Tiger fan", [20111]="fowl fan", [20112]="Vermillion Bird fan",
	[20113]="cobra fan", [20114]="Azure Dragon fan", [20115]="stellar fan", [20116]="lunar fan", [20117]="solar fan", [20118]="friendly fan",
	[20119]="attribeauty", [20120]="critical fan", [20121]="overcritical fan", [20122]="hypercritical fan", [20123]="dire critical fan", [20124]="white bouquet",
	[20200]="battle-axe", [20201]="pro's axe", [20202]="steel axe", [20203]="gigasteel axe", [20204]="golden axe", [20205]="moon axe",
	[20206]="full moon axe", [20207]="kaiser axe", [20208]="headsman's axe", [20209]="executioner's axe", [20210]="ice axe", [20211]="avalanche axe",
	[20212]="heavy hatchet", [20213]="bad axe", [20214]="maxi axe", [20215]="climaxe", [20216]="galaxy axe", [20291]="king axe",
	[20293]="iron axe", [20300]="leather whip", [20301]="thorn whip", [20302]="battle whip", [20303]="snakeskin whip", [20304]="serpentine whip",
	[20305]="sidewinder", [20306]="chain whip", [20307]="iron whip", [20308]="spiked steel whip", [20309]="gigaspike whip", [20310]="dragontail whip",
	[20311]="demon whip", [20312]="archdemon whip", [20313]="scourge whip", [20314]="queen's whip", [20315]="empress's whip", [20316]="Goddess whip",
	[20317]="wizardly whip", [20318]="Gringham whip", [20319]="mega Gringham whip", [20320]="giga Gringham whip", [20321]="Uber Gringham whip", [20400]="hieroglyph staff",
	[20401]="sage's staff", [20402]="brouhaha boomstick", [20403]="oak staff", [20404]="staff of sentencing", [20405]="staff of divine wrath", [20406]="Stolos' staff",
	[20407]="lightning conductor", [20408]="watermaul wand", [20409]="tsunami staff", [20410]="rune staff", [20411]="mega-magical mace", [20412]="Sceptre of Gitt",
	[20413]="savant's staff", [20414]="wyrmwand", [20415]="bright staff", [20416]="shining staff", [20417]="brilliant staff", [20418]="aurora staff",
	[20419]="faerie staff", [20493]="magical mace", [20494]="wizard's staff", [20495]="lightning staff", [20496]="magma staff", [20500]="bamboo lance",
	[20501]="celestial spear", [20502]="partisan", [20503]="iron lance", [20504]="steel lance", [20505]="gigasteel lance", [20506]="long spear",
	[20507]="holy lance", [20508]="battle fork", [20509]="trident", [20510]="Gracos's trident", [20511]="sandstorm spear", [20512]="halberd",
	[20513]="lightning lance", [20514]="storm spear", [20515]="demon spear", [20516]="hero spear", [20517]="metal slime spear", [20518]="liquid metal spear",
	[20519]="metal king spear", [20520]="poker", [20521]="stud poker", [20522]="split-pot poker", [20523]="red-hot poker", [20600]="laundry pole",
	[20601]="carrying pole", [20602]="oaken pole", [20603]="iron bar", [20604]="steel bar", [20605]="gigasteel bar", [20606]="pillar of strength",
	[20607]="sleepy stick", [20608]="slumber stick", [20609]="driller pillar", [20610]="killer pillar", [20611]="mistick", [20612]="optimistick",
	[20613]="ballistick", [20614]="sadistick", [20615]="dragon rod", [20616]="Xenlon rod", [20617]="orichalcudgel", [20618]="knockout rod",
	[20619]="senseless stick", [20620]="catatonic cosh", [20621]="coma cudgel", [20700]="boomerang", [20701]="reinforced boomerang", [20702]="edged boomerang",
	[20703]="cutting-edge boomerang", [20704]="crucerang", [20705]="razor-wing boomerang", [20706]="razer-wing boomerang", [20707]="erazor-wing boomerang", [20708]="swallowtail",
	[20709]="eaglewing", [20710]="gusterang", [20711]="blusterang", [20712]="flametang boomerang", [20713]="banefire boomerang", [20714]="pentarang",
	[20715]="hexarang", [20716]="meteorang", [20717]="asterang", [20718]="stellarang", [20719]="galaxarang", [20800]="stone claws",
	[20801]="iron claws", [20802]="steel claws", [20803]="gigasteel claws", [20804]="sacred claws", [20805]="razor claws", [20806]="crow's claws",
	[20807]="kestrel claws", [20808]="kite claws", [20809]="handrills", [20810]="hammer handrills", [20811]="dragon claws", [20812]="fire claws",
	[20813]="combusticlaws", [20814]="cobra claws", [20815]="king cobra claws", [20816]="beast claws", [20817]="beastmaster claws", [20818]="orichalcum claws",
	[20819]="Dragonlord claws", [20820]="Dragovian claws", [20821]="Dragovian lord claws", [20822]="Xenlon claws", [20900]="potshot bow", [20901]="short bow",
	[20902]="longbow", [20903]="hunter's bow", [20904]="Fuddle bow", [20905]="Cheiron's bow", [20906]="hotshot bow", [20907]="blowy bow",
	[20908]="billowing bow", [20909]="blustery bow", [20910]="great bow", [20911]="purblind bow", [20912]="blinding bow", [20913]="oh-no bow",
	[20914]="Odin's bow", [20915]="angel's bow", [20916]="archangel's bow", [20917]="aeon's bow", [20918]="seraph's bow", [21000]="warrior's shield",
	[21001]="shell shield", [21002]="kitty shield", [21003]="catty shield", [21004]="light shield", [21005]="platinum shield", [21006]="tempest shield",
	[21007]="saintess shield", [21008]="Goddess shield", [21009]="rusty shield", [21010]="brain drainer", [21011]="psyche swiper", [21012]="devilry drinker",
	[21013]="soul sucker", [21014]="slime shield", [21091]="bronze shield", [21092]="iron shield", [21093]="steel shield", [21095]="gigasteel shield",
	[21190]="metal slime shield", [21191]="Erdrick's shield", [21192]="scale shield", [21193]="liquid metal shield", [21194]="metal king shield", [21200]="white knight's shield",
	[21280]="enchanted shield", [21281]="ethereal shield", [21282]="empowered shield", [21290]="magic shield", [21291]="leather shield", [21292]="power shield",
	[21294]="silver shield", [21295]="white shield", [21296]="pot lid", [21297]="silver platter", [21298]="gold platter", [21299]="platinum platter",
	[21390]="flame shield", [21391]="dragon shield", [21392]="boss shield", [21393]="ruinous shield", [21394]="ogre shield", [21395]="ice shield",
	[21396]="dark shield", [21397]="big boss shield", [22000]="medicinal herb", [22001]="strong medicine", [22002]="special medicine", [22003]="superior medicine",
	[22004]="antidotal herb", [22005]="strong antidote", [22006]="special antidote", [22007]="moonwort bulb", [22008]="softwort", [22009]="lunaria",
	[22010]="angel bell", [22011]="panacea", [22012]="perfect panacea", [22013]="Yggdrasil leaf", [22014]="Yggdrasil dew", [22015]="magic water",
	[22016]="sage's elixir", [22017]="elfin elixir", [22018]="holy water", [22019]="chimaera wing", [22020]="mystifying mixture", [22021]="coagulant",
	[22022]="tangleweb", [22023]="sleeping hibiscus", [22024]="wakerobin", [22025]="party popper", [22026]="festive feast", [22027]="block o' choc",
	[22028]="choice chocolate", [22029]="basic biscuits", [22030]="posh biscuits", [22031]="Christmas cake", [22032]="birthday cake", [22033]="rockbomb shard",
	[22034]="watcher's wings", [22035]="sage's stone", [22036]="Gleeban groat", [22037]="Gleeban guinea", [22038]="Gleeban gold piece", [22039]="mini medal",
	[22041]="pretty betsy", [22045]="seed of life", [22046]="seed of magic", [22047]="seed of strength", [22048]="seed of deftness", [22049]="seed of agility",
	[22050]="seed of defence", [22051]="seed of sorcery", [22052]="seed of therapeusis", [22053]="seed of skill", [22070]="iron nails", [22071]="iron ore",
	[22072]="platinum ore", [22073]="mythril ore", [22074]="densinium", [22075]="gold bar", [22076]="orichalcum", [22077]="Hephaestus' flame",
	[22078]="cowpat", [22079]="horse manure", [22080]="saint's ashes", [22081]="enchanted stone", [22082]="ethereal stone", [22083]="wing of bat",
	[22084]="astral plume", [22085]="magic beast hide", [22086]="magic beast horn", [22087]="slimedrop", [22088]="butterfly wing", [22089]="kitty litter",
	[22090]="glass frit", [22091]="belle cap", [22092]="fisticup", [22093]="lava lump", [22094]="fresh water", [22095]="flurry feather",
	[22096]="royal soil", [22097]="ice crystal", [22098]="thunderball", [22099]="evencloth", [22100]="brighten rock", [22101]="tortoiseshell",
	[22102]="toad oil", [22103]="lambswool", [22104]="snakeskin", [22105]="manky mud", [22106]="corundum", [22107]="reset stone",
	[22108]="celestial skein", [22109]="sainted soma", [22110]="lucida shard", [22111]="agate of evolution", [22112]="resurrock", [22113]="mirrorstone",
	[22114]="sunstone", [22115]="flintstone", [22116]="malicite", [22117]="slipweed", [22118]="thinkincense", [22119]="narspicious",
	[22120]="seashell", [22121]="crimson coral", [22122]="emerald moss", [22123]="finessence", [22124]="aggressence", [22125]="MIMIC STONE",
	[22126]="BLARNEY STONE", [22141]="nectar", [22142]="birdsong nectar", [22143]="grubby bandage", [22144]="technicolour dreamcloth", [22256]="Sterling's whistle",
	[22257]="Evac-u-bell", [22258]="chronocrystal", [22259]="red orb", [22260]="blue orb", [22261]="yellow orb", [22262]="green orb",
	[22263]="purple orb", [22264]="silver orb", [22265]="\"Swordcraft in Summary\"", [22266]="\"Clear Spear Theory\"", [22267]="\"Knifing Know-How\"", [22268]="\"Wands and Beyond\"",
	[22269]="\"Working with Whips\"", [22270]="\"Staff Studies\"", [22271]="\"The Core of the Claw\"", [22272]="\"Further Fanmanship\"", [22273]="\"Advanced Axecraft\"", [22274]="\"Hardcore Hammering\"",
	[22275]="\"The Boomerang Bible\"", [22276]="\"Archery for the Adept\"", [22277]="\"Fearsome Fisticuffing\"", [22278]="\"Secrets of the Shield\"", [22279]="\"Warrior's Workbook\"", [22280]="\"Priest's Primer\"",
	[22281]="\"Mage's Manual\"", [22282]="\"Martial Artist's Manual\"", [22283]="\"Thief's Theory\"", [22284]="\"Minstrel's Manual\"", [22285]="\"Gladiator's Guide\"", [22286]="\"Paladin's Primer\"",
	[22287]="\"Armamentalist's Album\"", [22288]="\"Ranger's Revelations\"", [22289]="\"Sage's Scripture\"", [22290]="\"Luminary's Lore\"",
}
-- What each item is, from the game's own descriptions (data/prm/itemexpl.gp2), by item id.
ITEM_DESC = {
	[12170]="A holy helm that holds off confusion<,> illusion and poison.", [12171]="A godly guard against confusion<,> illusion<,> poison and death.", [12180]="Horned headgear for the wild at heart.", [12181]="Hardcore horned headgear for the real wild card.",
	[12182]="A hat made of a magical metal that<1>s stouter than steel.", [12183]="A skull-saver sported by bygone battlers.", [12184]="A blood-curdling cap for the cranium that curses the curious.", [12185]="Priceless protection packed with the power of liquid metal slimes.",
	[12186]="High-class headgear in which sits the soul of a metal king slime.", [12187]="A poorly preserved headpiece that precious little is known about.", [12188]="A helm offering holy protection against confusion and illusion.", [12189]="A holy helm hardy against confusion<,> illusion and poison.",
	[12191]="A humble hat made of iron.", [12192]="Plucky poll protection made use of by McRyan.", [12193]="A helmet habitually worn by a hero of Alefgard.", [12194]="A historic helm that harbours the might of a legendary hero.",
	[12195]="A helmet undeniably hailing from His Majesty of Midenhall.", [12197]="A handy helmet that harbours the hardiness of metal slimes.", [12198]="A hardy hat made of steel.", [12199]="A handsome hat made of hard gigasteel.",
	[12200]="A plumed piece of kit most often worn by minstrels.", [12201]="An accessory made to make foreheads more fancy.", [12202]="Guarding garb that bedecks the brow of many a gladiator.", [12204]="Pretty paraphernalia that<1>s part of every luminary<1>s allure.",
	[12205]="An appealing accessory worn on the head.", [12206]="A headpiece once worn by a whilom sage.", [12207]="A headband for martial artists strengthened with strands of steel.", [12208]="A lavishly crafted adornment for ladies<1> locks.",
	[12209]="Gorgeous golden headgear worn by women.", [12211]="An elegant accessory made from an expensive metal.", [12212]="A confusion-confounding accoutrement that sparkles with starlight.", [12290]="A gleaming garland given a great popularity boost by a legendary hero.",
	[12291]="A holy headpiece that hinders the effects of harmful spells.", [12292]="A hip helmet that a Zenithian hero would happily have on.", [12295]="A hat that heightens its wearer<1>s magical might.", [12296]="High-brow headgear that heavily heightens its wearer<1>s magical might.",
	[12400]="A sturdy protective skin for the skull mostly worn by warriors.", [12401]="An enigmatic extra of which enchanters are often enamoured.", [12402]="Holy headwear that all but halts the effects of death magic.", [12403]="A posh piece of plumed headgear put on by armamentalists.",
	[12404]="A high-class hat aimed squarely at extravagant armamentalists.", [12405]="A certain symbol of the supreme savvy of a sage.", [12406]="A nice piece of nogginwear that shows how savvy a sage is.", [12407]="Red-blooded rigging worn by rangers on the hunt.",
	[12408]="A fluffy trademark of the really committed ranger.", [12409]="The telltale trappings of a luminary.", [12410]="A bog-standard band to wrap around the bonce.", [12411]="A humdrum headpiece made from a hollowed out stump.",
	[12412]="A classy coronet that beats bouts of sleep and confusion.", [12413]="A cosmic coronet that banishes sleep and confusion.", [12414]="An understated skull wrap that subtly shines.", [12415]="Enchanted attire for the head that enhances its wearer<1>s agility.",
	[12416]="A feathery hat that<1>s the height of fashion.", [12417]="A hat that heightens its wearer<1>s magical might.", [12418]="A mysterious hat that meets the requirements of magic users.", [12419]="A hat sported by a sorceress of centuries past.",
	[12420]="A perplexingly pitiful piece of headgear.", [12421]="A curious cap that accumulates MP as its wearer wanders about.", [12422]="An odd ornament for the head that obstructs Dazzle magic.", [12423]="An odd ornament for the head that obstructs death magic.",
	[12424]="An odd ornament for the head that obstructs confusion.", [12425]="An odd ornament for the head that obstructs sleep-inducing magic.", [12426]="A tall bonce embellishment that belonged to Bishop Kiryl.", [12428]="The bright red hat that Santa Claus adores.",
	[12429]="Holy headwear that hinders the effects of death magic.", [12430]="A small-scale skullcap signed inside by Torneko Taloon.", [12431]="A spiky skullcap scented with the sweet smell of Yangus<1>s sweat.", [12432]="The basic bandana Erinn wears to keep her hair under control.",
	[12433]="A bright white hat that fulfils the requirements of formal dress.", [12434]="A classy black hat that fulfils the requirements of formal dress.", [12436]="The piratical hat worn by well-known seafarers the world over.", [12480]="A holy hat that perched on the head of a priest from the past.",
	[12491]="A cloth head-covering worn by a warrior of Trodain.", [12492]="A no-frills fabric headpiece loved by the long-lost king of Gotha.", [12493]="A favourite of fishermen that<1>s particularly popular in Estard.", [12494]="A triangular topper modelled on that of a tough tsarevna.",
	[12495]="A lengthy cloth wrap that keeps the conk cosy and safe.", [12496]="A tiny topper with a tapered tip.", [12497]="A crown worn by a king slime.", [12498]="A highly ordinary headpiece of hardened hide.",
	[12499]="A hat once worn by a whilom wizard.", [12500]="A horny head covering that thugs thrive in.", [12501]="A fancy-dress facemask featuring King Trode<1>s famous phiz.", [12502]="Want to look just like a jack o<1> lantern? Well<,> look no further!",
	[12503]="A super-realistic skull mask that will scare everyone silly!", [12600]="A remarkable wrap that<1>s made for mages.", [12700]="A length of fabric that thieves like to loop around their heads.", [12701]="A shadow-shrouded turban thought highly of by thieves.",
	[12702]="A heavy hood made from interlaced iron loops.", [12780]="A classy cowl popularised by a princess of Moonbrooke.", [12781]="A cute cowl carrying Maribel<1>s bona fide signature.", [12785]="A gift given by Greygnarl as a token of friendship.",
	[12790]="A complete metal covering for the cranium.", [12791]="Protection for the whole head prettified with precious metal.", [12792]="A pretty piece of protection for the head made from platinum.", [12793]="A hardy hood made from interlaced loops of the mighty metal mythril.",
	[12794]="A horned hat with a fiendish face that begets misfortune.", [12795]="An eye-catching cap made from the mighty metal mythril.", [12796]="A snug skin hood that softens the shock of shivery climes.", [12797]="A cute cover for the head with a slimy slant.",
	[12800]="A rabbity requirement for the bona fide bunny girl.", [12801]="An eared headband that makes a full-on feline fashion statement.", [12802]="A magical mask that musters aplomb and agility in its master.", [12803]="A flowery frill for furnishing the hair in Stella<1>s style.",
	[12804]="A black bloom to embellish the hair in Fleurette<1>s fancy style.", [12805]="A replica of a radiant ring that reveals a real Celestrian.", [12806]="Debora Briscoletti<1>s beloved hair embellishment.", [12807]="A flamboyant facemask that protects against paralysis attacks.",
	[12808]="A fantastic facemask that fends off paralysis attacks.", [12809]="A hairband that no maid could manage without.", [12810]="The piece that takes pride of place atop the bridal mop.", [12811]="Enchanted eyewear that enhances magical might a bit.",
	[12812]="Radical wrap-arounds worn by self-proclaimed kings of cool.", [12813]="Stick this on and you<1>ll seem like some kind of revered royal...probably.", [12814]="Enchanted eyewear that enhances magical mending a bit.", [12815]="Geeky glasses that give off an air of intelligent appeal.",
	[12900]="A handsome hairdo that harks back to that of the Prince of Somnia.", [12901]="Avant-garde goggled nogginwear perfect for the Prince of Cannock.", [12902]="A silvery shock resembling that of the sorcerer Borya.", [12903]="A hairdo that harks back to that of the dazzling dancer Maya.",
	[12904]="Long<,> lavish hairdo modelled on that of Meena the mystic.", [12907]="An unpretentious plait like that of the boyish yet beautiful Bianca.", [12908]="Beautiful<,> long blue hair like that of Nera Briscoletti.", [12909]="A manly Mohican mop in Carver<1>s style.",
	[12910]="Long blond locks like those worn by Milly.", [12911]="Ashlynn<1>s tufts tied up at the top.", [12912]="Prince Kiefer<1>s raucous<,> roguish hairdo.", [12913]="A twin ponytail that Jessica touts as being terrific for travelling.",
	[12914]="Angelo<1>s painstakingly preened handsome haircut.", [12915]="A barber-baffling head of hair modelled in a Morrie-esque style.", [12916]="The biggest style a brunette can bestow upon their bonce.", [12917]="The raddest style a redhead can bestow upon their bonce.",
	[13000]="A snazzy suit of armour that would suit a snooty soldier.", [13001]="An outfit for male martial artists to wear in real-life combat.", [13002]="Rose-coloured regalia that<1>s right on for male performers.", [13003]="Body-hugging boyswear that fends off fire- and ice-based attacks.",
	[13004]="A suit for celebrities who have a need to be noticed.", [13005]="A bog-standard bit of kit made of common cloth.", [13006]="A loose garment made for ease of movement when working out.", [13007]="Astral attire made from incredible ingredients.",
	[13009]="The uniform of an acclaimed academy.", [13010]="A loose garment made for tougher training sessions.", [13011]="Ta-daa! Glitzy<,> some might say gaudy<,> garb for stars of the stage.", [13012]="Uncommon clothing that makes evading enemy attacks easier.",
	[13013]="Enchanted attire that makes evading enemy attacks easier.", [13014]="Wobbly wear oozing with fancy-dress flair for an amazing translimation.", [13015]="A super-smart and stylish suit for the most fastidious of fops.", [13016]="A sparkling suit for an illustrious luminary.",
	[13017]="Martial artist<1>s attire that impedes attacks of fire and ice.", [13018]="A piece of clothing worn by pre-modern male martial artists.", [13020]="A supernatural suit that sporadically reflects spells.", [13021]="A reassuring wrap that repels fire<,> ice<,> poison<,> sleep and paralysis.",
	[13022]="A resistant wrap that repels fire<,> ice<,> poison<,> sleep and paralysis.", [13023]="A radical wrap that repels fire<,> ice<,> poison<,> sleep and paralysis.", [13024]="The perfect protection against fire<,> ice<,> poison<,> sleep and paralysis.", [13025]="A vest of Carver<1>s that could easily be mistaken for a ratty rag.",
	[13026]="A scarlet suit once worn by Prince Kiefer.", [13027]="A furry waistcoat that once failed to fully contain Yangus<1>s chest.", [13028]="One of Morrie<1>s special suits of carefully clashing colours.", [13031]="A belt for the bare skin that bolsters the beauty of brawn.",
	[13032]="A fetching and fashionable vest.", [13033]="Curious clothing that absorbs the power of magic cast on it.", [13034]="Would wearing this make you feel like some kind of superior Celestrian?", [13035]="What the groom wears at a slightly snazzy white wedding.",
	[13036]="Jolly old Father Christmas<1>s inimitable outfit. Ho ho ho!", [13037]="The spooky<,> skeletal top half of a bone-themed ensemble.", [13038]="A coat cut for a cutlass-wielding captain of considerable renown.", [13039]="A plain<,> white t-shirt.",
	[13040]="A scary top sporting a skull-and-crossbones design.", [13041]="A stripy shirt for seafaring souls.", [13080]="An outfit ostensibly worn by the Prince of Midenhall.", [13095]="Hardy hempen togs treasured by travellers.",
	[13096]="The type of suit a certain Trodain trooper might be tricked out in.", [13097]="A simple suit sported by the Prince of Somnia.", [13098]="Commonplace clothing that can be purchased in Estard.", [13099]="An unadorned outfit worn by a hero of Zenithia.",
	[13100]="Combat clobber for high-grade male gladiators.", [13101]="Fully frill-free armour of firm<,> tanned leather.", [13102]="A suit of armour with a scaly skin.", [13103]="A supple suit made from little loops of wire.",
	[13160]="Impermeable armour that mends HP and MP merely by moving about.", [13161]="Unparalleled protection that mends HP and MP merely by moving about.", [13162]="Armour given by Greygnarl as a token of friendship.", [13170]="A splendid suit that helps heal its wearer<1>s wounds in battle.",
	[13171]="Ancient armour said to harbour the soul of a bygone battler.", [13172]="Enchanted armour that sometimes sends spells back to their source.", [13173]="A resplendent suit that sometimes sends spells back to their source.", [13174]="Heavy armour<,> strong against fire-<,> ice- and lightning-based attacks.",
	[13175]="Armour with a liquid metal slime emblem that staves off spells.", [13176]="Armour with a metal king slime emblem that staves off spells.", [13177]="A spoilt<,> sorrowful suit of armour of obscure origin.", [13178]="Mystical mail that mends HP and MP merely by moving about.",
	[13179]="Acclaimed armour that mends HP and MP merely by moving about.", [13180]="An argent suit of armour that deflects a dash of magic damage.", [13181]="Protective golden garb that deflects a dash of magic damage.", [13182]="Precious protection that can deflect a dash of magic damage.",
	[13183]="A sturdy suit that staves off some fire- and ice- based strife.", [13184]="A strange suit of armour that staves off spells.", [13185]="A saintly suit of armour that staves off spells.", [13186]="A stupendous suit of armour that staves off spells.",
	[13187]="A scaly suit that deflects fire- and ice-based damage.", [13188]="Artful armour that reflects damage right back at its source.", [13189]="Enchanted armour that helps heal its wearer<1>s wounds in battle.", [13190]="Armour with a metal slime emblem that staves off spells.",
	[13192]="Metal armour that covers the upper quarters.", [13193]="A replica of Ragnar McRyan<1>s royal guard<1>s armour.", [13194]="Mail made to mimic that worn by a hero of Alefgard.", [13195]="Archetypal armour once worn by a heralded hero.",
	[13196]="Armour constructed with a covering of carefully selected scales.", [13197]="Armour made of alloyed metal plates.", [13198]="Steel armour that covers the upper quarters.", [13199]="A very hard version of full plate armour.",
	[13200]="Protection for male paladins that guards against ungodly powers.", [13201]="Female armamentalist<1>s attire that impedes the impact of magic attacks.", [13202]="A kilt revered by rangers for possessing the power of the earth.", [13203]="A toasty<,> tanned-leather type of attire.",
	[13204]="A sturdy skin that staves off fire and ice attacks.", [13205]="A classy cloak that improves one<1>s appearance.", [13206]="A regal wrap that enhances the elegance of any outfit eightfold.", [13207]="A gloomy-looking gown that sends enemy attacks astray.",
	[13208]="Dingy drapery that makes dodging enemy attacks a doddle.", [13209]="A gown that grants only real royalty the right to wear it.", [13210]="A male sage<1>s surplice that fights Fizzle and MP draining.", [13211]="Audacious red attire readily donned by the Templar Angelo.",
	[13290]="A supple suit supposedly sported by a legendary hero.", [13291]="A frugal gown that once graced the shoulders of the King of Gotha.", [13292]="A lady sage<1>s surplice that fights Fizzle and MP draining.", [13300]="A virtuous vestment for male priests that stops MP being stolen.",
	[13301]="Apparel apparently worn by principled male pilferers.", [13302]="Apparel apparently worn by principled female pilferers.", [13303]="Male armamentalist<1>s attire that impedes the impact of magic attacks.", [13304]="A gorgeous gown that guards against magic damage.",
	[13305]="A quality cape spun from silk yarn.", [13306]="Stops some attacks that would otherwise send the wearer to sleep.", [13307]="A deadly dressing-gown that dulls defence against many disorders.", [13308]="A radiant robe that wards off sleep and death and heals wounds.",
	[13309]="A downy gown that wards off sleep and death and heals wounds.", [13310]="A garment possessed by a powerful dragon that muffles magical attacks.", [13311]="A garment possessed by a dragon deity that muffles magical attacks.", [13312]="Curious clothing that fends off fatal spells.",
	[13313]="An unreal robe that fends off fatal spells.", [13314]="A righteous robe that fends off fatal spells.", [13315]="An unrivalled robe that fends off fatal spells.", [13316]="Clobber that once clad Bishop Kiryl.",
	[13317]="A cloak that once covered the shoulders of the sorcerer Borya.", [13318]="A stripy suit made for the merchant Taloon.", [13320]="An unadorned outfit ostensibly owned by King Trode of Trodain.", [13324]="A gown that guards against attacks that send victims to sleep.",
	[13325]="A magical vestment that spoils the effects of spells.", [13326]="A sound vestment that staunchly stands up to spells.", [13327]="A protected vestment that<1>s particularly powerful against magic.", [13328]="A godly gown that defends against the draining of magic.",
	[13329]="A consecrated costume that curbs fire- and ice-based damage.", [13390]="A Fizzle-fizzling frock that harbours the soul of an ancient sorceror.", [13391]="A Fizzle-fizzling frock that harbours the soul of an ancient sorceress.", [13490]="A past priest<1>s vital vestment used to evade magic draining.",
	[13491]="A comfortable cape worn by the Prince of Cannock.", [13500]="An unrestrictive outfit that<1>s much-loved by female martial artists.", [13501]="A virtuous vestment for female priests that stops MP being stolen.", [13502]="A gorgeous garment that<1>s great for girls on the stage.",
	[13503]="A mighty magical cloak favoured by erudite females", [13504]="A graceful gown for the more mature lady.", [13505]="Female martial artist<1>s attire that fends off fire and ice attacks.", [13506]="A nebulous number that<1>s not unknown to reflect spells.",
	[13507]="Magic-resistant regalia that would complement a queen.", [13508]="Magic-resistant regalia that exudes an empress<1>s elegance.", [13509]="Magic-resistant regalia that would be perfect for a prince.", [13510]="Magic-resistant regalia that would complement a king.",
	[13511]="Magic-resistant regalia that exudes an emperor<1>s exaltedness.", [13513]="A plain piece of clothing worn by the Princess of Moonbrooke.", [13514]="An uncomplicated cloak worn by Meena the mystic.", [13515]="A pricey piece of clothing once worn by Nera Briscoletti.",
	[13516]="Ribbon-ridden raiment made famous by the mighty Milly.", [13517]="A one-piece that was worn by Maribel.", [13518]="A delightful d<'e>collet<'e> dress donned by Jessica.", [13519]="A surprisingly stylish dress made of hard-wearing animal hide.",
	[13520]="A nice little number that brings to mind the green of young grass.", [13521]="A fancy frock that<1>s white<,> light and quite cool.", [13522]="A jazzy dress made from a jaguar<1>s hide.", [13590]="Magic-resistant regalia that would be perfect for a princess.",
	[13600]="A gob-smacking garment for female mages that fends off Fizzle.", [13601]="A flexible defensive garment for female fighters.", [13602]="Combat clobber for high-grade female gladiators.", [13603]="Protection for female paladins that guards against ungodly powers.",
	[13604]="A frilly<,> floating frock for the furtherance of fans<1> fantasies.", [13605]="Attractive attire donned by dancers.", [13606]="The sort of glamorous get-up bunny girls gad about in.", [13607]="A gasp-worthy gown for golden girls.",
	[13608]="Swimwear that<1>s somewhat unsafe to set eyes on.", [13609]="Waterwear that works well against fire and lightning attacks.", [13610]="Bold bathing gear that bravely beats back fire and lightning attacks.", [13612]="A barely believable bodice that you<1>d be brave to look at.",
	[13613]="A superior and oh-so-soft bodice made of silk.", [13614]="A beautiful bodice that makes sidestepping enemy strikes a cinch.", [13615]="A racy raiment donned by the dancer Maya.", [13616]="Get-up-and-go garb worn by Bianca Whitaker.",
	[13617]="A dress donned by Ashlynn<,> apparently.", [13618]="A fashionable fit for faerlie flamboyant females.", [13619]="A dazzling dress of Fleurette<1>s from a famous label.", [13620]="Aproned attire made for maids.",
	[13621]="A gaudy garment dearly beloved by Debora Briscoletti.", [13622]="Erinn<1>s much-beloved inn-tending outfit.", [13623]="A dress built with buxom lady bartenders in mind.", [13624]="A voluminous dress<,> perfect for hiding espionage equipment.",
	[13625]="What the bride wears at a traditional white wedding.", [13626]="Pop this on and just try not to feel the spirit of the season of goodwill!", [13627]="A piece of clothing worn by pre-modern female martial artists.", [13695]="A body-hugging one-piece worn by a heroine of Zenithia.",
	[13696]="A tantalising one-piece worn by Tsarevna Alena.", [13700]="A gob-smacking garment for male mages that fends off Fizzle.", [13701]="An enchanted ensemble for male mages that fends off Fizzle.", [13790]="Good defensive garb made of iron that covers the chest.",
	[13791]="An uninspiring piece of armour that nonetheless shelldom lets you down.", [13793]="A precious piece of protection for the chest.", [13794]="An eccentric enhancement of the tortoise shell.", [15000]="Very thick gloves that adorn the hands of all kinds of warrior.",
	[15001]="Modish mittens mainly adored by armamentalists.", [15002]="Mittens for m<^e>l<'e>e mash-ups mainly adored by armamentalists.", [15003]="Run-of-the-mill mitts made of unfancy fabric.", [15004]="Well made workwear that won<1>t wear easily.",
	[15005]="Handwear made from tanned hide.", [15007]="Wristwear once worn by a whilom martial artist.", [15008]="Cloth wrist coverings once worn by a sage of a bygone age.", [15009]="Flexible fingerwear that confounds incoming flashes of lightning.",
	[15010]="Gloves gladly worn by globetrotters.", [15013]="High-class handwear that hinders Dazzle magic and confusion.", [15014]="Graceful gloves that guard against Dazzle magic and confusion.", [15015]="A posh pair that protects against Dazzle magic and confusion.",
	[15016]="The well-worn handwear of a whilom warrior.", [15017]="Mitts made use of by female mages of a bygone age.", [15018]="Holy handwear that protected the palms of a priest of the past.", [15019]="High-class handwear worn by heroes of the thieving hierarchy.",
	[15020]="Mystical mitts made use of by a sage of distant memory.", [15021]="Mysterious mittens that impart mighty resilience to dark magic.", [15022]="Magical mittens that drive dark magic away.", [15023]="The beloved badge of a bona fide bullfighter.",
	[15024]="Fingerwear that fosters fine movement.", [15025]="Magical mitts that make those who don them deliciously dexterous.", [15026]="Mystical mitts that nurture nonpareil nimbleness.", [15027]="Divine digitwear that defies the undoable.",
	[15028]="Wondrous handwear worn by the hero of Zenithia.", [15029]="Guards for the wrists that are relics of Gothan royalty.", [15030]="Memorabilia from Maya<1>s magical performing moments.", [15031]="Alluring armlets that once rendered Meena<1>s wrists resplendent.",
	[15032]="Thick<,> weighty gloves that give a good defensive boost.", [15033]="Basic silver bangles.", [15034]="Bangles bent into shape by Bianca herself.", [15035]="Ritzy wristwear worn by the blue-haired Briscoletti bambina.",
	[15036]="Rip-roaring wristwear worn by the hard-working Carver.", [15037]="Small<,> simple bracelets that suit Milly to a tee.", [15038]="Magical mitts adored by Ashlynn.", [15039]="Super-cool gloves in a totally on-trend turquoise.",
	[15040]="Brawny bracelets brimmin<1> wiv Yangus<1>s bottle.", [15041]="Affected armwear advocated by Angelo.", [15042]="Massively masculine mittens styled by the inimitable Morrie himself.", [15043]="On-trend armwear for advanced adventurers.",
	[15045]="A one-handed glove that makes the wearer look well-hard.", [15047]="Faithful fistwear of a rich red hue.", [15048]="Gossamer-thin gloves for the purloining professional.", [15091]="Handwear made of hide that<1>s just perfect for Prince Kiefer.",
	[15092]="Fingerwear fashionable in Alefgard.", [15093]="Homespun handwear preferred by the Prince of Midenhall.", [15094]="Fashionable fingerwear autographed by the Prince of Cannock.", [15095]="Hand coverings that quietly contributed to a hero<1>s quest.",
	[15096]="Warrior<1>s gloves once worn by Ragnar McRyan.", [15097]="Winsome handwear one might find in a tsarevna<1>s wardrobe.", [15100]="Handwear whose lack of digital coverage allows for deft movement.", [15101]="Wrist guards revered by the ranks of the martial arts.",
	[15102]="Gloves instilled with the strength of legendary woman warriors.", [15103]="Good<,> strong<,> reinforced gloves worn by gladiators.", [15105]="Lightweight wonders worn by world-class wanderers.", [15106]="Handwear for handling bows<,> habitually worn by rangers.",
	[15107]="Handwear sported by some celebrated chevaliers.", [15108]="Handwear once worn habitually by honest-to-goodness heroes.", [15109]="Fingerwear favoured by female martial artists of a former age.", [15190]="Gloves that were the preferred pair of the Prince of Somnia.",
	[15200]="Wholesome handwear made of hardy hide.", [15280]="Handwear that staves off spell damage with spiritual protection.", [15281]="Tarnished and tattered handwear of obscure origins.", [15282]="Fiery fist protectors with unparalleled defensive potential.",
	[15283]="Moonlight-infused mittens with unparalleled defensive potential.", [15284]="Stormy gauntlets with unparalleled defensive potential.", [15285]="Solar smashers with unparalleled defensive potential.", [15286]="Gloves given by Greygnarl as a token of friendship.",
	[15291]="Elementary metal mitts.", [15292]="High-grade gloves once graced by the hands of a legendary hero.", [15293]="Hefty handwear made of hard steel.", [15294]="Gorgeous gloves made of gigasteel.",
	[15295]="Handwear that harbours the mystical sheen of a metal slime.", [15296]="Heavenly handwear that harbours the lustre of a liquid metal slime.", [15297]="High-class handwear harbouring the brilliance of a metal king slime.", [15298]="Magical mitts that diminish damage from magic attacks.",
	[15299]="Gloves whose saintly guardianship gives relief against magic attacks.", [16093]="Simple shorn-off slacks sold in Somnia.", [16094]="Underwear by men<,> for men.", [16095]="A loincloth made from bits of bashed-together beast hide.",
	[16100]="Loose-fitting legwear worn by woman warriors.", [16103]="Chunky chainmail legwear.", [16104]="Foot coverings for females that fit the leg up to the knee.", [16191]="Warming legwear once worn by a heroine of Zenithia.",
	[16200]="Red-tinged trousers worn by warriors.", [16202]="Long briefs for keen thiefs that allow super-swift movement.", [16203]="Made for martial artists to test their mettle in mortal combat.", [16204]="Strange slacks that seem to strengthen magical might.",
	[16205]="Super-snazzy slacks for showmen that stave off sleep.", [16206]="Trousers tailored for tussling that gladiators go mad for.", [16207]="Armamentalist<1>s attire that wears well against Fizzle magic.", [16208]="Scarlet stockings that stave off fire- and ice-based strikes.",
	[16209]="Leaf-green legwear that deflects death magic<,> poison and paralysis.", [16210]="Paralysis-preventing legwear beloved by roaming rangers.", [16211]="Enchanted chinos that make more of the wearer<1>s magical might.", [16212]="Silvery stockings that slightly stave off ice and wind attacks.",
	[16213]="Simple slacks made of standard stuff.", [16214]="A loose garment made for martial artists to work out in.", [16215]="Strange stockings that somehow seem angelic.", [16216]="Pants that put the <6>t<9> in <6>testosterone<9>.",
	[16217]="Pants that really put the <6>t<9> in <6>testosterone<9>.", [16218]="Iron contrivances that prevent knocks to the knees.", [16219]="Steel supplementary wear that prevents knocks to the knees.", [16220]="Gigasteel supplementary wear that prevents knocks to the knees.",
	[16221]="Loud legwear that helps hold off sleep and enchantment attacks.", [16222]="Strange see-through stockings.", [16223]="Martial artist<1>s attire that impedes attacks of fire and ice.", [16224]="A piece of clothing worn by pre-modern martial artists.",
	[16228]="Magic-boosting slacks worn by the sages of bygone ages.", [16229]="Protective legwear that disrupts attempts to lower defence.", [16230]="Magical legwear that disrupts attempts to lower defence.", [16231]="Steady slacks that staunchly withstand death spells.",
	[16232]="Steady slacks that stand up to sleep magic and death spells.", [16233]="Steady slacks that withstand paralysis<,> sleep and death spells.", [16234]="Super-steady slacks that stand up to all sorts of strangeness.", [16235]="Ashen attire that the Prince of Cannock put over his pins.",
	[16236]="White legwear once worn by Bishop Kiryl.", [16237]="Loose-fitting legwear once worn by the wily Torneko Taloon.", [16240]="A pair of Carver<1>s captivatingly cut shorts.", [16241]="Chalk-white trousers of Milly<1>s with a fairly free fit.",
	[16243]="Prince Kiefer<1>s close-fitting pitch-black pants.", [16244]="A puffed up pair belonging to Pickham<1>s premier pilferer.", [16245]="Multo masculine hosiery of Morrie<1>s that hugs his handsome haunches.", [16246]="Knee-high legwear for the faerlie fashion-conscious female.",
	[16248]="Stripy<,> knee-high socks that are a favourite of Fleurette<1>s.", [16251]="Legwear for lovable louts that looks a little tight.", [16252]="Spick and span scarlet legwear attributed to the Templar Angelo.", [16255]="A loose garment made for more advanced martial arts training.",
	[16256]="Given by Greygnarl as a token of friendship.", [16257]="Plain pantaloons imbued with Aquila<1>s aura.", [16258]="The uniform of an acclaimed academy.", [16259]="The bottom half of a beautifully tailored tuxedo.",
	[16260]="Santa<1>s trademark crimson trousers.", [16261]="Bloodcurdling bottoms decorated with beautifully drawn bones.", [16262]="Seafaring slacks sported by a celebrated swashbuckler.", [16263]="Casual trousers usually worn by the young <--> or the young at heart.",
	[16283]="A pair of priest<1>s tights from past times that improve magical mending.", [16286]="Spartan slacks sported by the Prince of Midenhall.", [16287]="Simple slacks sported by a hero of Alefgard.", [16288]="Bog-standard slacks supposedly sported by a legendary hero.",
	[16289]="A pair of unpretentious trousers worn by a hero of Zenithia.", [16290]="Bog-standard slacks sold in Estard.", [16291]="Cheapo chinos traded in the territory of Trodain.", [16300]="Legwear that makes much more of the wearer<1>s magical might.",
	[16301]="Sprightly slacks for a super-fast fighting frenzy.", [16302]="Tights that make a flattering fit for any lady<1>s legs.", [16303]="Swimwear that<1>s somewhat unsafe to set eyes on.", [16304]="Waterwear that works well against fire and lightning attacks.",
	[16305]="Bold bathing gear that bravely beats back fire and lightning attacks.", [16306]="The uniform of an acclaimed academy.", [16307]="A fierce<,> fiery<,> flashy and fun bright red skirt.", [16308]="A cool<,> calm<,> comfortable and classic bright blue skirt.",
	[16309]="A tweedy<,> tartan number with a certain cuteness to its cut.", [16310]="Lascivious legwear donned by the dancer Maya.", [16311]="A daringly cut denim miniskirt for the more adventurous maiden.", [16312]="These provide perfect protection when worn under a dress.",
	[16313]="These provide protection when worn under a dress.", [16316]="A classy<,> if slightly cutesy pink skirt.", [16317]="A super-trendy skirt with an air of upper-crustness to it.", [16318]="A sorcerous skirt that can fight back magical attacks.",
	[16319]="A bracing bit of womenswear that smells slightly of the sea.", [16390]="Heavy black hosiery once worn by Tsarevna Alena.", [17091]="Tough trekker<1>s wear that<1>s a trademark of Gotha.", [17092]="Comfortable footwear favoured by the Prince of Somnia.",
	[17093]="A pair of pumps popular with the people of Estard.", [17094]="Boots once worn by the brave hero of Zenithia.", [17095]="Fondly worn footwear of a fabled hero.", [17096]="A cut-price pair of pumps that are popular in Trodain.",
	[17100]="Steadfast footwear worn by warriors.", [17101]="Resolutely unshowy shoes popular with priests.", [17102]="Fast<,> flexible footwear favoured by those of the filching fraternity.", [17103]="Fine footwear that allows thieves to move quickly and quietly.",
	[17104]="Footwear made for martial artists to master their moves in.", [17105]="Bewitching pointed boots that are much-loved by mages.", [17106]="Fleet footwear that<1>s made to measure for minstrels.", [17107]="Footwear fit for only the most skilled of martial artists.",
	[17108]="Lightweight boots that allow lady warriors ease of movement.", [17109]="Funky footwear appropriate for armamentalists.", [17110]="Shoes that show off armamentalists<1> shapely shanks.", [17111]="Firm footwear that<1>s fitted with metal reinforcements.",
	[17112]="Fine footwear for sages that<1>s tailor-made for travelling.", [17113]="First-class footwear that sages find fantastic.", [17114]="Lightning-fast footwear that<1>s loved by lots of rangers.", [17115]="Rugged boots beloved by rangers for their fleet<,> firm stride.",
	[17116]="Fine footwear that makes luminaries look lovely.", [17117]="Rich red runners that suit luminaries splendidly.", [17118]="Unrefined footwear made of hide.", [17119]="Robust rubber boots that insulate against electrical attacks.",
	[17120]="Unsophisticated footwear well-suited to apprenticing Celestrians.", [17140]="Boots beloved by Erinn for their flexibility and comfort.", [17141]="Boots well-suited to Patty the pub landlady.", [17142]="Footwear fabricated for senior Celestrians.",
	[17143]="Shiny shoes with a formal feel.", [17150]="Stellar shoes that Stella swears are the way to almost anyone<1>s heart.", [17152]="Feisty footwear of Fleurette<1>s that feels delightfully devilish.", [17155]="Unrefined footwear that thugs thump around in.",
	[17158]="Sharp leather shoes with tapered toe-tips that belong to Borya.", [17159]="Shoes supposedly sported by mages of a bygone age.", [17160]="Fast<,> flexible footwear fresh from Ashlynn<1>s wardrobe.", [17163]="Kit of Kiefer<1>s that<1>s been created from high-quality hide.",
	[17164]="A pretty pretty pair of Maribel<1>s pumps.", [17165]="Shoes supposedly sported by King Trode on a clandestine quest.", [17166]="<1>Ard-wearin<1> ones an<1> twos that Yangus <1>as <1>ad fer donkey<1>s years.", [17167]="Shoes belonging to Jessica that young ladies yearn for.",
	[17168]="Boots worn by knights of the church like the amorous Angelo.", [17169]="Shoes with a style of their own that only Morrie can carry off.", [17170]="Strange shoes that aren<1>t shy of perilous places.", [17171]="Sacred shoes that aren<1>t at all shy of perilous places.",
	[17172]="A pretty pair of pumps particularly loved by the princess of Moonbrooke.", [17173]="Bishop Kiryl<1>s loose-fitting<,> functional long boots.", [17176]="Bianca<1>s favourite fleecy footwear.", [17177]="Unshowy shoes that become Nera Briscoletti brilliantly.",
	[17178]="Bulky boots that carry Carver<1>s uncompromising confidence.", [17179]="Almost unfeasibly fine footwear worn by Mistress Milly.", [17181]="Boots beloved by bygone sages.", [17182]="Fancy footwear that heals health points as its wearer wanders.",
	[17183]="Fabled footwear that heals health points as its wearer wanders.", [17184]="Formidable footwear that heals health points as its wearer wanders.", [17185]="Fantastic footwear that heals health points as its wearer wanders.", [17186]="A significantly stouter sort of safety shoe.",
	[17187]="A supremely stout set of safety shoes that define defensiveness.", [17188]="Forlorn footwear that<1>s full of misfortune.", [17189]="Footwear that fosters floods of experience.", [17191]="Long boots belonging to Tsarevna Alena that go great with her gloves.",
	[17192]="The first choice of footwear for the folks of Alefgard.", [17193]="Sturdy shoes that once protected the Prince of Midenhall<1>s pins.", [17194]="Heel-huggers for hikers that are commonplace in Cannock.", [17195]="Sturdy yet snug leather footwear.",
	[17196]="A pair of pumps perhaps pulled on by a bygone battler.", [17197]="Footwear favoured by long-forgotten martial artists.", [17198]="Footwear found on female mages of a former age.", [17199]="Sacred soles that protected the pins of past priests.",
	[17300]="A gift for gladiators that bounces a beating back at its perpetrator.", [17302]="Godly greaves that give protection to paladins<1> legs and feet.", [17303]="Given by Greygnarl as a token of friendship.", [17391]="Basic boots made of metal.",
	[17392]="Shoes with shin pads that Ragnar McRyan raves about.", [17394]="Oozy shoes imbued with the agility of a metal slime.", [17395]="Brawny boots made of a mighty metal.", [17396]="Beautiful boots made of a miraculous metal.",
	[17397]="Oozy shoes imbued with the agility of a liquid metal slime.", [17398]="Oozy shoes imbued with the agility of a metal king slime.", [17400]="Footwear that<1>s just made for mages.", [17401]="Shoes equally suited for dealing damage and dancing the night away.",
	[17402]="White winter warmers popular with priests.", [17403]="Mules fashionable among female minstrels.", [17404]="Folksy<,> yet in a fashion fashionable<,> animal-skin shoes.", [17405]="A chunky pair of pumps chiseled from a tree.",
	[17406]="Simple slip-ons that slip on simply.", [17407]="A slightly slicker style of clogs that are good for going out in.", [17408]="Fancy but not-so-functional female footwear.", [17409]="Even higher heels that lengthen the lines of ladies<1> legs.",
	[17410]="Sky-high heels fit for the feet of queens.", [17411]="Ferrous footwear that<,> though heavy<,> complements defence.", [17412]="Fabulous flip-flops that foster magical might.", [17413]="Shiny white shoes that beautify the feet of brides everywhere.",
	[17414]="Strange strappy shoes that magnify max. MP and restore it too.", [17415]="Sacred strappy shoes that magnify max. MP and restore it too.", [17416]="Special strappy shoes that magnify max. MP and restore it too.", [17417]="Superlative strappy shoes that magnify max. MP and restore it too.",
	[17419]="Torneko Taloon<1>s treasured treaders.", [17420]="Maya<1>s charming chappals with attached anklets.", [17421]="Choice chappals befitting Meena<1>s demeanour.", [18000]="A band that bolsters brawn when worn.",
	[18001]="A mark that magnifies muscle and musters fighting might.", [18002]="A jewel that jacks up attack power when worn.", [18003]="An accessory that accentuates attack power when worn.", [18004]="A pure gold piece of armwear that artfully enhances defence.",
	[18005]="Jaunty jewellery with a slimy slant.", [18006]="A warrior<1>s ward made of a wyrm<1>s scale.", [18007]="A beautiful<,> pure gold band that artfully enhances defence.", [18008]="A sparkling stone that strengthens defence when worn.",
	[18009]="A fun and fluffy fashion item.", [18010]="A jolly gem with a rose colour.", [18011]="A toff<1>s tie that<1>s sure to advance its wearer<1>s vanity.", [18012]="A craftsman<1>s companion that does wonders for its wearer<1>s deftness.",
	[18013]="A magical accoutrement that accentuates agility.", [18014]="Awesome armwear that makes its wearer insanely agile.", [18015]="A beautiful band that boosts max. MP and magical might.", [18016]="A holy helping hand that slightly heightens magical mending.",
	[18017]="A string of beads that boosts max. MP and magical mending.", [18018]="A jewel that jacks up its wearer<1>s magical might a little.", [18019]="An unusual accessory that enhances its wearer<1>s magical might.", [18020]="An enchanted extra that heals its wearer<1>s wounds in battle.",
	[18021]="An enchanted armband that boosts max. MP by thirty.", [18022]="A kingly coat-of-arms that increases magical might and mending.", [18023]="A righteous ring that restores a modicum of MP when used.", [18024]="A ring that resists the ravages of death magic when worn.",
	[18025]="A ring that resists Dazzle-like magic when donned.", [18026]="A ring that raises resilience to poison attacks when worn.", [18027]="A ring that provides protection against paralysis when worn.", [18028]="A ring that resists sleep attacks when worn.",
	[18029]="A ring that confounds confusion attacks when worn.", [18030]="A brilliant band that resists a whole range of undesirable effects.", [18031]="A satanic stick-on design with an ominous odour about it.", [18032]="An unpleasant piece of jewellery with an ominous odour about it.",
	[18033]="A talisman that turns aside tons of undesirable effects.", [18034]="A rejuvenating ring that heals health points with every step.", [18035]="A blessed band that brings back MP with every step.", [18038]="Unnatural neckwear with an ominous odour about it.",
	[18039]="A necklace that negates all sorts of spells that lower abilities.", [18040]="A jewel that fascinates those who feast their eyes on it.", [18043]="A warrior<1>s award that ups its wearer<1>s attack power.", [18044]="A priest<1>s prize that pumps up magical mending.",
	[18045]="A mage<1>s medal that maximises magical might.", [18046]="A martial artist<1>s medal that improves its wearer<1>s agility.", [18047]="A thief<1>s award that enhances the chances of successfully stealing.", [18048]="A minstrel<1>s medal that allows you to equip the opposite sex<1>s stuff.",
	[18049]="A gladiator<1>s medal that cranks up the chance of a critical hit.", [18050]="A paladin<1>s decoration that drums up defence.", [18051]="An armamentalist<1>s medal that maxes the chance of a coup de gr<^a>ce.", [18052]="A reward for rangers that upgrades deftness when donned.",
	[18053]="A sage<1>s medal that magnifies max. MP.", [18054]="An accolade for luminaries that seriously supplements style.", [18055]="Symbol of the sacred bond between two beings.", [19050]="A gnat of a knife that might be used for chopping up veggies.",
	[19051]="A nifty knife made of a softish alloy.", [19052]="A bitsy blade bathed in holy light that zealously zaps zombies.", [19053]="A knife that<1>s known to paralyse its prey part of the time.", [19054]="A keen knife that paralyses its prey part of the time.",
	[19055]="An unnerving knife that paralyses its prey part of the time.", [19057]="A prickly pin that can fell a foe with a single stab if correctly aimed.", [19058]="A killer cutter that in the right hands can fell a foe in a single strike.", [19059]="A nippy knife that emits icicles if used as an item in battle.",
	[19060]="A snowy stabber that emits icicles if used as an item in battle.", [19061]="A nefarious knife for nimble-fingered ne<1>er-do-wells.", [19062]="A stout<,> serrated blade that weakens enemies<1> weapons.", [19063]="A sinister serrated blade that weakens enemies<1> weapons.",
	[19064]="A divine earring that delivers a double attack.", [19065]="A famed dagger for a heralded hero.", [19066]="A fiery dagger for a triumphant trouper.", [19067]="A magical blade that can cause critical damage if it hits the spot.",
	[19068]="A mysterious knife that imparts unbeatable briskness.", [19069]="A legendary knife that imparts unbeatable briskness.", [19070]="A mighty knife that imparts unbeatable briskness.", [19071]="A matchless knife that imparts unbeatable briskness.",
	[19150]="A brutally basic bludgeon built of sturdy oak.", [19151]="A colossal cudgel<,> reportedly once wielded by giants.", [19152]="A heavyweight hammer with a head of iron.", [19153]="A steel-headed hammer manufactured for m<^e>l<'e>es!",
	[19154]="An even more formidable form of the war hammer.", [19155]="A sizeable spanner that can sock it to monsters of the machine family.", [19156]="A powerful pounder that harbours the essence of the earth<1>s energy.", [19157]="An even more ruinous revision of the terra tamper.",
	[19158]="An awesome overhaul of the terra firmer.", [19159]="A favourite of foul demons<,> it has dazzling destructive clout.", [19160]="A tricky tool to tame<,> but one that can finish foes in one fell swoop.", [19161]="A big basher that mashes monsters of material make-up.",
	[19162]="A huge hammer that easily erases monsters of material make-up.", [19163]="A huge hammer that weighs heavy on the heads of those it hits.", [19164]="A mammoth mallet that weighs heavy on the heads of those it hits.", [19165]="A pounder of imposing power that may rend the very ground asunder.",
	[19166]="A pounder of prodigious power that could crack continents in two.", [19167]="A pounder of stupendous power that could crush the moon.", [19168]="A pounder of peerless power<,> whose cosmic clout could crack a star.", [20000]="A biting blade favoured by battle-scarred brigands.",
	[20001]="A sizeable sabre supremely suited to swindling sorts.", [20002]="A fine-edged blade wielded by famous female fighters.", [20003]="A delightfully designed<,> slim-bladed sword.", [20004]="A commonplace cutter made of copper.",
	[20005]="A simple sword supplied to low-ranking castle custodians.", [20006]="A regular<,> wrought iron sword.", [20007]="A fully fledged fighting blade forged from steel.", [20008]="A refined steel blade of rip-roaring quality.",
	[20009]="A slender sword that would suit a seriously skilled soldier.", [20010]="A sacred sword that flings flames if used as an item in battle.", [20011]="A wondrous weapon that flings flames if used as an item in battle.", [20012]="A heralded hacker made from hard platinum.",
	[20013]="A mighty masher that<1>s merciless even against the scales of dragons.", [20014]="An even deadlier descendant of the dragonsbane.", [20015]="A sword so fast<,> it can slice an enemy twice in a single strike.", [20016]="A fiercer form of the falcon blade.",
	[20017]="A wonderful weapon that heals the holder<1>s HP with every blow.", [20018]="A more mighty model of the miracle sword.", [20019]="A hot blade that spits forth flames if used as an item in battle.", [20020]="A fiery blade that spits forth flames if used as an item in battle.",
	[20021]="A hard blade that carries incredible clout.", [20022]="An extremely hard blade that carries incredible clout.", [20023]="An incredibly hard blade that carries incredible clout.", [20024]="A shabby and unshiny sword whose origins are obscure.",
	[20025]="A well-known weapon once wielded by a legendary lionheart.", [20026]="A legendary blade that dulls the defence of the foes it fights.", [20027]="An unbelievable blade that dulls the defence of the foes it fights.", [20028]="An unbeatable blade that dulls the defence of the foes it fights.",
	[20029]="An almighty blade that dulls the defence of the foes it fights.", [20100]="A flamboyant fan made from peacock feathers.", [20101]="An inflexible fan<,> heavy due to having slats made of metal.", [20102]="A strong fan with slats made of steel.",
	[20103]="A ferocious fan with slats made of strengthened steel.", [20104]="A fighter<1>s fan<,> created for combat.", [20105]="A fan that fires air at foes if used as an item in battle.", [20106]="A fan that whips a wild whirlwind at foes if used as an item in battle.",
	[20107]="A fan that fosters the force of the earth.", [20108]="An earthy fan furnished with the mark of a mythical beast.", [20109]="A fan that fosters the force of ice.", [20110]="A watery fan furnished with the mark of a mythical beast.",
	[20111]="A fan that fosters the force of fire.", [20112]="A fiery fan furnished with the mark of a mythical beast.", [20113]="A fan that fosters the force of lightning.", [20114]="A thundery fan furnished with the mark of a mythical beast.",
	[20115]="An exquisite fan resplendent with a sweeping starscape.", [20116]="A magnificent fan made more so by a mystical moonscape.", [20117]="A sainted<,> painted fan inscribed with a sumptuous sunny scene.", [20118]="A fan that can fix a friend<1>s wounds if used as an item in battle.",
	[20119]="A fabled fan with tons of untold powers.", [20120]="A fabled fan that ups the occurrence of coups de gr<^a>ce.", [20121]="A mighty fan that ups the occurrence of coups de gr<^a>ce.", [20122]="An unbeatable battle fan that ups the occurrence of coups de gr<^a>ce.",
	[20123]="An unfailing battle fan that ups the occurrence of coups de gr<^a>ce.", [20124]="The beautiful bunch of flowers borne proudly by every bride.", [20200]="A huge hacker created exclusively for combat.", [20201]="A large axe loved by lumberjacks that can fell any plantlike foe.",
	[20202]="A sizeable<,> strong and somewhat weighty steel axe.", [20203]="A horrendously heavy hacker made by souping up a steel axe.", [20204]="A battle-axe with a blunt edge made from a malleable metal.", [20205]="A mysterious axe that may make those it minces a mite confused.",
	[20206]="A sharpened reshaping of the moon axe.", [20207]="A cracking cleaver<,> even more imperial than the king axe.", [20208]="An enormous axe of frankly fearsome force.", [20209]="A revolutionary rustproof refinement of the headsman<1>s axe.",
	[20210]="An ice-based axe with an interesting shape.", [20211]="An impressive ice-based axe with an interesting shape.", [20212]="A heinous hatchet that can hew through any material monster.", [20213]="A tip-top tomahawk that takes tension from its targets.",
	[20214]="A mighty massacrer that takes tension from its targets.", [20215]="An unchallenged chopper that takes tension from its targets.", [20216]="An almighty cosmic cleaver that takes tension from its targets.", [20291]="A splendid splitter sporting runes that harbour great magic.",
	[20293]="A meaty metal axe.", [20300]="A whip made of hide that can hit a whole heap of enemies at once.", [20301]="A thorny thong that can hit a whole heap of enemies at once.", [20302]="A combat whip that can hit a whole heap of enemies at once.",
	[20303]="A scaly whip that can hit a whole heap of enemies at once.", [20304]="A sturdy whip made from the skin of a large snake.", [20305]="A stronger and more severe version of the serpentine whip.", [20306]="A whip of linked loops that can lash a whole line of enemies at once.",
	[20307]="A strong whip woven from ferrous fibres.", [20308]="A wicked whip woven from steel wires with spiny protrusions.", [20309]="A fortified form of the spiked steel whip.", [20310]="A terribly tough whip designed to duplicate a dragon<1>s tail.",
	[20311]="A warped whip that whiffs worryingly of wickedness.", [20312]="A woeful whip that whiffs worryingly of wickedness.", [20313]="A ferocious whip that lashes foes like a menacing monsoon.", [20314]="A ladylike lash fondly flaunted by a famous queen.",
	[20315]="A ladylike lash fondly flaunted by an empress of antiquity.", [20316]="A ladylike lash fondly flaunted by a heavenly hand.", [20317]="A well-known whip derived from a dim and distant city of doom.", [20318]="A fantastic flail that can attack all foes at once.",
	[20319]="An even more vicious version of the Gringham whip.", [20320]="A reformed and remodelled revision of the Gringham whip.", [20321]="A greatly improved Gringham whip that packs a serious punch.", [20400]="A stick that seriously steps up magical might.",
	[20401]="Protects an ally from breath attacks if used as an item in battle.", [20402]="A weird wand with a somewhat flute-like form.", [20403]="A staff whittled from the wood of an old oak tree.", [20404]="A wand that whisks up whirling winds when used as an item in battle.",
	[20405]="A stick that whips foes with wild winds if used as an item in battle.", [20406]="A staff that stops your party<1>s paralysis if used as an item in battle.", [20407]="A staff that throws thunderbolts if used as an item in battle.", [20408]="A staff swirling with the strength of the sea. Feared by fishy foes.",
	[20409]="A rod of the ocean gods that smacks seaborne foes with fierce force.", [20410]="A stick that steps up magical might.", [20411]="A miraculous staff that sucks masses of MP from the enemy.", [20412]="Hereditary heirloom of the heinous heads of the Gittish Empire.",
	[20413]="A souped-up sort of sage<1>s staff<,> with mightier magic.", [20414]="A wand that fries foes with dragonfire if used as an item in battle.", [20415]="A radiant staff that stamps out magic effects when used as an item in battle.", [20416]="A holy staff that stamps out magic effects when used as an item in battle.",
	[20417]="A divine staff that stamps out magic effects when used as an item in battle.", [20418]="An unsurpassed staff that stamps out magic effects when used as an item in battle.", [20419]="A strange staff that once sealed away some faerie sisters.", [20493]="A magical staff that sucks masses of MP from the enemy.",
	[20494]="A staff that throws fire at foes if used as an item in battle.", [20495]="A staff that summons savage lightning if used as an item in battle.", [20496]="A staff that lobs lava if used as an item in battle.", [20500]="A simple spear fashioned from fresh bamboo.",
	[20501]="A super-sized spear suffused with a sacred light that zaps zombies.", [20502]="A sizeable spear with blades stemming from the sides of the spike.", [20503]="A spear made of iron for everyday action.", [20504]="A basic spear with a steel spike.",
	[20505]="A souped-up steel lance with superior penetrative potential.", [20506]="A long and leaden javelin.", [20507]="A holy lance blessed by the Almighty that zealously zaps zombies.", [20508]="A fair-sized fork that makes short work of aquatic enemies.",
	[20509]="A three-pronged fork that facilitates the filleting of fishy foes.", [20510]="A spear said to once have been used by an emperor of the ocean.", [20511]="A spear that sends sand to blind baddies if used as an item in battle.", [20512]="A whopper of a weapon with elements of both a spear and a battle-axe.",
	[20513]="A magical spear within which lingers the power of lightning.", [20514]="A spear said to have served a god of thunder in bygone days.", [20515]="A spear that can floor a foe with a single well-sighted strike.", [20516]="A spear that serves to restore its bearer<1>s HP with every strike.",
	[20517]="A supreme spear packed with the power of metal slimes.", [20518]="A supreme spear packed with the power of liquid metal slimes.", [20519]="A supreme spear packed with the power of metal king slimes.", [20520]="A lavish lance that can shoot through any shield.",
	[20521]="An alarming lance that can shoot through any shield.", [20522]="A lethal lance that can shoot through any shield.", [20523]="An unrivalled lance that can shoot through any shield.", [20600]="A long bamboo pole <6>borrowed<9> from a boring old clothes horse.",
	[20601]="A sturdy stick for lugging heavy luggage.", [20602]="A lengthy stick carved from the bough of a sturdy old oak.", [20603]="A metal rod that can really make those on its receiving end reel.", [20604]="A rock-solid rod made from strengthened steel.",
	[20605]="An even harder hitter than the steel bar.", [20606]="A quarterstaff of quite worrying width.", [20607]="A curious cudgel that sometimes sends the enemy to sleep.", [20608]="A supernatural stick that sometimes sends the enemy to sleep.",
	[20609]="A well-balanced weapon that packs one heck of a whack!", [20610]="A cudgel commonly employed by competent combatants.", [20611]="A strong staff that rains down blows like a sudden storm.", [20612]="A stormy stick that hails down blows like it<1>s monsoon season.",
	[20613]="A stupendous staff that twirls like a tornado and hits like a hurricane.", [20614]="A beastly bludgeon with a spiky end.", [20615]="A scary stick said to harbour the might of dragons.", [20616]="A spine-chilling stick said to harbour the might of a dragon deity.",
	[20617]="A stonking stick made of a super-rare substance.", [20618]="A supernatural stick that solidifies itself to smack foes silly.", [20619]="A celebrated stick that solidifies itself to smack foes silly.", [20620]="An unsurpassed stick that solidifies itself to smack foes silly.",
	[20621]="A supreme stick that solidifies itself to smack foes silly.", [20700]="A thrown weapon that can strike all enemies with a single sling.", [20701]="A slightly superior version of the basic boomerang.", [20702]="A metal boomerang with a bladed bite.",
	[20703]="A metal boomerang of shocking sharpness.", [20704]="A dream <1>rang that<1>s a doddle to dispatch and deals decent damage.", [20705]="A steel-bladed boomerang with an acute edge.", [20706]="A razor-sharp <1>rang renowned for razing the rabble to the ground.",
	[20707]="An uncommonly keen kylie that carves the way to conquest.", [20708]="A boomerang based on a picture of a pair of soaring swallows.", [20709]="A kylie whose construction is modelled on the king of hawks.", [20710]="A throwing stick suffused with the strength of the wind.",
	[20711]="A throwing stick so staggeringly strong<,> it can whip up a whirlwind.", [20712]="A boomerang bearing a fiery force.", [20713]="A boomerang blessed with the power of billowing flames.", [20714]="A bizarre star-shaped boomerang brimming with magic.",
	[20715]="A curious kylie that<1>s a pinch more powerful than the pentarang.", [20716]="A rip-roaring <1>rang that flattens foes like a meteorite.", [20717]="A rip-roaring <1>rang that flattens foes like an avalanche of asteroids.", [20718]="A rip-roaring <1>rang that ploughs through its prey like a supernova.",
	[20719]="A rip-roaring <1>rang glorified for its galaxy-gashing get-up-and-go.", [20800]="Super-simple scratchers made from sharpened stones.", [20801]="Metal menaces worn by many warriors.", [20802]="Tough talons made from strengthened steel.",
	[20803]="Super sharp metal scratchers forged from shrewdly selected steel.", [20804]="Consecrated claws capable of cutting even formless foes.", [20805]="Hooked claws full of exotic foreign fascination.", [20806]="Talons that tear through their target swift as a swooping bird.",
	[20807]="Talons that tear through their target like a hungry hawk.", [20808]="Talons that tear through their target like a crazed kite.", [20809]="Drill-like devices that can sink holes into steel.", [20810]="Heavy-duty drill-like devices that can cut holes through steel.",
	[20811]="Rock-hard<,> razor-sharp rippers like the talons of a dragon.", [20812]="Claws that fling forth fire if used as an item in battle.", [20813]="Terrifying toughened talons made from fire claws.", [20814]="Large toxic talons<,> hooked like those of a hellish demon.",
	[20815]="Enormous toxic talons<,> hooked like those of a hellish demon lord.", [20816]="Razor-sharp rippers resembling those of a mythical magical beast.", [20817]="Sharp shredders said to resemble those of the king of beasts.", [20818]="Godly talons crafted from orichalcum.",
	[20819]="Claws that can carve up dragon scales as easily as cutting cake.", [20820]="Claws that whip through dragon scales as if they were water.", [20821]="Claws that cut dragon scales as quickly as waving goodbye.", [20822]="The claws to end all claws. Destroy dragons with the flick of a wrist!",
	[20900]="A hunter<1>s handbow used for downing downy prey.", [20901]="A beginner<1>s bow that<1>s easy on the purse and the pectorals.", [20902]="A big bow that<1>s a bit more of a chore to draw.", [20903]="A strong bow that deals a strong blow and is well-loved by warriors.",
	[20904]="A discombobulating bow that befuddles the foes its arrows find.", [20905]="A blessed bow that heals all allies if used as an item in battle.", [20906]="A hunter<1>s handbow that finds even faraway flying prey.", [20907]="A bow imbued with the power of the wind.",
	[20908]="A bow imbued with the power of a whirlwind.", [20909]="A bow imbued with the power of a tempest.", [20910]="A big bow built to fire brawny bolts.", [20911]="A bewitched bow of brutal power.",
	[20912]="An enhanced edition of the purblind bow.", [20913]="A baleful bow that<,> though pretty powerful<,> is cripplingly cursed.", [20914]="A bow among bows that boasts fantastic firepower.", [20915]="A bow brimming with the holy power of heavenly messengers.",
	[20916]="A breathtaking bow made by bolstering the angel<1>s bow.", [20917]="A blistering bow made by bolstering the archangel<1>s bow.", [20918]="An unbeatable bow at the very peak of perfection.", [21000]="A shield for soldiers offering some immunity to magic attacks.",
	[21001]="A shield made from the shell of a tortoise.", [21002]="A charming piece of armour with a feline design.", [21003]="A pretty but practical piece of protection with a purrculiar design.", [21004]="A lightweight shield<,> easily used and ideal for learners.",
	[21005]="Protection made of platinum that fares well against fire attacks.", [21006]="A shield that baffles breath attacks if used as an item in battle.", [21007]="A sanctified shield that<1>s stout in the face of magical attacks.", [21008]="A sanctified shield that<1>s certain to stave off magic attacks.",
	[21009]="A corroded and conked-out shield of obscure origins.", [21010]="A supernatural shield that brings a magical barrier into being.", [21011]="A splendid shield that brings a magical barrier into being.", [21012]="A supreme shield that brings a magical barrier into being.",
	[21013]="A superlative shield that brings a magical barrier into being.", [21014]="A slime-shaped shield that just oozes class.", [21091]="A sizeable shield bashed out of bronze.", [21092]="A steadfast shield made of iron.",
	[21093]="A shield of steel that can stave off some fire- and ice-based strife.", [21095]="A strengthened steel shield that can dampen fire and ice damage.", [21190]="A shield made with metal slimes that guards against magical attacks.", [21191]="A shield purportedly sported by the original legendary hero himself.",
	[21192]="A shield made by sticking sturdy scales together.", [21193]="A shield made with liquid metal slimes that guards against magical attacks.", [21194]="A shield made with metal king slimes that guards against magical attacks.", [21200]="A sacred shield employed to protect against unholy assaults.",
	[21280]="A mystical shield that stands strong against offensive spells.", [21281]="A mystical shield that holds fast against even fierce offensive spells.", [21282]="A big shield that bolsters its bearer<1>s HP if used in battle.", [21290]="A mystical shield that provides protection against offensive spells.",
	[21291]="An unsophisticated shield of leather over lumber.", [21292]="A shield that bolsters its bearer<1>s HP if used as an item in battle.", [21294]="A shiny shield that shuns MP absorption<,> fire and thunder.", [21295]="A sacred shield that shines with a white light.",
	[21296]="A super-simple shield shaped by sticking a strap on a saucepan lid.", [21297]="A salver made of silver that makes a stopgap shield.", [21298]="A gorgeous gold dish that makes a good stopgap shield.", [21299]="A prize platinum plate that makes a perfect stopgap shield.",
	[21390]="A shield that builds a fireproof barrier if used as an item in battle.", [21391]="A shield of dragon<1>s scales that stifles fire- and ice-based strikes.", [21392]="A shield that casts a Sap spell if used as an item in battle.", [21393]="A sinister shield that emanates an eerie aura.",
	[21394]="A super-sized shield that can stave off fire- and ice-based strikes.", [21395]="A shield that builds an iceproof barrier if used as an item in battle.", [21396]="A jet-black shield that guards against fire- and ice-based attacks.", [21397]="A shield that casts a Sap spell if used as an item in battle.",
	[22000]="A helpful herb that restores around 30 HP to a single ally.", [22001]="A helpful herb that restores around 40 HP to a single ally.", [22002]="A helpful herb that restores around 90 HP to a single ally.", [22003]="A helpful herb that restores around 60 HP to a single ally.",
	[22004]="A helpful herb that purges the scourge of poison from a single ally.", [22005]="A herb that heals poison and restores around 40 HP to a single ally.", [22006]="A herb that heals poison and restores around 90 HP to a single ally.", [22007]="An antidote to paralysis that unfreezes an ally.",
	[22008]="An antidote to paralysis for a single ally that also adds around 60 HP.", [22009]="An antidote to paralysis for a single ally that also adds around 90 HP.", [22010]="A cure for confusion that concentrates on a single ally.", [22011]="A remedy that removes poison and paralysis and restores around 90 HP.",
	[22012]="A remedy that removes all manner of ills and restores around 90 HP.", [22013]="Rare foliage that can resurrect a single written-off ally.", [22014]="Divine drops that bring the whole party back to full health.", [22015]="An enchanted elixir that restores around 30 MP to a single ally.",
	[22016]="An enchanted elixir that restores around 90 MP to a single ally.", [22017]="An enchanted elixir that totally tops up a single ally<1>s MP.", [22018]="A righteous repellent that keeps weaker monsters away.", [22019]="A tool that can teleport people to places they<1>ve been before.",
	[22020]="A potion that sends a single enemy into a state of confusion.", [22021]="Poisonous powder that puts a single enemy into a state of paralysis.", [22022]="A cloying cobweb that slows the enemy to a snail<1>s pace.", [22023]="A serious sedative that sends a single group of enemies to sleep.",
	[22024]="A powerful pick-me-up that can stir a single ally from sleep.", [22025]="A cracker that frightens foes with a fearsome bang.", [22026]="An assortment of appetising eats full of festive feeling.", [22027]="A succulent and sweet show of affection from a sweetheart.",
	[22028]="An especially sugary show of affection from a sweetheart.", [22029]="A tasty tit-for-tat treat from an avid admirer.", [22030]="A truly tempting bit of tucker from an avid admirer.", [22031]="A succulent sweet prepared for the festive season.",
	[22032]="A gateau that anyone would be glad to get on their birthday.", [22033]="An explosive bit of boulder that deals damage to all foes.", [22034]="Peculiar plumage with the power to send people back home.", [22035]="A rock that restores everyone<1>s HP when used in battle.",
	[22036]="A coin with no practical use<,> which will fetch a pretty penny if sold.", [22037]="A coin with no practical use<,> which will fetch a pretty penny if sold.", [22038]="A coin with no practical use<,> which will fetch a pretty penny if sold.", [22039]="A mysterious medal that someone somewhere supposedly collects.",
	[22041]="A bewitching bloom that boosts a single ally<1>s charm a bit.", [22042]="A key capable of opening ordinary treasure chests.", [22043]="A key capable of opening locks protected by magic seals.", [22044]="A key capable of opening any lock you<1>d care to mention.",
	[22045]="A seed that slightly supplements a single ally<1>s maximum health.", [22046]="A seed that slightly supplements a single ally<1>s maximum MP.", [22047]="A seed that steps up a single ally<1>s strength slightly.", [22048]="A seed that steps up a single ally<1>s deftness a dash.",
	[22049]="A seed that slightly supplements a single ally<1>s agility.", [22050]="A seed that steps up a single ally<1>s defensive skills slightly.", [22051]="A seed that steps up a single ally<1>s magical might slightly.", [22052]="A seed that steps up a single ally<1>s magical mending slightly.",
	[22053]="A seed that slightly supplements a single ally<1>s skill points.", [22070]="Nothing more than normal nails. Alchemise <1>em!", [22071]="Rock containing an enormous amount of iron. Alchemise it!", [22072]="Rock containing a high proportion of platinum. Alchemise it!",
	[22073]="Rock containing a massive amount of mythril. Alchemise it!", [22074]="A lump of mysterious metal that<1>s drastically dense. Alchemise it!", [22075]="A piece of pure gold that<1>s heart-warmingly heavy. Alchemise it!", [22076]="A highly prized mineral of magnificent hardness. Alchemise it!",
	[22077]="A fire so fantastically fierce it can melt metal. Alchemise it!", [22078]="Fragrant fallout from a farmyard favourite. Alchemise it!", [22079]="An equine extra that exudes a pungent perfume. Alchemise it!", [22080]="Abrasive ash that cleans off curses. Alchemise it!",
	[22081]="A pebble possessed by a departed soul. Alchemise it!", [22082]="A protective pebble possessed by a phantom spirit. Alchemise it!", [22083]="The big black wing of a big black bat. Alchemise it!", [22084]="A feather from the white wings of a heavenly being. Alchemise it!",
	[22085]="Heavy hide taken from a brutal beast. Alchemise it!", [22086]="A hard horn taken from a brutal beast. Alchemise it!", [22087]="A gooey gumdrop shaped like a lovely little slime. Alchemise it!", [22088]="The charming wing of a fluttering thing. Alchemise it!",
	[22089]="A peculiar powder that purring pets apparently prefer. Alchemise it!", [22090]="Gentle grit that<1>s perfect for polishing. Alchemise it!", [22091]="A mysteriously marvellous-looking mushroom. Alchemise it!", [22092]="A funny fungus in the form of a fist. Alchemise it!",
	[22093]="A pyroclastic rock possessing the power of fire. Alchemise it!", [22094]="Wondrous water of perfect purity. Alchemise it!", [22095]="A plume plucked from a great big bird. Alchemise it!", [22096]="A mass of mud with magical characteristics. Alchemise it!",
	[22097]="A captivating crystal with cryogenic powers. Alchemise it!", [22098]="A chunk of rock charged with electrical energy. Alchemise it!", [22099]="Coal-black cloth cloaked in impenetrable darkness. Alchemise it!", [22100]="A sacred stone alive with the might of light. Alchemise it!",
	[22101]="A substance stripped from the shell of a tortoise. Alchemise it!", [22102]="The greasy excretion of an enormous amphibian. Alchemise it!", [22103]="A fluffy fleece of ovine origins. Alchemise it!", [22104]="The sloughed-off skin of a slithering serpent. Alchemise it!",
	[22105]="Dangerous dirt that<1>s totally toxic. Alchemise it!", [22106]="An unpolished precious stone with a rusty lustre. Alchemise it!", [22107]="A retroactive rock that might undo the effects of alchemy. Alchemise it!", [22108]="Mysterious string within which water flows. Alchemise it!",
	[22109]="Incredible liquid infused with an angelic essence. Alchemise it!", [22110]="A fragment formed from some heavenly fallout. Alchemise it!", [22111]="A special stone that encourages evolution. Alchemise it!", [22112]="A stone said to hold the secret of restoring life. Alchemise it!",
	[22113]="A resplendent rock that reflects light like a mirror. Alchemise it!", [22114]="A radiant rock that sizzles with solar heat. Alchemise it!", [22115]="A rock that<1>s just right for setting off sparks. Alchemise it!", [22116]="A jinxed gem that calls cured curses back on its bearer. Alchemise it!",
	[22117]="A plant that<1>s so slippery it<1>s problematic to pick up. Alchemise it!", [22118]="A peculiar plant with a soothing scent when burned. Alchemise it!", [22119]="A peculiar plant with an untrustworthy air. Alchemise it!", [22120]="A cute<,> colourless keepsake from the coast. Alchemise it!",
	[22121]="A stunning souvenir from the sea. Alchemise it!", [22122]="A vividly verdant piece of vegetation. Alchemise it!", [22123]="An extract composed of concentrated combat capabilities. Alchemise it!", [22124]="An extract composed of the vigorous verve for victory. Alchemise it!",
	[22129]="A legendary tool allegedly able to crack any rock.", [22131]="An old key found at the bottom of a grotto.", [22132]="Wondrous water from Angel Falls.", [22141]="The sweet<,> fragrant essence of a flower in bloom. Alchemise it!",
	[22142]="Queer concoction that confers a sweet singing voice. Alchemise it!", [22143]="A soiled dressing much-loved by mummies. Alchemise it!", [22144]="Colourful cloth that glows like a rainbow. Alchemise it!", [22158]="A precious piece of jewellery lost by an old lady.",
	[22159]="A crystallised mass of mortal gratitude.", [22160]="An award given to inncredible inntertainers.", [22162]="A queer key that opens the Quarantomb.", [22164]="A magical plant from Gerzuun that drives out demons.",
	[22165]="The necklace Serena was so desperately searching for.", [22166]="An irradiant item that allegedly opens the way through the Wyrmward.", [22167]="A bracing brew that Greygnarl likes to guzzle.", [22168]="An emblem once proudly possessed by a lieutenant of the Empire.",
	[22169]="A golden fruit of the Great World Tree<,> Yggdrasil.", [22170]="A memento of the firm friendship between Patty and Phoebe.", [22171]="A possibly deadly potion that banishes bad dreams.", [22172]="A list of particulars about persons staying at Erinn<1>s inn.",
	[22173]="A meticulous treatise on the terrible Gittish Empire.", [22174]="A golden mark which only a monarch may make use of.", [22175]="A magical herb said to help those who are unhappy.", [22176]="A card for collecting stamps from ex-inmates of the Gortress.",
	[22177]="A certificate to show competence in handling the Starflight Express.", [22178]="Fresh foliage from the sacred tree on Pluvi Isle.", [22179]="A Stella special that<1>s supposed to stop any illness.", [22180]="Cracking cookies that shine brilliantly<,> both in looks and taste.",
	[22181]="A giant gem that gleams gloriously.", [22182]="A peerless precious stone of profound blue.", [22183]="A teardrop shed by noble Nodoph.", [22184]="A dreamlike gem that helps the hopes of heavenly defenders.",
	[22185]="Sizeable stash stolen by a monster.", [22186]="A strange stone that stores the light of the moon.", [22187]="Decorative down of the hocus chimaera that<1>s loved by the ladies.", [22188]="A desert delicacy that works wonders with the skin.",
	[22189]="A compact cutter used by Madame Couteau for creating fine cuisine.", [22190]="A stick with a bit of a bend that<1>s excellent for easing itchy backs.", [22191]="A fearsome fang prised from a power hammer.", [22192]="A meticulously made miniature hand-mirror.",
	[22193]="An axe that was carried off by the treevil it got stuck in.", [22194]="The ridged rear plumage of a robo-robin.", [22195]="A polar plume that chucks out one heck of a chill.", [22196]="A gooey gunk that<1>s tricky to take hold of.",
	[22197]="A mark o<1> Marco having travelled to Bloomingdale.", [22198]="A mark o<1> Marco having travelled to Gleeba.", [22199]="A mark o<1> Marco having travelled to Angel Falls.", [22200]="A mark o<1> Marco having travelled to Coffinwell.",
	[22201]="A mark o<1> Marco having travelled to Snowberia.", [22202]="A simmering lump of freshly foraged lava.", [22203]="A secret scripture about the art of staffcraft.", [22204]="A consignment from Catwright<,> the tip-top whipsmith.",
	[22205]="A high-level scroll about boomeranging.", [22206]="An intermediate scroll about boomeranging.", [22207]="A basic scroll about boomeranging.", [22208]="A knitted muffler that<1>s made to measure for a teeny sanguini.",
	[22209]="A knitted muffler that<1>s made to measure for a pink sanguini.", [22210]="A knitted muffler that<1>s made to measure for a genie sanguini.", [22211]="A meal made with love and many<,> many mushrooms.", [22212]="A wrinkled and rather grubby piece of paper.",
	[22213]="A fashionable flower that<1>s highly sought-after by slimes.", [22214]="A message meant for the boy Bryson from Porth Llaffan.", [22216]="A large lizard with a beard more than a metre long.", [22217]="An examination paper that reads<,> <6>...0%...<9>",
	[22218]="An examination paper that reads<,> <6>...Lion...<9>", [22219]="An examination paper that reads<,> <6>...el 10...<9>", [22220]="A blade that belonged to a battler who was beaten by a beast.", [22221]="A care package from Walter<1>s dear old Ma.",
	[22222]="A little girl<1>s doll beloved by Batkhaan.", [22223]="A piece of paper with a print of a magmalice<1>s paw.", [22224]="A piece of paper with a print of a mega moai<1>s massive frame.", [22225]="A keepsake left behind by Anabella.",
	[22226]="A mythical medicine that mends the maladies of giants.", [22227]="A letter left behind by a pirate captain.", [22228]="A mysterious mass that possesses the power of magic.", [22229]="An enormous gnasher dropped by a drakulord.",
	[22230]="A sure shoe for a horse<1>s hoof.", [22231]="A strange stone that makes miracles happen with heartfelt thanks.", [22232]="The pit of a plum swallowed by a big sea beast.", [22233]="Fluffy stuff left behind by a cloudy foe.",
	[22234]="An itsy-bitsy bottle for collecting witch<1>s wrath.", [22235]="Phew! A pair of pants that exude a powerful pong.", [22246]="A bijou box borne by birds of terrordise.", [22247]="A pretty piece of plumage from a bird of terrordise.",
	[22249]="A rusty and moss-ridden ring.", [22250]="A nugget of knowledge from Barney<1>s ancestors.", [22251]="A bag from Jared for putting top-quality earth in.", [22253]="A bone that makes a melodic yet maudlin sound.",
	[22255]="A golden lubricant left behind by expired exploads.", [22256]="A puff on this will bring the Starflight Express steaming to your aid.", [22257]="Allows the ringer to instantly escape from a tower<,> cave or dungeon.", [22258]="A crystal formed over countless millennia. Alchemise it!",
	[22259]="A ridiculously rare orb of richest red. Alchemise it!", [22260]="A ridiculously rare orb of cornflower blue. Alchemise it!", [22261]="A ridiculously rare orb of buttercup yellow. Alchemise it!", [22262]="A ridiculously rare orb of verdant green. Alchemise it!",
	[22263]="A ridiculously rare orb of deep purple. Alchemise it!", [22264]="A ridiculously rare orb of sparkling silver. Alchemise it!", [22265]="Pop this in your pocket to gain use of the Gigagash ability.", [22266]="Pop this in your pocket to gain use of the Lightning Storm ability.",
	[22267]="Pop this in your pocket to gain use of the Persecutter ability.", [22268]="Pop this in your pocket to gain use of the Zing Stick ability.", [22269]="Pop this in your pocket to gain use of the Serpent<1>s Bite ability.", [22270]="Pop this in your pocket to gain use of the Counter Wait ability.",
	[22271]="Pop this in your pocket to gain use of the Hand of God ability.", [22272]="Pop this in your pocket to gain use of the Hustle Dance ability.", [22273]="Pop this in your pocket to gain use of the Whopper Chop ability.", [22274]="Pop this in your pocket to gain use of the Big Banga ability.",
	[22275]="Pop this in your pocket to gain use of the Gigathrow ability.", [22276]="Pop this in your pocket to gain use of the Shining Shot ability.", [22277]="Pop this in your pocket to gain use of the Miracle Moon ability.", [22278]="Pop this in your pocket to completely avoid critical hits.",
	[22279]="Pop this in your pocket to perform off-the-cuff counterattacks.", [22280]="Pop this in your pocket to gain use of the Wave of Relief ability.", [22281]="Pop this in your pocket to gain use of the Weakening Wave ability.", [22282]="Pop this in your pocket to take tension from battle to battle.",
	[22283]="Pop this in your pocket to steal stuff without lifting a finger.", [22284]="Pop this in your pocket to gain use of the Gritty Ditty ability.", [22285]="Pop this in your pocket to perform two hits per turn sometimes.", [22286]="Pop this in your pocket to gain use of the Solar Flair ability.",
	[22287]="Pop this in your pocket to focus the Fource for you and all your allies.", [22288]="Pop this in your pocket to perform critical hits in times of crisis.", [22289]="Pop this in your pocket to gain use of the Twocus Pocus ability.", [22290]="Pop this in your pocket to gain use of the Gold Rush ability.",
}
-- the description of an item named at the start of a line ("Moonwort bulb, 1 of 2")
ITEM_ID_BY_NAME = nil
function item_desc_of(text)
	if not text or text == "" then return nil end
	if not ITEM_ID_BY_NAME then
		ITEM_ID_BY_NAME = {}
		for id, n in pairs(ITEM_NAMES) do if not ITEM_ID_BY_NAME[n:lower()] then ITEM_ID_BY_NAME[n:lower()] = id end end
	end
	local name = (text:match("^([^,]+)") or text):lower():gsub("%s+$", "")
	local id = ITEM_ID_BY_NAME[name]
	local d = id and ITEM_DESC[id]
	return d and clean_text_g(d) or nil
end
-- story event spots: map number -> { first chapter, step, last chapter, step, box x1, z1, x2, z2, event }
EVENT_SPOTS = {
	[200] = { {11,2,11,2,-7.19,-35.95,-23.97,-45.34,302} },
	[406] = { {1,1,19,99,5.06,-10.43,4.06,-11.43,314} },
	[1100] = { {1,3,1,4,3.57,0.44,0.78,-4.05,17} },
	[1300] = { {1,1,4,4,6.69,31.86,-0.90,29.06,22}, {4,5,4,6,6.69,31.86,-0.90,29.06,22} },
	[1500] = { {7,1,7,1,12.37,18.58,9.58,17.38,342} },
	[1900] = { {19,1,19,99,10.77,12.84,7.78,9.54,45} },
	[5101] = { {2,2,2,2,-0.31,18.86,-13.89,10.27,337}, {2,2,2,2,-7.16,2.40,-13.75,-1.50,325}, {2,2,2,2,-10.43,33.07,-17.23,29.07,342}, {2,7,2,7,-3.14,11.08,-20.22,6.69,239}, {4,7,4,99,-3.56,14.12,-9.35,9.53,331} },
	[5700] = { {14,4,14,4,-12.87,-8.00,-20.76,-9.30,314}, {14,4,14,4,-14.37,9.80,-20.67,8.30,45}, {14,4,14,4,12.16,-11.41,11.06,-16.11,45}, {14,4,14,4,-11.15,-11.57,-12.25,-15.97,314}, {14,4,14,4,13.49,-12.23,11.90,-17.42,45}, {14,4,14,4,-10.01,-13.89,-15.31,-15.49,45}, {14,6,14,6,12.99,-13.24,10.19,-14.24,314}, {14,6,14,6,-11.35,-11.62,-12.35,-16.22,314}, {14,6,14,6,13.85,-13.80,10.56,-14.80,314}, {14,6,14,6,-10.69,-14.03,-14.08,-15.03,222} },
	[5701] = { {14,4,14,5,-15.17,10.97,-16.37,9.37,314} },
	[5702] = { {14,6,14,6,-3.28,2.72,-4.28,1.42,28}, {14,6,14,6,3.47,1.74,2.17,0.74,331} },
	[7901] = { {9,3,9,3,25.25,-1.21,19.66,-3.71,359} },
	[8303] = { {12,5,12,5,3.42,7.35,0.13,6.35,80} },
	[9108] = { {19,2,19,99,6.04,3.89,-1.45,2.29,51} },
}

map_code_frame, map_code_val = -1, ""
local function map_code()
	if map_code_frame ~= frame then map_code_frame, map_code_val = frame, cstring(MAPCODE, 12) end
	local c = map_code_val
	if c:match("^%u%d%dM%d%d") then return c end
	return nil
end
local function map_name()
	local n = cstring(MAPNAME, 40)
	if printable(n) then return clean(n) end
	return nil
end

local function player_pos()
	local p = u32(PLAYER_PTR)
	if not inram(p, 0x60) then return nil end
	return s32(p + 0x44) / 4096, s32(p + 0x48) / 4096, s32(p + 0x4C) / 4096
end

-- Unit vectors for "up" and "right" on screen, in world x/z.
local function screen_axes()
	local px, _, pz = player_pos()
	if not px then return 0, -1, 1, 0 end
	local cx, cz = s32(CAMERA) / 4096, s32(CAMERA + 8) / 4096
	local ux, uz = px - cx, pz - cz
	local len = math.sqrt(ux * ux + uz * uz)
	if len < 0.01 then return 0, -1, 1, 0 end
	ux, uz = ux / len, uz / len
	return ux, uz, -uz, ux
end
function screen_axes_g() return screen_axes() end

local function steps(n, word)
	n = math.floor(math.abs(n) + 0.5)
	if n == 0 then return nil end
	return n .. (n == 1 and " step " or " steps ") .. word
end

local function directions_to(tx, tz)
	local px, _, pz = player_pos()
	if not px then return "unknown" end
	local ux, uz, rx, rz = screen_axes()
	local dx, dz = tx - px, tz - pz
	local fwd, right = dx * ux + dz * uz, dx * rx + dz * rz
	if math.sqrt(dx * dx + dz * dz) < 1.2 then return "right next to you" end
	local a = steps(fwd, fwd >= 0 and "up" or "down")
	local b = steps(right, right >= 0 and "right" or "left")
	if a and b then
		if math.abs(fwd) >= math.abs(right) then return a .. ", " .. b else return b .. ", " .. a end
	end
	return a or b or "right next to you"
end

-- Doors and exits: the game keeps a list of the current map's warp boxes. Each is 0x70 bytes:
-- +0 kind (0 = exit to the surrounding area, 1 = door into a building), +4 max x/y/z,
-- +0x10 min x/y/z, +0x1C id of the map it leads to. Pointer at 0x020FB474, count at 0x020FB478.
WARP_PTR, WARP_COUNT = 0x020FB474, 0x020FB478
local learned = {}          -- names of places reached through exits, learned as you travel
local people = {}           -- who people are, learned when you talk to them
local searched_load = {}
local events_done_load = {}
local function learn_name(id, name)
	if learned[id] == name then return end
	learned[id] = name
	local f = io.open(PLACES_FILE, "a")
	if f then f:write(string.format("%d|name|0|0|%s\n", id, name)) f:close() end
end
-- places the game gives no useful name to
EXIT_NAMES = { [4107] = "stairs up to the Great Hall",       -- Observatory level 2, where Apus Major is
               [4109] = "archway into the Observatory" }       -- the round hall inside level 3
-- names for one exit in one place: "where you are (first 6 letters of the map code)|where it goes"
EXIT_NAMES_AT = {
	["X01M01|4103"] = "Stairs to tree 1",      -- Observatory level 1-2 outside: the stairs up to level 3 (Exterior 3)
	["X01M02|4104"] = "Stairs to tree 2",      -- Observatory level 3 outside (map X01M02): the stairs up to Exterior 4
}
function exit_name_here(id)
	local here = map_code()
	return here and EXIT_NAMES_AT[here:sub(1, 6) .. "|" .. id]
end
-- the door into a named room of a building: "Princess" is the Princess's room
ROOM_DOOR_NAMES = { Princess = "Princess's room door", Throneroom = "throne room door" }
function room_door_label(room)
	if ROOM_DOOR_NAMES[room] then return ROOM_DOOR_NAMES[room] end
	-- "Lv 2, Northern Tower Throneroom": the room's own name after the floor
	room = room:gsub("^Lv %d+, *", ""):gsub("^B%d+, *", "")
	if ROOM_DOOR_NAMES[room] then return ROOM_DOOR_NAMES[room] end
	room = room:gsub("Throneroom", "throne room"):lower()
	if room:match("^b%d+$") then return "basement door" end
	if room:match("^lv %d+$") then return "upstairs door" end
	if room:match("^b%d") or room:match("^lv") then return "door" end
	return room .. " door"
end
local function door_name(id, kind)
	if kind == 0 and exit_name_here(id) then return exit_name_here(id) end
	local m = MAPIDS[id]
	local name = (m and m[2]) or learned[id]
	-- the open field between towns shares its name with the town (Angel Falls): say what it is
	if kind == 0 and id >= 20000 and id < 30000 and not (m and m[2]) then
		-- (a field with a name of its own, "Zere Region", is called that)
		local an = m and AREAS[m[1]:sub(1, 3)]
		name = "the open field"
		if an then
			local town = false
			for c, v in pairs(AREAS) do if v == an and c:match("^[MC]") then town = true end end
			if not town then name = an end
		end
	end
	if not name and m and kind == 0 then name = AREAS[m[1]:sub(1, 3)] end
	if not name and kind == 0 and id >= 20000 and id < 30000 then name = "the open field" end
	if kind == 0 and EXIT_NAMES[id] then return EXIT_NAMES[id] end
	if kind == 0 then
		local here = map_code()
		if name and m and here and m[1]:sub(1, 3) == here:sub(1, 3) and name:match("^Lv %d") then return "passage" end
		-- the game's part names ("Exterior", "Interior - Lv 1") mean nothing on their own:
		-- in another area say the area ("exit to Mountain Pass"), in this one say "outside"
		local room = name and name:match("^Interior.- %- (.+)$")
		if room then
			local l = room_door_label(room):gsub(" door$", "")
			if l ~= "door" then return "exit to " .. (l:gsub("^upstairs$", "upstairs")) end
		end
		-- a castle's own floors ("Interior", "Interior Lv 3"): which floor
		if name and m and here and m[1]:match("^C") and m[1]:sub(1, 3) == here:sub(1, 3) then
			if name == "Interior" then return "exit to the ground floor" end
			local lv = name:match("^Interior Lv (%d+)$")
			if lv then return "exit to the " .. (({ "1st", "2nd", "3rd" })[tonumber(lv)] or (lv .. "th")) .. " floor" end
		end
		if name and m and (name:match("^Exterior") or name:match("^Interior") or name:match("^Lv %d")) then
			if here and m[1]:sub(1, 3) == here:sub(1, 3) then
				if name:match("^Exterior") then return "exit outside" end
			elseif AREAS[m[1]:sub(1, 3)] then
				name = AREAS[m[1]:sub(1, 3)]
			end
		end
		return name and ("exit to " .. name) or "exit"
	end
	if m and m[1]:match("^R0") then name = "Quester's Rest" end        -- the inn's own maps
	-- a part of a building with a name of its own after the dash ("Interior Lv 2 - Princess",
	-- "Interior Lv 2 - Barracks"): that room's name
	local room = name and name:match("^Interior.- %- (.+)$")
	if room then return room_door_label(room) end
	if name and m[1]:match("^C") then
		-- a castle's floors: "Interior" is the ground floor, "Interior Lv 3" the third
		local lv = name:match("^Interior Lv (%d+)$")
		if lv then
			local ord = ({ "1st", "2nd", "3rd" })[tonumber(lv)] or (lv .. "th")
			return "castle door to the " .. ord .. " floor"
		end
		if name == "Interior" then return "castle door to the ground floor" end
	end
	-- another part of the building you are in: the game's own part names ("Lv 1-2") mean nothing
	local here = map_code()
	if name and m and here and m[1]:sub(1, 3) == here:sub(1, 3) then
		if name:match("^Lv %d") or name:match("^Interior %- Lv") then name = nil
		elseif name:match("^Exterior") then return "door outside" end
	end
	-- a door out to another area's part ("Exterior 4" from the Starflight Express): the area
	if name and m and (name:match("^Exterior") or name:match("^Interior")) and AREAS[m[1]:sub(1, 3)] then
		return "door to " .. AREAS[m[1]:sub(1, 3)]
	end
	-- a way down with no door of its own: just its name ("Well", "Cave")
	if name == "Well" or name == "Cave" then return name end
	return name and (name .. " door") or "door"
end
door_name_g = door_name
function door_gimmick_near(x, z, id)
	local base, n = u32(0x020FB480), u32(0x020FB484)
	if n == 0 or n > 200 or not inram(base, n * 0x74) then return id == nil end
	for k = 0, n - 1 do
		local g = base + k * 0x74
		if u32(g + 4) == 2 and math.abs(s32(g + 8) / 4096 - x) < 2 and math.abs(s32(g + 0x10) / 4096 - z) < 2 then
			-- (asked with a map: only a door that leads there)
			-- (also says where the door itself stands)
			if id == nil or u16(g + 0x30) == id then return true, s32(g + 8) / 4096, s32(g + 0x10) / 4096 end
		end
	end
	return false
end
doors_cache = { frame = -1000, id = -1, list = nil, town = nil, town_frame = -1000 }
local function doors()
	-- the doors of a map do not move: look them up again only now and then
	local id = u16(MAPID)
	if doors_cache.list and doors_cache.id == id and frame - doors_cache.frame < 60 then return doors_cache.list end
	local list = doors_raw()
	-- (just after a battle the map's exits are not back yet: "No exits nearby" for a moment)
	if #list == 0 and doors_cache.list and #doors_cache.list > 0 and doors_cache.id == id
		and (in_battle() or frame - (battle_seen_frame or -1000) < 300) then return doors_cache.list end
	if stairs_mark then pcall(stairs_mark, list) end
	doors_cache.list, doors_cache.id, doors_cache.frame = list, id, frame
	return list
end
function doors_raw()
	local list = {}
	local base, n = u32(WARP_PTR), u32(WARP_COUNT)
	if n > 64 or not inram(base, n * 0x70) then return list end
	for k = 0, n - 1 do
		local S = base + k * 0x70
		local kind = u32(S)
		local x1, z1 = s32(S + 4) / 4096, s32(S + 12) / 4096
		local x0, z0 = s32(S + 16) / 4096, s32(S + 24) / 4096
		if kind <= 1 and x1 >= x0 and z1 >= z0 then
			-- an exit with a real door in front of it that leads to the same place is a door
			-- (otherwise it would be listed twice, once in each list)
			if kind == 0 and door_gimmick_near((x0 + x1) / 2, (z0 + z1) / 2, u16(S + 0x1C)) then kind = 1 end
			-- the thin side of the box is the way through it
			local nx, nz = 0, 1
			if (x1 - x0) < (z1 - z0) then nx, nz = 1, 0 end
			local label = door_name(u16(S + 0x1C), kind)
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			local has, gx, gz = door_gimmick_near(cx, cz)
			if label == "door" and not has then
				label = "entrance"      -- a way in with no door, such as a well or a trapdoor
			end
			local e = { label = label, x = cx, z = cz, kind = kind, id = u16(S + 0x1C), nx = nx, nz = nz,
			            x0 = x0, x1 = x1, z0 = z0, z1 = z1, y0 = s32(S + 0x14) / 4096, y1 = s32(S + 8) / 4096 }
			-- an exit that is about as wide as it is deep (the top of a stairway) has no front:
			-- walk straight into it
			if kind == 0 then
				local w, dd = x1 - x0, z1 - z0
				if math.max(w, dd) < 1.5 * math.min(w, dd) then e.nx, e.nz = nil, nil end
			end
			-- a door standing in front of the exit box: the door is where you walk to, and the way
			-- in is from the door's side, through it, into the box
			if kind == 1 and gx then
				local ddx, ddz = gx - cx, gz - cz
				local dl = math.sqrt(ddx * ddx + ddz * ddz)
				if dl > 0.3 and dl < 2.5 then
					e.x, e.z, e.nx, e.nz, e.facing = gx, gz, ddx / dl, ddz / dl, true
					e.wx, e.wz = cx, cz
				end
			end
			list[#list + 1] = e
		end
	end
	return list
end

-- Your own marks, saved per map in dq9-access-places.txt, one per line:  mapcode|mark|x|z|label
local places = {}
local function load_places()
	local f = io.open(PLACES_FILE, "r")
	if not f then return end
	for line in f:lines() do
		local code, kind, x, z, label = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
		if code and kind == "name" and tonumber(code) then learned[tonumber(code)] = label end
		if code and kind == "npc" then people[code] = label end
		if code and kind == "searched" then searched_load[code] = true end
		if code and kind == "eventdone" then events_done_load[code] = true end
		if code and kind == "mark" and tonumber(x) and tonumber(z) then
			places[#places + 1] = { code = code, kind = kind, x = tonumber(x), z = tonumber(z), label = label }
		end
	end
	f:close()
end
local function add_place(code, kind, x, z, label)
	places[#places + 1] = { code = code, kind = kind, x = x, z = z, label = label }
	local f = io.open(PLACES_FILE, "a")
	if f then
		f:write(string.format("%s|%s|%.2f|%.2f|%s\n", code, kind, x, z, label))
		f:close()
	end
end

local function map_key(code) return code and code:sub(1, 6) or "" end
local function place_key() return map_key(map_code()) .. "#" .. u16(MAPID) end

-- The screen fades through the DS master brightness register; while it is fading the player is
-- walking through a door, not into a wall. If this BizHawk build cannot read hardware registers
-- the check simply says "not fading".
local brightness_ok = true
local function fading()
	if not brightness_ok then return false end
	local ok, v = pcall(function() return memory.read_u16_le(0x0400006C, "ARM9 System Bus") end)
	if not ok or type(v) ~= "number" then brightness_ok = false return false end
	return v ~= 0
end

local cur_code, code_changed_frame = nil, -1000
local settled = nil       -- the map we last announced: { code, label }
local pending = nil       -- a map change that is still loading
local near_door = nil     -- the door the player was last standing close to

-- "Angel Falls, Inn": the town name, then the building from the game's own map list
local function room_name()
	local m = MAPIDS[u16(MAPID)]
	if m and m[1]:match("^R0") and m[2] then
		-- the Quester's Rest: "Lobby Interior 1" is the lobby
		return "Quester's Rest " .. (m[2]:gsub(" Interior %d+$", ""):gsub(" Interior$", ""))
	end
	if m and #m[1] > 3 and m[2] and not m[2]:match("^M%d") then return m[2] end
	return nil
end
local function track_map()
	local code = map_code()
	if not code then return end
	code = code .. "#" .. u16(MAPID)
	local x, _, z = player_pos()
	if not x then return end
	if code ~= cur_code then
		cur_code, code_changed_frame = code, frame
		if not settled or map_key(code) .. (code:match("#%d+$") or "") ~= map_key(settled.code) .. (settled.code:match("#%d+$") or "") then
			pending = { sx = x, sz = z, door = near_door }
		end
	end
	if pending then
		-- The player is moved to the new map a little after the map code changes; wait for the jump.
		local jumped = math.abs(x - pending.sx) > 1 or math.abs(z - pending.sz) > 1
		local waited = frame - code_changed_frame
		if ((jumped or not settled) and not fading() and waited > 30 and map_name()) or waited > 150 then
			local label = map_name() or "somewhere new"
			-- going in through a door: say which building, if the game's map list names it
			local d = pending.door
			local room = room_name()
			if room and map_name() then
				label = room == map_name() and room or (map_name() .. ", " .. room)
			elseif d and d.kind == 1 then
				label = label .. ", " .. (d.label ~= "door" and d.label:gsub(" door$", "") or "inside")
			elseif d and d.kind == 0 and map_name() and (d.label == "exit" or d.label == "exit to the open field") then
				learn_name(d.id, map_name())       -- the exit had no name: now we know where it goes
			end
			if not settled or label ~= settled.label then queue(label) end
			settled = { code = code, label = label }
			pending, near_door = nil, nil
		end
	elseif frame % 5 == 0 then
		near_door = nil
		for _, d in ipairs(doors()) do
			if math.abs(d.x - x) < 3 and math.abs(d.z - z) < 3 then near_door = d end
		end
		if not near_door and town_doors then
			for _, d in ipairs(town_doors()) do
				if math.abs(d.x - x) < 3 and math.abs(d.z - z) < 3 then near_door = d end
			end
		end
	end
end

------------------------------------------------------------------------------ nearby --------
local selected = 0
local nearby = {}

-- A person is known by the map and the spot the game placed them at, so the name you learn by
-- talking to them sticks even when they wander about.
local function npc_key(o)
	local r = u32(o + 0x0C)
	if not inram(r, 0x20) then return nil end
	if not map_code() then return nil end
	return place_key() .. ":" .. math.floor(s32(r + 0x10) / 4096 + 0.5) .. ":" .. math.floor(s32(r + 0x18) / 4096 + 0.5)
end

-- What the townspeople look like, from the game's own character pictures (data/ani/n001a.spr ...).
-- The letter after the number is a colour variant; "g" is the ghostly version.
NPC_LOOKS = {
	n001 = "man in a straw hat", n002 = "young woman in a dress", n003 = "stout man with a beard",
	n004 = "old woman in a headscarf and apron", n005 = "old man with a walking stick",
	n006 = "old woman with glasses", n007 = "big man in a horned helmet", n008 = "stout man in a cap",
	n009 = "man in a red coat", n010 = "minstrel with a lute", n011 = "man in a bandana",
	n012 = "old man with a white beard and a red cap", n013 = "woman in an apron", n014 = "boy",
	n015 = "little girl with a bow", n016 = "priest", n017 = "nun", n018 = "bearded man in a wide straw hat",
	n019 = "sailor in a striped shirt", n020 = "blonde woman in green", n021 = "dancer",
	n022 = "lady in a pink gown", n023 = "old man in black with a red bow tie", n024 = "cook",
	n025 = "king", n026 = "nobleman in a green robe", n027 = "lady in a blue gown", n028 = "soldier",
	n029 = "royal guard", n030 = "maid", n031 = "woman warrior with a spear",
	n032 = "woman in red with a shield", n033 = "martial artist in green", n034 = "hooded man",
	n035 = "woman in a purple cloak", n036 = "bald man with a beard", n037 = "stout man in a green coat",
	n039 = "angel, young man", n040 = "angel, woman with teal hair", n041 = "angel, bearded man",
	n042 = "angel, elder in a robe", n043 = "angel with a ponytail", n044 = "angel in purple",
	n045 = "angel in purple", n046 = "angel, blonde woman", n047 = "angel, child",
	n048 = "angel, woman with blue hair", n049 = "skeleton in a coat", n050 = "knight in dark armour",
	n051 = "warrior in red armour", n052 = "man in an orange robe", n053 = "woman in an orange dress",
	n054 = "stout man in green", n055 = "bald man in a yellow robe", n056 = "man in a blue robe",
	n057 = "woman with a red headband", n058 = "old man in a grey hat", n059 = "old woman in green",
	n060 = "boy in a teal cap", n061 = "girl in yellow", n062 = "man in a striped robe",
	n063 = "man with a red headband", n064 = "woman in white with a red headband",
	n065 = "old warrior with a grey beard", n066 = "old man in a red waistcoat",
	n067 = "woman in a long orange dress", n068 = "sailor in a blue waistcoat",
	n069 = "woman in a yellow dress", n070 = "old man with a long white beard",
	n071 = "blonde woman in white", n072 = "girl in a tribal outfit", n073 = "woman with pink pigtails",
	n074 = "boy with white hair", n075 = "girl in an orange dress", n076 = "old man in a purple robe",
	n077 = "man in a purple coat", n078 = "woman in a purple dress", n079 = "stout man in a red coat",
	n080 = "student in a red jacket", n081 = "student with spiky hair",
	n082 = "student, girl with blonde pigtails", n083 = "student, girl with a headband",
	n084 = "student with glasses", n085 = "student, girl with teal hair",
	n088 = "stout man in a brown coat", n089 = "man in a brown robe",
	n092 = "bald old man with a white beard", n095 = "shirtless man", n096 = "cat", n097 = "dog",
	n098 = "cow", n099 = "horse", n100 = "little floating spirit", n101 = "girl in a swimsuit",
	n102 = "skeleton", n103 = "skeleton", n104 = "sheep", n106 = "stone statue",
	n107 = "stone statue of a woman", n108 = "stone statue of a stout man",
	n109 = "stone statue of an old man", n110 = "stone statue of a man",
	n111 = "stone statue of a woman", n112 = "stone statue of a child",
	n113 = "stone statue of a man in a hat", n114 = "stone statue of a cat",
	n300 = "woman in a blue dress and apron", n301 = "woman in a yellow dress and apron",
	n302 = "woman with blue hair in a red dress", n303 = "winged woman with white hair",
	n304 = "fish", n305 = "alchemy pot", n306 = "woman in a green robe",
	n900 = "stout man in purple and gold", n901 = "bishop", n902 = "soldier in green",
	n903 = "young man in green", n904 = "young woman in a pink dress",
	n905 = "nobleman in a green robe", n906 = "king", n907 = "old woman in a headscarf and apron",
	n908 = "big man in a horned helmet", n909 = "nun", n910 = "boy",
	n911 = "bearded man in a wide straw hat", n912 = "stout man in blue",
	n913 = "old man with a walking stick", n916 = "blonde woman in green", n919 = "cat",
	n925 = "woman with blue hair in a red dress",
}
function npc_look(model)
	local desc = NPC_LOOKS[model:sub(1, 4)]
	if not desc then return nil end
	if model:sub(5, 5) == "g" then desc = "ghostly " .. desc end
	return desc
end

-- names for particular people and things: their place and position (as in dq9-access-places.txt)
OBJECT_NAMES = {
	["X01M04#4104:0:-3"] = "Tree",             -- Observatory level 4 outside: where you offer benevolessence to Yggdrasil
	["X01M05#4105:2:3"] = "Portal keeper",     -- Observatory level 1-1: the Celestrian by the portal down to the Protectorate
}
-- the name for a person or thing: its own position, or one step either way (positions are rounded)
function object_name(key)
	if OBJECT_NAMES[key] then return OBJECT_NAMES[key] end
	local place, x, z = key:match("^(.*):(%-?%d+):(%-?%d+)$")
	if not place then return nil end
	x, z = tonumber(x), tonumber(z)
	for k, name in pairs(OBJECT_NAMES) do
		local p2, x2, z2 = k:match("^(.*):(%-?%d+):(%-?%d+)$")
		if p2 == place and math.abs(tonumber(x2) - x) <= 1 and math.abs(tonumber(z2) - z) <= 1 then return name end
	end
	return nil
end
-- Named people, from the game's own talk files (data/scenario/<area><chapter>.gp2: one message
-- file per person, numbered like the person's placement; the name the game shows when they speak).
-- By area (the first three letters of the map code) and the person's number.
NPC_NAMES = {
	C01 = { [10] = "Ricki", [38] = "Maisie", [39] = "Queen Schott", [45] = "King Schott", [46] = "Princess Simona", [70] = "Angus", [72] = "Earnan", [112] = "Colonel MacDuff", [114] = "Yore", [115] = "Maeve", [116] = "Calhoun", [119] = "Branton", [120] = "Claude", [122] = "Alison", [128] = "Rufus", [129] = "Cosette", [131] = "King Schott", [133] = "Princess Simona", [209] = "Hamish", [211] = "Julia", [212] = "Bill", [215] = "Gulliver", [216] = "Malinda", [217] = "Kalvin" },
	C02 = { [104] = "Misslei", [200] = "Drak", [210] = "Brunhild", [211] = "Fry", [212] = "Peregrine", [214] = "Duff", [215] = "Ruki", [216] = "Walter", [217] = "Mehdik", [219] = "Applaudia", [220] = "Nivia", [221] = "Afan", [223] = "Pluvius" },
	C04 = { [10] = "Aquila", [11] = "King Godwyn", [12] = "Lieutenant Hootingham-Gore", [13] = "Lieutenant Goresby-Purrvis", [14] = "Lieutenant Goresby-Purrvis", [200] = "Supreme Sage" },
	D03 = { [0] = "Wight Knight", [7] = "Princess Simona", [116] = "Maeve", [117] = "Calhoun", [120] = "Princess Simona" },
	D04 = { [29] = "Dr Phlegming" },
	D06 = { [0] = "Elios" },
	D07 = { [11] = "Christopher Collapsus", [12] = "Ardaz Nayuls", [202] = "Odval", [203] = "Muunokhoi" },
	D08 = { [202] = "Drak", [207] = "Al Capinne", [209] = "Sellma" },
	D09 = { [35] = "Marion", [61] = "Tyrantula" },
	D13 = { [18] = "Fred", [21] = "Sir Sternivus Swinedimple", [47] = "Sir Sternivus Swinedimple", [48] = "Vena" },
	D14 = { [26] = "Serena", [101] = "Dr Earlybird" },
	D16 = { [101] = "Greygnarl", [200] = "Unscrupulus Maximus" },
	F24 = { [44] = "Patty" },
	F57 = { [200] = "Unscrupulus Maximus" },
	H02 = { [1] = "Gus" },
	H03 = { [1] = "Timmy", [2] = "Enid" },
	H04 = { [1] = "Eric", [2] = "Derek" },
	H05 = { [1] = "Nicholas" },
	H06 = { [1] = "Woody" },
	H08 = { [1] = "Baabara", [2] = "Selwyn" },
	H09 = { [1] = "Barney" },
	H10 = { [1] = "Herman" },
	H11 = { [1] = "Chris Cringle" },
	H12 = { [1] = "Prancer", [2] = "Dancer", [3] = "Graham the Bird" },
	H14 = { [1] = "C. Nile" },
	H17 = { [1] = "Shanice" },
	H18 = { [1] = "Myrrhia", [2] = "King Considerate" },
	H19 = { [1] = "Cephalgernon", [2] = "Fickser" },
	H20 = { [1] = "Skully", [2] = "Billy Bones", [3] = "Jolly Roger" },
	M01 = { [7] = "Ivor", [8] = "Hugo", [16] = "Mayor Litlun", [21] = "Patty", [22] = "Godfrey", [97] = "Winnston", [98] = "Erinn", [99] = "Aquila", [100] = "Dr Slimon", [102] = "Chanterelle", [104] = "Veginia", [105] = "Sootheslime", [106] = "Questelle", [204] = "Edwinn" },
	M02 = { [10] = "Alanna", [15] = "Petra", [18] = "George", [23] = "Jared", [26] = "Wellard", [27] = "Harmony" },
	M03 = { [25] = "Mayor Laria", [26] = "Catarrhina", [29] = "Dr Phlegming", [32] = "Catarrhina", [35] = "Dodger", [36] = "Dr Phlegming", [37] = "Dr Phlegming", [98] = "Dr Phlegming", [200] = "Earnest", [201] = "Jade", [202] = "Lionel", [203] = "Doug", [204] = "Mrs Tofferton", [206] = "Dominique" },
	M05 = { [1] = "Jona", [2] = "Bryson", [3] = "Mayor Bryce", [51] = "Glitzy" },
	M07 = { [21] = "Rocky" },
	M08 = { [18] = "Colden", [24] = "Buster" },
	M09 = { [17] = "Pete", [23] = "Mayor Daff", [31] = "Mayoress Daff", [35] = "Marion", [39] = "Randolph", [51] = "Meowser", [53] = "Sister Cindy", [60] = "Dusty", [76] = "Wallace", [77] = "Christina", [78] = "Rayne", [79] = "Bert" },
	M10 = { [22] = "Batzorig", [27] = "Batkhaan", [28] = "Sarantsatsral", [100] = "Larstastnaras", [101] = "Chuluun", [102] = "Enkh", [103] = "Phoebe", [208] = "Conner" },
	M11 = { [1] = "Headmaster", [18] = "Fred", [50] = "Itchy", [51] = "Archie", [52] = "Boomer", [53] = "Kylie", [54] = "Max", [55] = "Marco", [56] = "Alchemilla", [57] = "Buckler", [58] = "Mrs Mallet", [59] = "Klaus", [60] = "Paulo", [61] = "Bumbles", [62] = "Toadie", [63] = "Fanny", [64] = "Mr Whippy", [65] = "Cecil", [66] = "Lance", [67] = "Madame Couteau" },
	M12 = { [5] = "Charlene", [15] = "Mayor Doffish", [16] = "Wallace", [31] = "Forger", [100] = "Kevo", [101] = "Stasha", [102] = "Scarface", [104] = "Hordy", [107] = "Clare Voyant", [108] = "Mayor Doffish" },
	M13 = { [23] = "Kelly", [100] = "Skye" },
	R01 = { [90] = "Ginny", [98] = "Erinn", [99] = "Pavo", [100] = "Krak Pot", [202] = "Sellma", [203] = "Patty", [205] = "Erinn", [206] = "Patty", [208] = "Erinn", [209] = "Ginny", [210] = "Patty", [211] = "Sellma" },
	R02 = { [90] = "Ginny", [98] = "Erinn", [99] = "Pavo", [100] = "Krak Pot", [202] = "Sellma", [203] = "Patty", [208] = "Erinn", [210] = "Patty", [211] = "Sellma" },
	R03 = { [90] = "Ginny", [98] = "Erinn", [99] = "Pavo", [100] = "Krak Pot", [202] = "Sellma", [203] = "Patty", [208] = "Erinn", [210] = "Patty", [211] = "Sellma" },
	R04 = { [90] = "Ginny", [98] = "Erinn", [99] = "Pavo", [100] = "Krak Pot", [202] = "Sellma", [203] = "Patty", [208] = "Erinn", [210] = "Patty", [211] = "Sellma" },
	R05 = { [101] = "Prince Princeton", [102] = "Princess Princessa", [103] = "Alena", [104] = "Kiryl", [105] = "Borya", [106] = "Meena", [107] = "Maya", [108] = "Torneko", [109] = "Ragnar", [110] = "Bianca", [111] = "Nera", [112] = "Debora", [113] = "Milly", [114] = "Carver", [115] = "Ashlynn", [116] = "Kiefer", [117] = "Maribel", [118] = "Jessica", [119] = "Angelo", [120] = "Yangus", [121] = "King Trode", [122] = "Morrie", [123] = "Fleurette" },
	S01 = { [7] = "Ivor", [101] = "Ivor", [200] = "Pauline" },
	S02 = { [3] = "Flame Tang" },
	S03 = { [4] = "Romeo" },
	S04 = { [1] = "Dirk" },
	S05 = { [1] = "Jona", [3] = "Mayor Bryce" },
	S06 = { [16] = "Nergui", [22] = "Batzorig", [29] = "Khoonbish", [201] = "Tuya" },
	S07 = { [201] = "Lieutenant Goreham-Hogg", [203] = "Sterling", [211] = "Digby" },
	S10 = { [12] = "Victor" },
	S11 = { [1] = "Batzorig", [2] = "Khoonbish", [3] = "Bayarmaa" },
	S12 = { [3] = "Catwright" },
	S13 = { [2] = "Wallace", [3] = "Serena", [5] = "Charlene" },
	S14 = { [2] = "Stella", [203] = "Sterling" },
	T02 = { [2] = "Nodoph" },
	X01 = { [99] = "Aquila", [133] = "Columba", [139] = "Apus Major" },
	X02 = { [17] = "Jack of Alltrades", [24] = "Cribber", [100] = "Brusque Lee", [101] = "Grandmaster Wun Tun Punch", [104] = "Tom Foolery", [105] = "Windy" },
	X03 = { [6] = "Celestria", [139] = "Apus Major", [140] = "Stella", [203] = "Sterling" },
	X04 = { [201] = "Lieutenant Goreham-Hogg", [202] = "Lieutenant Hootingham-Gore", [203] = "Lieutenant Goresby-Purrvis", [204] = "Corvus", [205] = "Corvus" },
	X05 = { [133] = "Columba", [139] = "Apus Major", [203] = "Sterling", [204] = "Stella", [205] = "Apus Major" },
}
-- the person's name from the table above: the map's area and the number in their placement record
function npc_game_name(o)
	local r = u32(o + 0x0C)
	if not inram(r, 0x20) then return nil end
	local c = map_code()
	local t = c and NPC_NAMES[c:sub(1, 3)]
	return t and t[u8(r)]
end
-- story models that are things, not characters
STORY_THINGS = { s097 = "shiny object" }
-- What each thing is, from the game's talk files (dq9-access-objects.lua): by area and the number
-- in its placement record, sometimes by story chapter (the talk files are lettered A, B ... by
-- chapter). "-" is a spot that only says a door is locked.
pcall(dofile, DIR .. "dq9-access-objects.lua")
function obj_label(o)
	if not OBJ_LABELS then return nil end
	local r = u32(o + 0x0C)
	if not inram(r, 0x20) then return nil end
	local c = map_code()
	if not c then return nil end
	local t = OBJ_LABELS[c:sub(1, 3)] or (c:sub(1, 1) == "F" and OBJ_LABELS.F)
	local e = t and t[u8(r)]
	if type(e) ~= "table" then return e end
	local now = string.char(64 + math.max(1, math.min(26, story_now() // 100)))
	local best, bl, first, fl = nil, nil, nil, nil
	for L, v in pairs(e) do
		if L <= now and (not bl or L > bl) then best, bl = v, L end
		if not fl or L < fl then first, fl = v, L end
	end
	return best or first
end
local function characters()
	local list = {}
	local n = u32(OBJ_COUNT)
	if n > 64 then return list end
	local px, _, pz = player_pos()
	for i = 0, n - 1 do
		local o = u32(OBJ_TABLE + 4 * i)
		if inram(o, 0x70) then
			local m = u32(o + 0x08)
			local model = inram(m, 12) and cstring(m + 4, 8) or ""
			-- story characters (models s001, s025 ...) are built differently: their position
			-- is further into the object
			local story = model:match("^s%d%d%d") ~= nil
			local x, z
			if story then x, z = s32(o + 0x64) / 4096, s32(o + 0x6C) / 4096
			else x, z = s32(o + 0x24) / 4096, s32(o + 0x2C) / 4096 end
			local far = math.abs(x) > 1000 or math.abs(z) > 1000       -- parked off the map
			-- (or parked at exactly -100, -100: the Krak Pot at the Quester's Rest before Erinn
			-- hands it over)
			if math.abs(x + 100) < 0.01 and math.abs(z + 100) < 0.01 then far = true end
			if not far and not (px and math.abs(x - px) < 0.05 and math.abs(z - pz) < 0.05) then
				-- people are drawn from a character sprite (n001a ...); signs, statues and the
				-- like have none
				local person = model:match("^%l%d%d%d") ~= nil
				local key = npc_key(o)
				local label = key and people[key]
				-- a person the game has a name for: that name, even before you talk to them
				local gname = (person or story) and npc_game_name(o)
				if gname and (not label or label:find("^someone who says")) then label = gname end
				local look = person and not story and npc_look(model)
				if not person and label then
					if label:find("reads the sign", 1, true) then label = "sign"
					else label = label:gsub("^someone who says", "something that says") end
				end
				-- a thing: what the game's own words say it is (unless you have read it already)
				local skip = false
				if not person and not story then
					local tl = obj_label(o)
					if tl == "-" then skip = true
					elseif tl and (not label or label:find("^something")) then label = tl end
				end
				-- (a game name learned by mistake for someone standing next to its owner)
				if label and not gname and person and key and people[key] == label then
					local c = map_code()
					local t = c and NPC_NAMES[c:sub(1, 3)]
					local bare = label:gsub("%s+$", "")
					if t then for _, v in pairs(t) do if v == bare then label = nil break end end end
				end
				-- only names are kept for people; what they said is not part of the label
				if person and label and label:find("^someone who says") then label = nil end
				if story and label and label ~= gname then label = label .. ", story character" end
				label = label or look
				if key and object_name(key) then label = object_name(key) end
				-- some story models are things to pick up, not people (the lost ring in the grass)
				local sthing = story and STORY_THINGS[model:sub(1, 4)]
				if skip then
					-- (left out)
				elseif sthing then
					list[#list + 1] = { label = sthing, x = x, z = z, obj = o, key = key, thing = true, item = true, posoff = 0x64 }
				else
				-- signs and statues face one way (+0x34, 0x10000 to a turn; 0 faces +z): the side
				-- they can be read from
				list[#list + 1] = { label = label or (story and "story character" or person and "someone" or "something"),
				                    x = x, z = z, obj = o, key = key, thing = not person, story = story, posoff = story and 0x64 or nil,
				                    fy = s32(o + (story and 0x68 or 0x28)) / 4096,
				                    rot = (not person and not story) and u16(o + 0x34) or nil }
				end
			end
		end
	end
	-- an unnamed spot right where a person stands (the talk spot behind a counter): the person
	-- is already on the list
	local out = {}
	for _, c in ipairs(list) do
		local dup = false
		if c.thing and c.label == "something" then
			for _, d in ipairs(list) do
				if not d.thing and math.abs(d.x - c.x) < 0.5 and math.abs(d.z - c.z) < 0.5 then dup = true break end
			end
		end
		if not dup then out[#out + 1] = c end
	end
	return out
end

-- Things you can search (cupboards, pots, barrels, chests ...): the map's list of "gimmicks".
-- Each is a small box with a kind number; doors are kind 2 and are already in the door list.
GIMMICK_PTR, GIMMICK_COUNT = 0x020FB480, 0x020FB484
local searched = searched_load  -- things you have already opened or looked in, kept in the places file
GIMMICK_NAMES = { [0] = "pot or barrel", [1] = "treasure chest", [5] = "cupboard", [6] = "barrel", [8] = "bookshelf", [9] = "something to search" }
local function map_items()
	local list = {}
	local base, n = u32(GIMMICK_PTR), u32(GIMMICK_COUNT)
	if n == 0 or n > 200 or not inram(base, n * 0x74) then return list end
	for k = 0, n - 1 do
		local g = base + k * 0x74
		local kind = u32(g + 4)
		local sx, sz = s32(g + 0x14) / 4096, s32(g + 0x1C) / 4096
		if kind ~= 2 and kind < 64 and math.abs(sx) <= 3 and math.abs(sz) <= 3 then
			local x, z = s32(g + 8) / 4096, s32(g + 0x10) / 4096
			local key = place_key() .. ":" .. math.floor(x + 0.5) .. ":" .. math.floor(z + 0.5)
			local label = GIMMICK_NAMES[kind] or "something to search"
			if searched[key] then label = label .. (kind == 1 and ", opened" or ", searched") end
			list[#list + 1] = { label = label, x = x, z = z, item = true, gkind = kind, key = key, fy = s32(g + 0x0C) / 4096 }
		end
	end
	return list
end

-- Pressing A right next to a pot, barrel, chest ... (and nearer to it than to anyone) searches it:
-- remember that, so the list can say "searched" or "opened".
local function mark_searched()
	local px, _, pz = player_pos()
	if not px then return end
	local nearest_person = 99
	for _, c in ipairs(characters()) do
		local d = math.sqrt((c.x - px) ^ 2 + (c.z - pz) ^ 2)
		if d < nearest_person then nearest_person = d end
	end
	local best, bd = nil, 1.4
	for _, it in ipairs(map_items()) do
		local d = math.sqrt((it.x - px) ^ 2 + (it.z - pz) ^ 2)
		if d < bd then best, bd = it, d end
	end
	if best and bd < nearest_person and not searched[best.key] then
		searched[best.key] = true
		-- pots, barrels and shelves fill up again after a while; only opened chests are kept
		if best.gkind ~= 1 then return end
		local f = io.open(PLACES_FILE, "a")
		if f then f:write(best.key .. "|searched|0|0|" .. (GIMMICK_NAMES[best.gkind] or "") .. "\n") f:close() end
	end
end

-- Sparkly spots in the open fields: the game keeps a chain of the spots that are showing right
-- now. The field's list of spots says which item each one gives.
SPARKLE_GROUPS, SPARKLE_GROUP_COUNT, SPARKLE_HEAD = 0x02108FE8, 0x02108FEC, 0x0210902C
local function sparkle_item(x, z)
	local g0, n = u32(SPARKLE_GROUPS), u16(SPARKLE_GROUP_COUNT)
	if n == 0 or n > 40 or not inram(g0, n * 0x70) then return nil end
	for k = 0, n - 1 do
		local g = g0 + k * 0x70
		for j = 0, 7 do
			local a = g + 0x0C + j * 12
			if math.abs(s32(a) / 4096 - x) < 0.3 and math.abs(s32(a + 8) / 4096 - z) < 0.3 then
				local nm = ITEM_NAMES[u16(g)]
				return nm
			end
		end
	end
	return nil
end
-- Doors inside a town that open onto the same map (Stornway's houses, for example) are not warps,
-- only "gimmicks" of kind 2. List the ones that are not already a warp door.
function town_doors()
	local id = u16(MAPID)
	if doors_cache.town and doors_cache.town_id == id and frame - doors_cache.town_frame < 60 then return doors_cache.town end
	local list = town_doors_raw()
	doors_cache.town, doors_cache.town_id, doors_cache.town_frame = list, id, frame
	return list
end
function town_doors_raw()
	local list = {}
	local base, n = u32(GIMMICK_PTR), u32(GIMMICK_COUNT)
	if n == 0 or n > 200 or not inram(base, n * 0x74) then return list end
	local ws = doors()
	for k = 0, n - 1 do
		local g = base + k * 0x74
		if u32(g + 4) == 2 then
			local x, z = s32(g + 8) / 4096, s32(g + 0x10) / 4096
			local dup = false
			for _, d in ipairs(ws) do if d.kind == 1 and math.abs(d.x - x) < 2 and math.abs(d.z - z) < 2 then dup = true end end
			for _, d in ipairs(list) do if math.abs(d.x - x) < 1 and math.abs(d.z - z) < 1 then dup = true end end
			-- the map the door leads to (a shop, a house ...) is kept at +0x30
			local id = u16(g + 0x30)
			local label = (MAPIDS[id] or learned[id]) and door_name(id, 1) or "door"
			if not dup then list[#list + 1] = { label = label, x = x, z = z, kind = 1, gdoor = true, id = id } end
		end
	end
	return list
end

local function sparkles()
	local list = {}
	local node, guard = u32(SPARKLE_HEAD), 0
	while inram(node, 0x18) and guard < 40 do
		local x, z = s32(node + 4) / 4096, s32(node + 0x0C) / 4096
		if math.abs(x) < 1000 and math.abs(z) < 1000 then
			local what = sparkle_item(x, z)
			list[#list + 1] = { label = "sparkly spot" .. (what and (", " .. what) or ""), x = x, z = z, sparkle = true }
		end
		node, guard = u32(node + 0x14), guard + 1
	end
	return list
end

-- Story event spots: boxes on the map that start a story scene when you walk in, taken from the
-- game's trigger files. Each is only live for part of the story (chapter and step), which the
-- game keeps in two bytes. Once you have walked into one it is marked as done.
STORY_PROGRESS = 0x02108844
local events_done = events_done_load
local function event_spots()
	local list = {}
	local spots = EVENT_SPOTS[u16(MAPID)]
	if not spots then return list end
	local now = u8(STORY_PROGRESS) * 100 + u8(STORY_PROGRESS + 1)
	for _, e in ipairs(spots) do
		if now >= e[1] * 100 + e[2] and now <= e[3] * 100 + e[4] then
			local key = u16(MAPID) .. ":" .. e[9] .. ":" .. math.floor(e[5]) .. ":" .. math.floor(e[6])
			local x0, x1 = math.min(e[5], e[7]), math.max(e[5], e[7])
			local z0, z1 = math.min(e[6], e[8]), math.max(e[6], e[8])
			list[#list + 1] = { label = "story event" .. (events_done[key] and ", already seen" or ""),
			                    x = (x0 + x1) / 2, z = (z0 + z1) / 2, event = true, key = key,
			                    x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
		end
	end
	return list
end
local function watch_events()
	local px, _, pz = player_pos()
	if not px then return end
	for _, e in ipairs(event_spots()) do
		if not events_done[e.key] and px >= e.x0 - 0.5 and px <= e.x1 + 0.5 and pz >= e.z0 - 0.5 and pz <= e.z1 + 0.5 then
			events_done[e.key] = true
			local f = io.open(PLACES_FILE, "a")
			if f then f:write(e.key .. "|eventdone|0|0|story event\n") f:close() end
		end
	end
end

-- Monsters walking about in the open: the game keeps twelve slots for them. Each points at an
-- entry of this area's monster list, which starts with the monster's name.
MONSTER_SLOTS = 0x020F35A0
local function monsters()
	local list = {}
	local px, _, pz = player_pos()
	for k = 0, 11 do
		local o = u32(MONSTER_SLOTS + 4 * k)
		if inram(o, 0x198) and u16(o + 2) ~= 0xFFFF and u16(o + 6) ~= 0xFFFF then
			local x, z = s32(o + 0x44) / 4096, s32(o + 0x4C) / 4096
			local e = u32(o + 0x180)
			local name = inram(e, 4) and clean(cstring(u32(e), 40)) or ""
			if name == "" or not printable(name) then name = "monster" end
			if math.abs(x) < 1000 and math.abs(z) < 1000 and not (px and math.abs(x - px) < 0.05 and math.abs(z - pz) < 0.05) then
				list[#list + 1] = { label = name, x = x, z = z, obj = o, posoff = 0x44, monster = true }
			end
		end
	end
	return list
end

-- Who did you just talk to? The nearest person. Their name if the message gives one, otherwise
-- the start of what they said, for example: someone who says "Welcome to the inn".
on_new_message = function(text, full)
	full = full or text
	local px, _, pz = player_pos()
	if not px then return end
	local best, bd = nil, 2.6
	for _, c in ipairs(characters()) do
		local d = math.sqrt((c.x - px) ^ 2 + (c.z - pz) ^ 2)
		if c.key and d < bd then best, bd = c, d end
	end
	local known = best and people[best.key]
	-- a sign read from the wrong side is learned again once it has been read properly
	if not best or (known and not (best.thing and (known == "sign" or known == "inscription" or known:find("something that says", 1, true) or known:find("reads the sign", 1, true)))) then return end
	local name = text:match("^([%u][%w%.' %-]-): ")
	-- someone the game itself names (Apus Major, Aquila ...) is speaking: the name is theirs,
	-- not that of whoever happens to stand nearest you
	if name and not best.thing then
		local mine = best.obj and npc_game_name(best.obj)
		if mine and mine ~= name then return end
		local c = map_code()
		local t = c and NPC_NAMES[c:sub(1, 3)]
		if t then for _, v in pairs(t) do if v == name and mine ~= name then return end end end
	end
	local label
	if best.thing then
		if full:find("reads the sign", 1, true) then
			-- a sign: remember what it says (the words are on the next page)
			local said = full:match("reads the sign%.?%s*(.*)$") or ""
			said = said:gsub("^[%(%s'\"]+", ""):gsub("[%)%s'\"]+$", "")
			label = (said ~= "" and not said:find("wrong side", 1, true)) and ("sign: " .. said) or "sign"
		elseif full:lower():find("inscription", 1, true) then
			local said = full:match("inscription[^%.]*%.%s*(.*)$") or ""
			said = said:gsub("^[%(%s'\"]+", ""):gsub("[%)%s'\"]+$", "")
			label = said ~= "" and ("inscription: " .. said) or "inscription"
		elseif full:match("examines the ([%a%s%-]+)") then
			label = full:match("examines the ([%a%s%-]+)"):gsub("%s+$", "")
		end
		name = nil
	end
	if label then
		-- already worked out above
	elseif name and #name <= 24 then
		label = name
	else
		local words, out = 0, {}
		for w in text:gmatch("%S+") do
			words = words + 1
			out[#out + 1] = w
			if words >= 8 or w:match("[%.!%?]$") or (words >= 4 and w:match(",$")) then break end
		end
		local snippet = table.concat(out, " "):gsub("[%.,!%?]+$", "")
		if snippet == "" then return end
		label = (best.thing and 'something that says "' or 'someone who says "') .. snippet .. '"'
	end
	people[best.key] = label
	local f = io.open(PLACES_FILE, "a")
	if f then f:write(best.key .. "|npc|0|0|" .. label .. "\n") f:close() end
end

-- Many doors with no name of their own (the rooms around the Observatory's hall): call each
-- one after the side of the place it is on, "left door, upper", "top door, middle" and so on.
function name_doors_by_side(ds)
	local plain = {}
	for _, d in ipairs(ds) do
		d.base_label = d.base_label or d.label
		if d.kind == 1 and d.base_label == "door" then plain[#plain + 1] = d else d.label = d.base_label end
	end
	if #plain < 3 then for _, d in ipairs(plain) do d.label = d.base_label end return end
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, d in ipairs(plain) do
		x0, x1 = math.min(x0, d.x), math.max(x1, d.x)
		z0, z1 = math.min(z0, d.z), math.max(z1, d.z)
	end
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local sides = { top = {}, bottom = {}, left = {}, right = {} }
	for _, d in ipairs(plain) do
		local dx, dz = d.x - cx, d.z - cz
		local side
		if math.abs(dx) > math.abs(dz) then side = dx < 0 and "left" or "right" else side = dz < 0 and "top" or "bottom" end
		table.insert(sides[side], d)
	end
	for side, list in pairs(sides) do
		local across = (side == "top" or side == "bottom")
		table.sort(list, function(a, b) if across then return a.x < b.x else return a.z < b.z end end)
		local words = across and { "left", "middle", "right" } or { "upper", "middle", "lower" }
		for i, d in ipairs(list) do
			local where = ""
			if #list == 2 then where = ", " .. (i == 1 and words[1] or words[3])
			elseif #list == 3 then where = ", " .. words[i]
			elseif #list > 3 then where = ", " .. i .. " of " .. #list .. (across and " from the left" or " from the top") end
			d.label = side .. " door" .. where
		end
	end
end

-- (the doors of this place with their names, for tests)
function doors_named_g()
	local ds = {}
	for _, d in ipairs(doors()) do ds[#ds + 1] = d end
	for _, d in ipairs(town_doors()) do ds[#ds + 1] = d end
	name_doors(ds)
	return ds
end
-- Doors named after where they go, by place ("map code#map id") and where the door stands.
-- (Observatory level 1: the main hall, map 4105, and the rooms round it, map 4106)
DOOR_NAMES_AT = {
	["X01M05#4105"] = {
		{ -3.25, -11.9, "prayer room door, left" },        -- the save point: the angel with a ponytail
		{ 3.25, -11.9, "prayer room door, right" },
		{ -12.5, 15.1, "study door" },                    -- bookshelves, a desk, stairs up
		{ 12.25, 15.1, "storeroom door" },                -- pots, a barrel, stairs up
		{ -17.0, 10.65, "door behind a wall, lower left" },
	},
}
-- every plain door of a place leads to the same one
DOOR_NAMES_ALL = { ["X01M05#4106"] = "door back to the main hall" }

-- What is behind each door and whether it is locked, from the game's own data: the names come
-- from dq9-access-doors.lua (made from the map files: the room on the other side, its stairs,
-- chests and shelves), and the locks from the game's trigger rules for each door, checked
-- against the story so far and the game's event flags, so a door that has been opened since
-- is not called locked.
pcall(dofile, DIR .. "dq9-access-doors.lua")
STORY_BASE = 0x02108844
KEY_NAMES = { "the Thief's Key", "the Magic Key", "the Ultimate Key" }
function story_now()
	local ch, st = u32(STORY_BASE + 0x488), u32(STORY_BASE + 0x48C)
	if ch < 1 or ch > 30 or st > 99 then ch, st = u8(STORY_BASE), u8(STORY_BASE + 1) end
	return ch * 100 + st
end
function flag_bit(addr, n)
	if n < 0 then return false end
	return (u8(addr + (n >> 3)) & (1 << (n & 7))) ~= 0
end
-- one condition of a door rule (code * 65536 + number)
function door_cond(c)
	local op, n = c // 65536, c % 65536
	local slot = u8(STORY_BASE + 0x332)
	if op == 0 then return flag_bit(STORY_BASE + 0x8C, n)
	elseif op == 1 then return not flag_bit(STORY_BASE + 0x8C, n)
	elseif op == 2 then return flag_bit(STORY_BASE + slot * 0x1C + 3, n)
	elseif op == 3 then return not flag_bit(STORY_BASE + slot * 0x1C + 3, n)
	elseif op == 4 then return flag_bit(STORY_BASE + slot * 0x1C + 0x10, n)
	elseif op == 5 then return not flag_bit(STORY_BASE + slot * 0x1C + 0x10, n)
	elseif op == 0x17 then return n == 0 or n == 2       -- playing on your own (not a guest)
	end
	return false        -- carrying a key, and the rest: not counted
end
-- is this door (its part numbers) locked right now? -> nil, or true and the key that opens it
function door_lock(mapid, gids)
	local db = DOOR_LOCKS and DOOR_LOCKS[mapid]
	if not db or not gids then return nil end
	local now = story_now()
	local locked, key = false, nil
	for _, gid in ipairs(gids) do
		local rules = db[gid]
		if rules then
			local first = nil
			for _, r in ipairs(rules) do
				if now >= r[1] and now <= r[2] then
					if not first then
						local ok = true
						for _, c in ipairs(r[3]) do if not door_cond(c) then ok = false break end end
						if ok then first = r[4] end
					end
					if r[4] == "u" and r[5] > 0 then key = math.min(key or 9, r[5]) end
				end
			end
			if first == "l" then locked = true end
		end
	end
	if not locked then return nil end
	return true, key
end
------------------------------------------------------------------------------ story guide ---
-- LT + Back (or Y on the keyboard): where to go next in the story, and how to open the locked
-- doors where you are. The step comes from the game's own story counter (chapter * 100 + step,
-- as used for the door locks) and, inside a chapter, from the places you have been and the
-- bosses you have beaten (kept in dq9-access-guide.txt). The words are a short walkthrough.
--   ch: the game's story chapters the step can be in; st: exact story numbers, when known;
--   areas: where the step happens (arriving there means you have got that far);
--   boss: beating it (the story moving on in that battle) means the step is done
GUIDE = {
	{ ch = { 1, 1 }, st = { 101, 101 }, areas = { "X01" }, text = "In the Observatory, talk to Apus Major on the upper floor, then to Aquila in the room to his left. If a room seems to have no way out, turn the camera." },
	{ ch = { 1, 1 }, areas = { "X01" }, text = "Go out of the south door on the Observatory's second floor and up the stairs to the great tree, Yggdrasil. Examine the tree, talk to Aquila, then go back to Apus Major. The woman by the portal on the ground floor sends you down to Angel Falls." },
	{ ch = { 1, 1 }, areas = { "M01" }, text = "In Angel Falls, gather benevolessence by helping people: clean out the stables, take the lost ring back to the old woman in the church, and talk to the lost spirit in the north east of the village. Then offer it to the tree." },
	{ ch = { 2, 2 }, areas = { "M01" }, text = "You have lost your wings. In Angel Falls, talk to the Mayor in the westernmost house, then eat and sleep at Erinn's inn on the east side, and leave the village." },
	{ ch = { 2, 2 }, areas = { "S01" }, text = "In the Mountain Pass, see the crashed Starflight Express, talk to Ivor by the landslide, then go back to the Mayor in Angel Falls." },
	{ ch = { 2, 2 }, areas = { "S04", "D01" }, boss = "Hammibal", text = "Go to the Hexagon. Level up to about 5 first. Examine the writing in the north, follow the ghost west to a switch, and go down to the lowest floor to find Patty and the boss. Then go back to Angel Falls: there is a scene at the inn, and a little statue hidden behind the inn to show to the ghost, then to Erinn." },
	{ ch = { 2, 2 }, st = { 206, 206 }, areas = { "S01" }, text = "Go to the Mountain Pass and examine the door of the Starflight Express. After the scene with Stella, carry on along the pass to Stornway." },
	{ ch = { 2, 3 }, st = { 207, 301 }, areas = { "C01" }, text = "In Stornway, talk to everyone at the inn, and get three companions from Patty at the inn's counter. Then read the sign in the middle of town about the King's request, and go up to the castle north of town to see King Schott in the throne room." },
	{ ch = { 3, 3 }, st = { 302, 302 }, areas = { "F02", "S02" }, boss = "Wight Knight", text = "Go to Loch Storn to deal with the Wight Knight. Leave Stornway over the small bridge north of town and keep heading north; the loch is in the clearing by the river." },
	{ ch = { 3, 3 }, st = { 303, 303 }, areas = {}, text = "Go back to Stornway and tell King Schott about the Wight Knight. He is in the throne room, up the middle stairs of the castle." },
	{ ch = { 3, 3 }, st = { 304, 304 }, areas = {}, text = "Princess Simona wants to talk to you in private. Her room is through the door from the throne room, then east along the outside walkway, the Princess's room door." },
	{ ch = { 3, 3 }, st = { 305, 305 }, areas = { "F63", "M02" }, text = "Go to Zere, a small village just west of Loch Storn, to find the princess's old maid, Alanna. Leave Stornway over the bridge north of town, head north towards Loch Storn, then west to Zere. In Zere, Alanna lives in the house in the far north east of the village; see her in the daytime." },
	{ ch = { 3, 3 }, st = { 306, 306 }, areas = { "F04", "D03" }, boss = "Morag", text = "Go to Brigadoom, north of Zere: go one area north into Doomingale Forest and find the big dark patch near the top of the map. Inside, the boss, Morag, is up the stairs in the northernmost part; her attack can paralyse, so keep your healer safe. Afterwards talk to the Wight Knight, then to Princess Simona." },
	{ ch = { 3, 4 }, st = { 307, 399 }, areas = {}, text = "Go back to King Schott in Stornway castle for your reward: use a chimaera wing to fly to Stornway, or walk, out of Brigadoom to the south, through Doomingale Forest to the south east into the open field, past Zere and on south east to Stornway. The King opens the treasure room and says the checkpoint to the north east is open. At Stornway's inn, talk to Erinn to get the Krak Pot for alchemy. Then go through the Eastern Checkpoint, north east of Stornway, and on north to Coffinwell." },
	{ ch = { 4, 4 }, areas = { "S03", "F05", "M03" }, text = "In Coffinwell, talk to the Mayor on the second floor of the big building in the north, then to Doctor Phlegming's wife in the house in the north west. Follow her to the door east of her house to find the doctor, then go back to the Mayor for the key to the Quarantomb." },
	{ ch = { 4, 4 }, areas = { "F06", "D04" }, boss = "Ragin' Contagion", text = "Go to the Quarantomb, west of Coffinwell. On the first floor, touch the red statue and the blue statue in the north east and north west; that opens the door near the entrance. Go on to the middle room, where a broken jar starts a scene, and talk to the big pink monster to fight the boss, the Ragin' Contagion, who attacks twice a turn." },
	{ ch = { 4, 5 }, areas = {}, text = "Back in Coffinwell, talk to the Mayor, Catarrhina, the Mayor again, rest at the inn, and the Mayor once more; then the ghost in the graveyard, Doctor Phlegming's laboratory door, the houses, and the inn. Then go to the Starflight Express in the Mountain Pass." },
	{ ch = { 5, 6 }, areas = { "S14", "X05" }, text = "At the Observatory, pray at the great tree to learn Zoom, the spell to fly back to places you have been. Then talk to Stella on the Starflight Express; it takes you to Newid Isle." },
	{ ch = { 5, 6 }, areas = { "F07", "X02" }, text = "On Newid Isle, go into Alltrades Abbey, north east of where you land. Talk to the priest on the north side of the first floor, then to the people at the bar downstairs, then back to the priest to learn the Bow party trick." },
	{ ch = { 5, 6 }, areas = { "T01" }, boss = "Master of Nu'un", text = "Go to the Tower of Trades, east of Alltrades Abbey. Do the Bow party trick in front of its door to get in. Climb to the seventh floor; the shining gate in the north leads to the boss, the Master of Nu'un, who attacks twice a turn. Then go back to the abbey and talk to the Jack of Alltrades in the north of the building, so you can change vocations." },
	{ ch = { 6, 7 }, areas = { "M05" }, text = "Go to Porth Llaffan, straight south of Alltrades Abbey. In the daytime, talk to the pink haired girl, Jona, on the shore, then try to leave town. After that: sleep at the inn, visit Jona at her house, talk to the ghost on the shore, then the Mayor, then the Mayor's son by the west gate, and leave by the west gate." },
	{ ch = { 7, 7 }, areas = { "D06", "S05" }, boss = "Lleviathan", text = "Follow the road west from Porth Llaffan to Tywll Cave on the shore. At the far end, on Cuddiedig Cliff, the boss is Lleviathan. Afterwards, in Porth Llaffan, talk to Jona on the shore, get on the boat and talk to the captain to set sail." },
	{ ch = { 7, 8 }, areas = { "S08", "F09", "F11", "M08" }, text = "The boat lands at Slurry Quay. Head south east to Dourbridge. In the daytime, cross the upper bridge for a scene, talk to the man in the northernmost building, then to Cap'n Max Meddlin in the tent in the north east; he gives you the Thief's Key for mini medals." },
	{ ch = { 8, 9 }, areas = { "F12", "M09", "F10", "S12" }, text = "Leave Dourbridge going east, then south, across the Lonely Plains to Bloomingdale, to the south west. Then go to the Heights of Loneliness, north east of Bloomingdale." },
	{ ch = { 8, 9 }, areas = { "D07", "M07" }, boss = "Garth Goyle", text = "Climb the Heights of Loneliness to Zere Rocks at the top. Talk to the slime in the building in the north east, then leave to meet the boss, Garth Goyle. Afterwards a ghost goes into the basement next to the slime's hut; talk to it, then go back to Bloomingdale." },
	{ ch = { 9, 9 }, areas = {}, text = "In Bloomingdale: talk to the old man at the harbour; in the daytime visit Marion at the mansion in the north; talk to the old woman in the small house in the west; talk to Randolph at the armour shop in the middle of town; talk to the ghost and follow it; then examine the gravestone in the south." },
	{ ch = { 9, 10 }, areas = { "D09" }, boss = "Tyrantula", text = "Go to the Bad Cave, north of Bloomingdale. On the first floor, sit in the lone chair at the middle table; a kidnapper comes out and puts down a ladder. The boss at the end is Tyrantula. Then examine the southern gravestone in Bloomingdale again; Marion's boat at the harbour is now yours to sail." },
	{ ch = { 9, 11 }, areas = { "C02", "F15" }, text = "Sail to Gleeba, the desert town on the island to the north. Agree to help the Chancellor on the second floor of the palace. Use the Clap party trick by the north western tree in the shade outside the palace to scare out a lizard, and give it to the Chancellor. Talk to the soldier at the bath on the first floor and the woman south of the bath door. On the roof, go round the big oval building and in from the north to get the Magic Key. Then talk to the man on the fountain and jump into the fountain." },
	{ ch = { 9, 11 }, areas = { "D08" }, boss = "Grand Lizzier", text = "Follow the overgrown lizard into the well, down into the Plumbed Depths. The Queen is on the third floor down, and the boss is the Grand Lizzier. Afterwards, the waterfall in the west of Gleeba hides an item." },
	{ ch = { 10, 11 }, areas = { "M10", "S06", "F21" }, text = "Sail to Batsureg, on the island north of Gleeba. Talk to Chief Batkhaan in the north western yurt, go to the Hunters' Yurts north of town and examine the northern one, then talk to Batzorig in the southern yurt. Then go north to Mount Ulbaruun, where Batzorig is in a cave to the west." },
	{ ch = { 10, 11 }, areas = { "F23", "S11", "F22", "D12" }, text = "Talk to the ghost in the cave on Mount Ulbaruun, then go east to Mount Ulzuun. In its north, go into the cave, Gerzuun; the ghost opens the door. Find the Bodura grass at the underground spring. Then go back to Batsureg, rest at the inn, and talk to Batzorig at the southern Hunters' Yurt." },
	{ ch = { 10, 11 }, areas = {}, boss = "Larstastnaras", text = "Heal up, then step onto the raised ground in the middle of Batsureg to fight the boss, Larstastnaras. Afterwards rest, and go back to the grave where you met Batzorig and his ape." },
	{ ch = { 11, 12 }, areas = { "F20", "F16", "M11" }, text = "Go to Swinedimples Academy: from the Urdus Marshland head east to Hermany, then north twice. Talk to the man at the gate. In the east dormitory, listen to the students on the second floor, then go into their room. Talk to Fred behind the western house, then rest in your dormitory room. At night, examine the statue on the third floor balcony of the main building." },
	{ ch = { 12, 12 }, areas = { "D13" }, boss = "Dreadmaster", text = "Go to the old underground school in the north east of the academy grounds. On the second floor down, talk to the ghost teacher, the Dreadmaster, to fight him. Then fly to Alltrades Abbey and go to the glimmering tree in the west to ride the Starflight Express to the Observatory." },
	{ ch = { 12, 13 }, areas = { "M12", "F26", "H17" }, text = "In Wormwood Creek, buy new gear, rest at the inn until night, then talk to the Mayor at the church. Then go to the cave north of town, squeeze through the small hole in the wall for the Lucida Shard, and talk to Wallace. On the way out the ghost Serena asks for something from town: examine the guardian statue by the weapon shop, then the stone in the church's north east corner, and take her the Serene Necklace." },
	{ ch = { 13, 13 }, areas = { "F27", "H19", "D14" }, boss = "Gadrongo", text = "From Wormwood Creek go north, then west, to Western Wormwood and the Bowhole. The boss at the bottom is Gadrongo, whose attack can paralyse. Take the Wyrmlight Bow from the pedestal." },
	{ ch = { 13, 14 }, areas = { "F28", "F29", "F30", "F32", "F33", "M13" }, text = "Go west from Wormwood Creek to Wormwood Canyon, stand on the dragon's face and fire the Wyrmlight Bow to make a bridge of light. Go round the mountains to Upover, in the middle of the Wyrmsmaw region. Talk to the Mayor in the north east, then the guard outside the cave to the right of the Mayor's house." },
	{ ch = { 13, 14 }, areas = { "D16" }, boss = "Greygnarl", text = "Go through the Magmaroo, five floors, to the boss, Greygnarl. Afterwards, leave the area for a scene and go back to Upover. Talk to the man in purple armour at the town's entrance." },
	{ ch = { 14, 14 }, areas = {}, text = "Leave your companions at Stornway's inn: the next part is on your own. In Upover, talk to the old woman at the Magmaroo entrance; she wants Drunken Dragon from the brewery down the stairs west of her. Take it to her, then fly to Magmaroo Peak, beat the beast on the southern path, and talk to Greygnarl. Wear the dragon warrior armour he gives you and ride him." },
	{ ch = { 14, 14 }, areas = { "S07" }, text = "In Gortress, examine the door of your cell, go upstairs and talk to Sterling. Visit the graveyard, examine the barrier, and talk to the soldiers in the east corner and the south corner, then Sterling by the middle bridge. The next day, go to the gallows in the north. Then fly to Stornway to get your companions back." },
	{ ch = { 14, 14 }, areas = {}, boss = "Goreham-Hogg", text = "Back in Gortress, go up the watch tower, beat the armour guarding the shield generator and turn it off. Sterling opens the way to the boss, Goreham-Hogg, on the first floor; heal at the blue light first. His chest holds the Ultimate Key: use it on the prison doors downstairs, then talk to Sterling." },
	{ ch = { 14, 15 }, areas = { "X01", "X03" }, text = "At the Observatory, talk to Apus Major on the second floor, then go up to the fourth floor, talk to him again by the Starflight Express and board it. In the Realm of the Almighty, go to the top of the second floor, step into the light and offer the fyggs. Then talk to Stella and Sterling, and take the train to Alltrades Abbey." },
	{ ch = { 15, 16 }, areas = { "F34", "C04" }, boss = "Godwyn", text = "Travel east from Gortress through the Gittish Empire to Gittingham Palace. Bosses: Hootingham-Gore with two Bad Karmours at the entrance (beat the Karmours first, and use attacks, not spells, on him), Goresby-Purrvis at the top of the outdoor part, then King Godwyn upstairs, who attacks twice a turn and removes your buffs: bring Multiheal or two healers." },
	{ ch = { 16, 17 }, areas = { "D17" }, text = "On the second floor of Gittingham Palace, the sealed door is now open. Go through it into the Oubliette, down to the sixth floor below, where Corvus is chained in the middle room. Free him; the battle you cannot win and a long scene follow. At the Observatory, take the fygg from the great tree, board the Starflight Express, talk to Sterling, eat the fygg, and talk to him again; the Realm of the Mighty is the last dungeon." },
	{ ch = { 17, 18 }, areas = { "X04" }, boss = "Corvus", text = "The Realm of the Mighty: level 43 or more is a good idea. Goreham-Hogg is on the third floor, Hootingham-Gore on the eighth; at the fork after him the main way is west. Jump into the purple pit at the end of the red carpet. Then Goresby-Purrvis, and Corvus on the throne. Go back out of the double red doors; at the second one a scene drops you in the middle, where touching the big glowing red ball starts Barbarus. Heal first: after him comes Corvus, the last boss. Keep Multiheal and Magic Barrier going." },
	{ ch = { 19, 99 }, areas = {}, text = "The story is finished. Next: in Porth Llaffan, find Jona in the shack in the far south east, stay at the inn until night, talk to the ghost on the shore and say no. Then wear a flowing dress from Wormwood Creek, a watermaul wand from Gleeba and a silver shield from Stornway, see Jona, and follow her to Tywll Cave to fight Lleviathan again. You get Sterling's Whistle, to call the Starflight Express anywhere and fly to new places. Treasure map grottos are the main thing to do after the story." },
}
-- the keys and where you get them
KEY_FROM = {
	{ ch = 8, text = "Cap'n Max Meddlin gives it to you in his tent in the north east of Dourbridge, for mini medals" },
	{ ch = 10, text = "it is on the roof of Gleeba's palace, inside the big oval building, which you go into from the north" },
	{ ch = 14, text = "it is in the chest you get after beating Goreham-Hogg in Gortress" },
}
-- doors the story keeps shut, by where they are: when they open
STORY_DOORS = {
	{ code = "C01", label = "treasure room", text = "King Schott opens it as your reward, once you have dealt with the Wight Knight's business at Brigadoom" },
}
guide = { prog = {}, loaded = false, boss = nil, boss_story = 0, boss_step = nil }
GUIDE_FILE = DIR .. "dq9-access-guide.txt"
function guide_load()
	guide.loaded = true
	local f = io.open(GUIDE_FILE, "r")
	if not f then return end
	for line in f:lines() do
		local ch, idx, st = line:match("^(%d+)=(%d+)@(%d+)")
		if ch then guide.prog[tonumber(ch)] = { idx = tonumber(idx), st = tonumber(st) } end
	end
	f:close()
end
function guide_save()
	local f = io.open(GUIDE_FILE, "w")
	if not f then return end
	local ks = {}
	for ch in pairs(guide.prog) do ks[#ks + 1] = ch end
	table.sort(ks)
	for _, ch in ipairs(ks) do f:write(ch, "=", guide.prog[ch].idx, "@", guide.prog[ch].st, "\n") end
	f:close()
end
-- you have got as far as step idx (kept per chapter, with the story number at the time, so going
-- back to an older save does not count it)
function guide_reach(idx)
	if not guide.loaded then guide_load() end
	local now = story_now()
	local ch = now // 100
	local p = guide.prog[ch]
	if p and p.st <= now and p.idx >= idx then return end
	guide.prog[ch] = { idx = idx, st = now }
	guide_save()
end
local function guide_has(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
-- the step you are on now
function guide_step()
	if not guide.loaded then guide_load() end
	local now = story_now()
	local ch = now // 100
	local cands = {}
	for i, s in ipairs(GUIDE) do
		if ch >= s.ch[1] and ch <= s.ch[2] then cands[#cands + 1] = i end
	end
	if #cands == 0 then
		-- a chapter not in the guide: the nearest step before it
		for i, s in ipairs(GUIDE) do if s.ch[1] <= ch then cands = { i } end end
		if #cands == 0 then cands = { 1 } end
	end
	-- exactly known from the story number
	for _, i in ipairs(cands) do
		local s = GUIDE[i]
		if s.st and now >= s.st[1] and now <= s.st[2] then return i end
	end
	-- how far you have got in this chapter (and the chapters before, for steps that run on)
	local best = cands[1]
	for c = ch - 1, ch do
		local p = guide.prog[c]
		if p and p.st <= now and p.idx >= best and guide_has(cands, p.idx) then best = p.idx end
	end
	-- (a step pinned to story numbers you are past is done)
	while GUIDE[best].st and now > GUIDE[best].st[2] and guide_has(cands, best + 1) do best = best + 1 end
	-- where you are now: a later step of this chapter that happens here
	local code = (map_code() or ""):sub(1, 3)
	for _, i in ipairs(cands) do
		if i > best and guide_has(GUIDE[i].areas, code) and not (GUIDE[i].st and now > GUIDE[i].st[2]) then best = i break end
	end
	return best
end
-- every so often: arriving somewhere moves the guide on
guide_last_code = nil
function guide_tick()
	if frame % 60 ~= 0 then return end
	local code = (map_code() or ""):sub(1, 3)
	if code ~= "" and code ~= guide_last_code and not in_battle() then
		guide_last_code = code
		local i = guide_step()
		if i and guide_has(GUIDE[i].areas, code) then guide_reach(i) end
	end
	-- a boss beaten: the story moved on during that battle
	if guide.boss and not in_battle() and frame - battle_seen_frame > 120 then
		if story_now() > guide.boss_story then guide_reach(guide.boss_step + 1) end
		guide.boss = nil
	end
end
-- a battle starting ("Morag draws near!"): is it a boss of the guide?
function guide_hear(text)
	if guide.boss or not text then return end
	local who = text:match("^(.-) draws? near!") or text:match("^(.-) appears?!")
	if not who then return end
	who = who:gsub("^[Tt]he ", "")
	for i, s in ipairs(GUIDE) do
		if s.boss and who:find(s.boss, 1, true) then
			guide.boss, guide.boss_story, guide.boss_step = s.boss, story_now(), i
			return
		end
	end
end
-- what the locked doors here need
function guide_doors(skip)
	local out = {}
	local ok, list = pcall(build_nearby_g)
	if not ok or type(list) ~= "table" then return out end
	local ch = story_now() // 100
	local seen = {}
	for _, d in ipairs(list) do
		local skipped = false
		for _, gid in ipairs(d.gids or {}) do if (skip and skip[gid]) or seen["g" .. gid] then skipped = true end end
		if d.kind == 1 and d.locked and not seen[d.label] and not skipped then
			seen[d.label] = true
			for _, gid in ipairs(d.gids or {}) do seen["g" .. gid] = true end
			local name = d.label:gsub(", opens with .*$", ""):gsub(", locked from this side$", ""):gsub(", locked$", ""):gsub("^locked ", "")
			if d.lock_key and KEY_FROM[d.lock_key] then
				local k = KEY_FROM[d.lock_key]
				local key = KEY_NAMES[d.lock_key]
				if ch >= k.ch + 1 then
					out[#out + 1] = name .. " opens with " .. key .. ", which you should have by now: " .. k.text .. ". Walk into the door with it to open it."
				elseif ch == k.ch then
					out[#out + 1] = name .. " opens with " .. key .. ": " .. k.text .. "."
				else
					out[#out + 1] = name .. " opens with " .. key .. ", which you get later in the story: " .. k.text .. "."
				end
			elseif door_opens_inside(u16(MAPID), d.gids) then
				out[#out + 1] = name:gsub(", left$", ""):gsub(", right$", "") .. " is locked from this side: you unlock it from its other side, so find the way round to there."
			else
				local why = nil
				local code = map_code() or ""
				for _, s in ipairs(STORY_DOORS) do
					if code:sub(1, #s.code) == s.code and name:find(s.label, 1, true) then why = s.text end
				end
				out[#out + 1] = name .. " is kept shut by the story for now" .. (why and (": " .. why) or "; it opens later") .. "."
			end
		end
	end
	return out
end
-- Step by step through a dungeon, by the part of it you are in (the map), until its boss is
-- beaten (the story number moves past "before"). Door notes: what opens a locked door (by map
-- number and door part number). The words are from walkthroughs of each dungeon.
DUNGEON_GUIDE = {
	D03 = { name = "Brigadoom", before = 306,
		M01 = {
			"You are in Brigadoom's ruins; you came in at the south. Optional: a chest with a trailblazing bandana, good for a healer, on top of the eastern tower. From down here it is the treasure chest in the items list that says higher up. To get to it, go in through the eastern tower door, then take the exit outside at the top of the stairs inside; that brings you out on top of the tower, next to the chest.",
			"The way on is underground. In the exits list there are two exits to the basement: take the one up and to the left of the entrance, on the north west side of the ruins, just north of the way into the western tower.",
			"The double door on the west side, the bottom door, is up a few steps and locked from this side; the exit to western tower in the exits list is behind it. You unlock it from its other side: through the basement into the western tower, then out of the tower's stairs to the outside. After that it is a short cut in and out, to go back to Zere to rest.",
		},
		-- (the double door unlocked: the way on is through it and up onto the walls)
		M01_open = {
			"The double door on the west side is open. The way on is through it: go up the steps to the double door, through it, and follow the walkway north. It climbs up onto the roof of the northern part of the ruins.",
			"At the north end of the roof is the way into the northern tower: pick exit to northern tower throne room in the exits list; auto walk can take you all the way there from the ruins. Optional: pots on the east side of the roof.",
			"Inside, you come to the second floor of the northern tower, where Morag is. Press this again there for the steps.",
		},
		M02 = {
			"The north western tower: a side room with a treasure chest. It is not on the way to Morag. Go back out, through the double door on the west side and along the walkway north, up onto the roof, to the exit to northern tower throne room.",
		},
		M03 = {
			"The basement. Optional: go north, then east, and follow the eastern path to two chests, with clogs and a mini medal.",
			"Then come back until you can go south. The stairs up on the left lead into the western tower, the way on: pick exit to western tower in the exits list.",
			"Going on south instead leads to a chest with a belle cap, and then a locked door that needs the Ultimate Key, which you only get much later in the story.",
		},
		M05 = {
			"The western tower. Optional: the drawers in the north and a pot in the south hold items. The way on is the stairs to the outside, next to where you came in: pick it in the exits list.",
			"They bring you out on the walkway behind the double door. The double door is just south of you: walk into it from this side to unlock it, so it is a short cut back to the ruins and Zere.",
			"Then follow the walkway north. It climbs up onto the roof of the northern part of the ruins; at its north end, pick exit to northern tower throne room in the exits list, the way into the northern tower, where Morag is.",
		},
		M06 = {
			"The second floor of the northern tower. Optional: go east to the stairs down to the princess's room, with a chest holding a gold bracer, and a portrait, a letter and a diary to read.",
			"Then go round the room clockwise until you find a door to the north: the throne room, where Morag is. Heal and get ready before you go in.",
			"Talk to Morag to fight her. She mostly attacks with her knife, and sometimes casts a spell like Crack or dances; keep your healer's HP up. A mage can cast Sap on her for the first couple of turns. After the fight, talk to the Wight Knight, then to Princess Simona.",
		},
		M07 = {
			"The princess's room. Open the chest for a gold bracer, and examine the portrait, the letter on the bookshelf and the diary.",
			"Then go back up the stairs and round the floor clockwise to the door in the north: the throne room, where Morag is.",
		},
		M04 = {
			"The eastern tower. The chest is not in here: it is outside on top of the tower. Pick exit outside in the exits list, at the top of the stairs a few steps up, and walk into it. You come out on the tower top; the treasure chest is then in the items list, right by you. Open it for the trailblazing bandana.",
			"Then come back in through the same way, go out of the door outside at the bottom, and head for the stairs down to the basement on the north west side of the ruins.",
		},
		doors = { [7301] = { [8] = "it opens from the inside: you unlock it from the western tower. Go down to the basement, up into the western tower, then south to this door; after that it is a short cut." } },
	},
}
function dungeon_guide()
	-- (the map's own number says which part it is: the code in memory is the file's, and the
	-- eastern tower's file is "D03M02")
	local m = MAPIDS[u16(MAPID)]
	local code = m and m[1] or map_code() or ""
	local g = DUNGEON_GUIDE[code:sub(1, 3)]
	if not g or story_now() > g.before then return nil end
	local sub = code:sub(4, 6)
	if sub == "" then sub = "M01" end
	local part = g[sub]
	if g[sub .. "_open"] and code_unlocked_shortcut(g) then part, code = g[sub .. "_open"], code .. "open" end
	if not part then return nil end
	return part, g, code
end
-- notes for this dungeon's locked doors, once per door
function dungeon_door_notes(g)
	local out = {}
	local mapid = u16(MAPID)
	local notes = g.doors and g.doors[mapid]
	if not notes then return out end
	local ok, list = pcall(build_nearby_g)
	if not ok or type(list) ~= "table" then return out end
	local done = {}
	for _, d in ipairs(list) do
		if d.kind == 1 and d.locked and d.gids then
			for _, gid in ipairs(d.gids) do
				if notes[gid] and not done[gid] then
					done[gid] = true
					local name = d.label:gsub(", opens with .*$", ""):gsub(", locked from this side$", ""):gsub(", locked$", ""):gsub("^locked ", ""):gsub(", left$", ""):gsub(", right$", "")
					out[#out + 1] = name .. ": " .. notes[gid]
				end
			end
		end
	end
	return out, done
end
-- each press: the next step of the part of the dungeon you are in; after the last one, the
-- story's next step; then round again. A new part starts from its first step.
guide_press = { code = nil, n = 0 }
function say_guide()
	local part, g, code = dungeon_guide()
	if part then
		if guide_press.code ~= code then guide_press.code, guide_press.n = code, 0 end
		guide_press.n = guide_press.n + 1
		if guide_press.n <= #part then
			local i = guide_press.n
			local text = part[i]
			-- (the short cut already unlocked: no need to unlock it)
			if code_unlocked_shortcut(g) and text:find("walk into it from this side to unlock it", 1, true) then
				text = "They bring you out on the walkway behind the double door, which is unlocked now: your short cut back to the ruins and Zere."
			end
			local head = (i == 1 and (g.name .. " walkthrough, ") or "") .. "step " .. i .. " of " .. #part .. ". "
			local tail = ""
			if i == #part then
				-- (doors this dungeon's steps already explain are left out)
				local _, done = dungeon_door_notes(g)
				local notes = guide_doors(done or {})
				if #notes > 0 then tail = " Other locked doors here: " .. table.concat(notes, " ") end
				tail = tail .. " Press again for the story's next step."
			else
				tail = " Press again for the next step."
			end
			say(head .. text .. tail, true)
			return
		end
		guide_press.n = 0
	end
	local i = guide_step()
	local s = GUIDE[i]
	local parts = { "Next in the story: " .. s.text }
	local doors = guide_doors()
	if #doors > 0 then parts[#parts + 1] = "Locked doors here: " .. table.concat(doors, " ") end
	say(table.concat(parts, " "), true)
end
-- Brigadoom's short cut: the door's lock rule says flag 126 opens it
function code_unlocked_shortcut(g)
	if g.name ~= "Brigadoom" then return false end
	return flag_bit(STORY_BASE + 0x8C, 126)
end
guide_step_g, guide_doors_g = guide_step, guide_doors
-- a locked door you unlock from its other side (a rule that unlocks it with no key)
function door_opens_inside(mapid, gids)
	local db = DOOR_LOCKS and DOOR_LOCKS[mapid]
	if not db or not gids then return false end
	local now = story_now()
	for _, gid in ipairs(gids) do
		for _, r in ipairs(db[gid] or {}) do
			if now >= r[1] and now <= r[2] and r[4] == "u" and r[5] == 0 then return true end
		end
	end
	return false
end
-- the door part numbers of the door nearest a spot (a double door has two parts); id: the place
-- it leads to, when known
function door_gids_at(x, z, r, id)
	local out = {}
	local base, n = u32(GIMMICK_PTR), u32(GIMMICK_COUNT)
	if n == 0 or n > 200 or not inram(base, n * 0x74) then return out end
	local bx, bz, bd = nil, nil, r
	for k = 0, n - 1 do
		local g = base + k * 0x74
		if u32(g + 4) == 2 and (not id or u16(g + 0x30) == id) then
			local gx, gz = s32(g + 8) / 4096, s32(g + 0x10) / 4096
			local dd = math.max(math.abs(gx - x), math.abs(gz - z))
			if dd < bd then bx, bz, bd = gx, gz, dd end
		end
	end
	if not bx then return out end
	for k = 0, n - 1 do
		local g = base + k * 0x74
		if u32(g + 4) == 2 and math.abs(s32(g + 8) / 4096 - bx) < 0.6 and math.abs(s32(g + 0x10) / 4096 - bz) < 0.6 then
			out[#out + 1] = u8(g + 0x2D)
		end
	end
	return out
end
-- side words for doors that would otherwise have the same name: along a line for two or three,
-- by side of the place for more ("top, left")
function tell_apart(list)
	if #list < 2 then return end
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, d in ipairs(list) do
		x0, x1 = math.min(x0, d.x), math.max(x1, d.x)
		z0, z1 = math.min(z0, d.z), math.max(z1, d.z)
	end
	if #list <= 3 then
		local across = (x1 - x0) >= (z1 - z0)
		table.sort(list, function(a, b) if across then return a.x < b.x else return a.z < b.z end end)
		local words = across and { "left", "middle", "right" } or { "upper", "middle", "lower" }
		for i, d in ipairs(list) do
			d.label = d.label .. ", " .. ((#list == 2 and i == 2) and words[3] or words[i])
		end
		return
	end
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local sides = { top = {}, bottom = {}, left = {}, right = {} }
	for _, d in ipairs(list) do
		local dx, dz = d.x - cx, d.z - cz
		local side
		if math.abs(dx) > math.abs(dz) then side = dx < 0 and "left" or "right" else side = dz < 0 and "top" or "bottom" end
		table.insert(sides[side], d)
	end
	for side, sl in pairs(sides) do
		local across = (side == "top" or side == "bottom")
		table.sort(sl, function(a, b) if across then return a.x < b.x else return a.z < b.z end end)
		local words = across and { "left", "middle", "right" } or { "upper", "middle", "lower" }
		for i, d in ipairs(sl) do
			local where = ""
			if #sl == 2 then where = ", " .. (i == 1 and words[1] or words[3])
			elseif #sl == 3 then where = ", " .. words[i]
			elseif #sl > 3 then where = ", " .. i .. " of " .. #sl end
			d.label = d.label .. ", " .. side .. where
		end
	end
end
-- all of the naming: by side, after where they lead, hand-made names, told apart, and locked
function name_doors(ds)
	name_doors_by_side(ds)
	local mapid = u16(MAPID)
	local dest = DOOR_DEST and DOOR_DEST[mapid]
	for _, d in ipairs(ds) do
		d.dest_label = nil
		-- (a name the game shows, or one you have learned by going in, is kept; the game's
		-- builders' names such as "House A" are not)
		if d.kind == 1 and dest and (d.base_label == "door" or d.base_label:match("^House [%w]+ door$")) then
			local best, bd = nil, 1.3
			for _, e in ipairs(dest) do
				local dd = math.max(math.abs(d.x - e[1]), math.abs(d.z - e[2]))
				if d.wx then dd = math.min(dd, math.max(math.abs(d.wx - e[1]), math.abs(d.wz - e[2]))) end
				if dd < bd then best, bd = e[3], dd end
			end
			d.dest_label = best
		end
	end
	-- a door inside this map: the room on the far side from you
	local sides = DOOR_SIDES and DOOR_SIDES[mapid]
	local px, _, pz = player_pos()
	if sides and px then
		-- the part of the map you can walk to: a side in it is the side you are on
		local R = nil
		local nv = nav_ready()
		if nv and not nv.reach_big then
			local ok, r = pcall(reach_region, nv, px, select(2, player_pos()), pz, true)
			if ok and r and not r.truncated then R = r end
		end
		for _, d in ipairs(ds) do
			if d.kind == 1 and not d.dest_label and d.base_label == "door" then
				for _, e in ipairs(sides) do
					if math.abs(d.x - e[1]) < 1.0 and math.abs(d.z - e[2]) < 1.0 then
						local ina = R and reach_near(R, e[3], e[4]) < 0.8
						local inb = R and reach_near(R, e[6], e[7]) < 0.8
						if ina and not inb then d.dest_label = e[8]
						elseif inb and not ina then d.dest_label = e[5]
						elseif R then
							-- a door somewhere else: name the room behind it, the smaller of the two
							d.dest_label = (#e[5] > 0 and e[5]:match("big room")) and e[8] or e[5]
						else
							local da = (px - e[3]) ^ 2 + (pz - e[4]) ^ 2
							local db = (px - e[6]) ^ 2 + (pz - e[7]) ^ 2
							d.dest_label = da > db and e[5] or e[8]
						end
						break
					end
				end
			end
		end
	end
	-- doors named after where they lead: the plain side names are only for the rest
	local named = {}
	for _, d in ipairs(ds) do if d.dest_label then d.label = d.dest_label named[#named + 1] = d end end
	rename_doors(ds)
	-- the same name twice or more: say where each one is (among the ones you can walk to, and
	-- apart from that among the ones in other rooms)
	if reach_mark then pcall(reach_mark, ds) end
	local groups = {}
	for _, d in ipairs(ds) do
		if d.kind == 1 then
			local k = d.label .. (d.unreachable and "#far" or "")
			groups[k] = groups[k] or {} table.insert(groups[k], d)
		end
	end
	for _, list in pairs(groups) do tell_apart(list) end
	-- locked now?
	for _, d in ipairs(ds) do
		if d.kind == 1 then
			local gids = d.gids
			if not gids then
				if d.gdoor then gids = door_gids_at(d.x, d.z, 0.6)
				else gids = door_gids_at(d.wx or d.x, d.wz or d.z, 2.6, d.id) end
				d.gids = gids
			end
			local locked, key = door_lock(mapid, gids)
			d.locked, d.lock_key = locked, key
			if locked then
				if d.label:match("^door") then d.label = "locked " .. d.label else d.label = d.label .. ", locked" end
				if key then d.label = d.label .. ", opens with " .. KEY_NAMES[key]
				elseif door_opens_inside(mapid, gids) then
					-- (a door you unlock from its other side: say so)
					d.inside_lock = true
					d.label = d.label:gsub(", locked$", ", locked from this side"):gsub("^locked ", "") .. (d.label:match("^locked ") and ", locked from this side" or "")
				end
			end
		end
	end
end
function rename_doors(ds)
	local key = (map_code() or ""):sub(1, 6) .. "#" .. u16(MAPID)
	local list, all = DOOR_NAMES_AT[key], DOOR_NAMES_ALL[key]
	if not list and not all then return end
	for _, d in ipairs(ds) do
		if d.kind == 1 then
			local named = false
			for _, e in ipairs(list or {}) do
				if math.abs(d.x - e[1]) < 1.0 and math.abs(d.z - e[2]) < 1.0 then d.label, named = e[3], true break end
			end
			if not named and all and d.label ~= "door outside" and not d.label:match("^stairs") then
				d.label = all
			end
		end
	end
end
local function build_nearby()
	local px, _, pz = player_pos()
	if not px then return {} end
	local list = characters()
	for _, m in ipairs(monsters()) do list[#list + 1] = m end
	for _, m in ipairs(map_items()) do list[#list + 1] = m end
	for _, m in ipairs(sparkles()) do list[#list + 1] = m end
	local ds = {}
	for _, d in ipairs(doors()) do ds[#ds + 1] = d end
	for _, d in ipairs(town_doors()) do ds[#ds + 1] = d end
	name_doors(ds)
	-- many exits into the same place (the archways all round a tower): list only the nearest
	local same = {}
	for _, d in ipairs(ds) do
		if d.kind == 0 then same[d.id] = (same[d.id] or 0) + 1 end
	end
	local nearest = {}
	for _, d in ipairs(ds) do
		if d.kind == 0 and same[d.id] >= 3 then
			local dd = (d.x - px) ^ 2 + (d.z - pz) ^ 2
			if not nearest[d.id] or dd < nearest[d.id][2] then nearest[d.id] = { d, dd } end
		end
	end
	for _, d in ipairs(ds) do
		d.exit_label = d.exit_label or d.label
		if d.kind == 0 and same[d.id] >= 3 then
			if nearest[d.id][1] == d then
				d.label = d.exit_label .. ", nearest of " .. same[d.id]
				list[#list + 1] = d
			end
		else
			list[#list + 1] = d
		end
	end
	local key = place_key()
	for _, p in ipairs(places) do
		if p.code == key and p.kind == "mark" then list[#list + 1] = { label = p.label, x = p.x, z = p.z, mark = true } end
	end
	for _, it in ipairs(list) do it.d = math.sqrt((it.x - px) ^ 2 + (it.z - pz) ^ 2) end
	if reach_mark then reach_mark(list) end
	-- things you can walk to first, nearest first; then the ones in other rooms
	table.sort(list, function(a, b)
		if (a.unreachable or false) ~= (b.unreachable or false) then return not a.unreachable end
		return a.d < b.d
	end)
	return list
end
function build_nearby_g() return build_nearby() end

local sel_item = nil
local function announce_selected()
	local it = nearby[selected]
	if not it then say("Nothing nearby.") return end
	sel_item = it
	it.code = map_code()
	say(it.label .. ", " .. directions_to(it.x, it.z) .. (it.unreachable and ((it.level and ", " .. it.level or "") .. ", no way there from here") or "") .. ". " .. selected .. " of " .. #nearby)
end

-- Categories for the nearby list: N and B (or the controller) only go through the chosen one.
CATEGORIES = { "People", "Monsters", "Items", "Sparkly spots", "Doors", "Exits", "Objects", "Marks" }   -- (Events taken out: not useful)
-- these are always offered, even when there are none here, so you know they exist
ALWAYS_SHOWN = { ["Monsters"] = true, ["Sparkly spots"] = true }
local category = 1
local function category_of(it)
	if it.monster then return "Monsters" end
	if it.sparkle then return "Sparkly spots" end
	if it.item then return "Items" end
	if it.event then return "Events" end
	if it.obj then return it.thing and "Objects" or "People" end
	if it.kind == 1 then return "Doors" end
	if it.kind == 0 then return "Exits" end
	return "Marks"
end
local function nearby_in_category(cat)
	local all = build_nearby()
	local out = {}
	for _, it in ipairs(all) do
		if category_of(it) == CATEGORIES[cat] then out[#out + 1] = it end
	end
	return out
end

local function step_nearby(delta)
	nearby = nearby_in_category(category)
	if #nearby == 0 then
		selected = 0 sel_item = nil
		say("No " .. CATEGORIES[category]:lower() .. " nearby.")
		return
	end
	-- keep your place in the list even though it is re-sorted by distance every time
	local at = 0
	if sel_item then
		-- the same thing again: same name, and the closest to where it was (people move a little)
		local bestd = 2.5
		for i, it in ipairs(nearby) do
			local d = math.abs(it.x - sel_item.x) + math.abs(it.z - sel_item.z)
			if it.label == sel_item.label and d < bestd then at, bestd = i, d end
		end
	end
	selected = at + delta
	if selected < 1 then selected = #nearby elseif selected > #nearby then selected = 1 end
	announce_selected()
end

-- Next or previous category, skipping the ones with nothing in them right now.
local function step_category(delta)
	for _ = 1, #CATEGORIES do
		category = (category - 1 + delta) % #CATEGORIES + 1
		local items = nearby_in_category(category)
		local n = #items
		if n > 0 or ALWAYS_SHOWN[CATEGORIES[category]] then
			selected, sel_item = 0, nil
			local away = 0
			for _, it in ipairs(items) do if it.unreachable then away = away + 1 end end
			local note = ""
			-- (out in the open there are no rooms: across water or up a cliff)
			local code = map_code() or ""
			local open = code:match("^F") or code:match("^S")
			if away == n and n > 0 then note = open and ", all out of reach from here" or ", all in other rooms, no way there from here"
			elseif away > 0 then note = ", " .. away .. (open and " of them out of reach from here" or " of them in other rooms") end
			say(CATEGORIES[category] .. ", " .. (n > 0 and n or "none here right now") .. note, true)
			return
		end
	end
end

-- Walk there for you: the script holds the D-pad toward the thing you picked. A door is walked
-- into from the front: the script first goes to a spot just outside it, then straight in. When
-- something is in the way it steps to one side and tries again. Any controller button takes over.
------------------------------------------------------------------------------ path finding --
-- The game's own collision walls for every map come from dq9-access-maps.bin (taken from the
-- ROM). With them the script plans a real route around cliffs, fences and houses.
NAV_FILE = DIR .. "dq9-access-maps.bin"
local nav_index = nil          -- name -> { off, n }
local nav = nil                -- walls and floors of the current map
local nav_cache = nil
NB = 2.0                 -- bucket size in world units
NCELL = 0.5              -- path grid size

local function nav_load_index()
	if nav_index then return nav_index end
	nav_index = {}
	local f = io.open(NAV_FILE, "rb")
	if not f then return nav_index end
	local head = f:read(8)
	if head and head:sub(1, 4) == "DQ9N" then
		local count = string.unpack("<I4", head, 5)
		local idx = f:read(count * 16) or ""
		for i = 0, count - 1 do
			local name = idx:sub(i * 16 + 1, i * 16 + 8)
			local off, n, v = string.unpack("<I4I2I2", idx, i * 16 + 9)
			nav_index[name] = { off = off, n = n, scale = 2 ^ (12 - v) }
		end
	end
	f:close()
	return nav_index
end

local function bucket_add(t, x0, z0, x1, z1, v)
	for i = math.floor(x0 / NB), math.floor(x1 / NB) do
		for j = math.floor(z0 / NB), math.floor(z1 / NB) do
			local k = i * 100000 + j
			local b = t[k]
			if not b then b = {} t[k] = b end
			b[#b + 1] = v
		end
	end
end

-- The collision file of the map you are on, from the map number (the map name string is the
-- same for every house in a town, the number is not).
local function nav_name()
	local m = MAPIDS[u16(MAPID)]
	local code = m and m[1]
	if not code then
		code = map_code()
		return code and (code:sub(1, 3) .. "A" .. code:sub(5, 8))
	end
	if #code == 3 then return code .. "A0000" end
	return code:sub(1, 3) .. "A" .. code:sub(5, 6) .. "00"
end
-- Read a map's walls and floors from the file. When run as a background job (a coroutine) it
-- does a slice each frame, so arriving in a big area does not make the game hitch.
function nav_build(name)
	local e = nav_load_index()[name]
	if not e then return nil end
	local f = io.open(NAV_FILE, "rb")
	if not f then return nil end
	f:seek("set", e.off)
	local raw = f:read(e.n * 24) or ""
	f:close()
	local n = { name = name, walls = {}, wb = {}, fb = {}, bb = {}, nfloors = 0 }
	for t = 0, e.n - 1 do
		if t % 150 == 149 and coroutine.isyieldable() then coroutine.yield() end
		local v = { string.unpack("<hhhhhhhhhh", raw, t * 24 + 1) }
		local ny = v[10] / 4096
		local sc = e.scale
		local x1, z1, x2, z2, x3, z3 = v[1] / sc, v[3] / sc, v[4] / sc, v[6] / sc, v[7] / sc, v[9] / sc
		if ny >= 0.5 then
			local tri = { x1, z1, x2, z2, x3, z3, v[2] / sc, v[5] / sc, v[8] / sc }
			n.nfloors = n.nfloors + 1
			bucket_add(n.fb, math.min(x1, x2, x3), math.min(z1, z2, z3), math.max(x1, x2, x3), math.max(z1, z2, z3), tri)
		elseif ny > -0.5 then
			-- a wall: its footprint on the ground is its longest edge
			local p = { { x1, z1 }, { x2, z2 }, { x3, z3 } }
			local ba, bb, bl = 1, 2, -1
			for a = 1, 2 do for b = a + 1, 3 do
				local l = (p[a][1] - p[b][1]) ^ 2 + (p[a][2] - p[b][2]) ^ 2
				if l > bl then ba, bb, bl = a, b, l end
			end end
			if bl > 0.0001 then
				-- with its height, so walls of a floor below a bridge can be left out
				local y1, y2, y3 = v[2] / sc, v[5] / sc, v[8] / sc
				local w = { p[ba][1], p[ba][2], p[bb][1], p[bb][2], math.min(y1, y2, y3), math.max(y1, y2, y3) }
				-- the kind of wall, from the low bits of its flags: 3 is furniture (counters, tables,
				-- shelves) that the game lets you talk across; 0 and 6 are the building's walls
				w.k = (raw:byte(t * 24 + 21) or 0) % 16
				-- where each corner sits along the footprint (0..1) and its height, so the wall's
				-- height at any point along it can be worked out (a slanted wall beside a ramp)
				local ax, az = w[3] - w[1], w[4] - w[2]
				local l = ax * ax + az * az
				local ys = { y1, y2, y3 }
				for c = 1, 3 do
					w[5 + 2 * c] = ((p[c][1] - w[1]) * ax + (p[c][2] - w[2]) * az) / l
					w[6 + 2 * c] = ys[c]
				end
				n.walls[#n.walls + 1] = w
				bucket_add(n.wb, math.min(w[1], w[3]) - 0.8, math.min(w[2], w[4]) - 0.8,
				           math.max(w[1], w[3]) + 0.8, math.max(w[2], w[4]) + 0.8, w)
			end
		end
	end
	return n
end
local function nav_for()
	local name = nav_name()
	if not name then return nil end
	if nav and nav.name == name then return nav end
	nav_cache = nav_cache or {}
	if nav_cache[name] then nav = nav_cache[name] return nav end
	local n = nav_build(name)
	if not n then return nil end
	nav = n
	nav_cache[name] = n
	return n
end
-- the walls of a map you have just arrived in, read in the background
nav_job = nil
function nav_prefetch()
	if nav_job then
		local ok, n = coroutine.resume(nav_job.co)
		if not ok then nav_job = nil return end
		if coroutine.status(nav_job.co) == "dead" then
			nav_cache = nav_cache or {}
			if n then nav_cache[nav_job.name] = n end
			nav_job = nil
			doors_cache.list = nil          -- name the stairs now that the floors are known
		end
		return
	end
	local name = nav_name()
	if name and not (nav_cache and nav_cache[name]) and name ~= nav_failed then
		nav_failed = name
		nav_job = { name = name, co = coroutine.create(function() return nav_build(name) end) }
	end
end
function nav_ready()
	local name = nav_name()
	return name and nav_cache and nav_cache[name] and nav_for() or nil
end

local function seg_dist2(px, pz, ax, az, bx, bz)
	local abx, abz = bx - ax, bz - az
	local l = abx * abx + abz * abz
	local t = l > 0 and ((px - ax) * abx + (pz - az) * abz) / l or 0
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local dx, dz = px - (ax + t * abx), pz - (az + t * abz)
	return dx * dx + dz * dz
end
local function cross(ox, oz, px, pz, qx, qz) return (px - ox) * (qz - oz) - (pz - oz) * (qx - ox) end
local function seg_cross(ax, az, bx, bz, cx, cz, dx, dz)
	local d1, d2 = cross(cx, cz, dx, dz, ax, az), cross(cx, cz, dx, dz, bx, bz)
	local d3, d4 = cross(ax, az, bx, bz, cx, cz), cross(ax, az, bx, bz, dx, dz)
	return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0))
end
local function has_floor(n, x, z)
	if n.nfloors == 0 then return true end
	local b = n.fb[math.floor(x / NB) * 100000 + math.floor(z / NB)]
	if not b then return false end
	for _, t in ipairs(b) do
		local x1, z1, x2, z2, x3, z3 = t[1], t[2], t[3], t[4], t[5], t[6]
		local d = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3)
		if d ~= 0 then
			local l1 = ((z2 - z3) * (x - x3) + (x3 - x2) * (z - z3)) / d
			local l2 = ((z3 - z1) * (x - x3) + (x1 - x3) * (z - z3)) / d
			if l1 >= -0.001 and l2 >= -0.001 and l1 + l2 <= 1.001 then return true end
		end
	end
	return false
end
-- can you stand here with this much room around you?
local function clear_at(n, x, z, clear, floors)
	if floors and not has_floor(n, x, z) then return false end
	local k = math.floor(x / NB) * 100000 + math.floor(z / NB)
	local bl = n.bb[k]
	if bl then
		for _, o in ipairs(bl) do
			if (x - o[1]) ^ 2 + (z - o[2]) ^ 2 < (o[3] + clear) ^ 2 then return false end
		end
	end
	local b = n.wb[k]
	if not b then return true end
	local c2 = clear * clear
	local py = n.py
	for _, w in ipairs(b) do
		if not (py and (w[6] < py - 0.4 or w[5] > py + 2.2)) then
			if seg_dist2(x, z, w[1], w[2], w[3], w[4]) < c2 then return false end
		end
	end
	return true
end
-- things the walls do not show (trees, barrels, people) are learned when you bump into them
local function nav_block(n, x, z, r)
	bucket_add(n.bb, x - r - 1, z - r - 1, x + r + 1, z + r + 1, { x, z, r })
end
-- (walls wholly below your feet, or high above your head, are on another level)
local function wall_between(n, x0, z0, x1, z1)
	local py = n.py
	local b = n.wb[math.floor(x1 / NB) * 100000 + math.floor(z1 / NB)]
	if b then for _, w in ipairs(b) do
		if not (py and (w[6] < py - 0.4 or w[5] > py + 2.2)) and seg_cross(x0, z0, x1, z1, w[1], w[2], w[3], w[4]) then return true end
	end end
	b = n.wb[math.floor(x0 / NB) * 100000 + math.floor(z0 / NB)]
	if b then for _, w in ipairs(b) do
		if not (py and (w[6] < py - 0.4 or w[5] > py + 2.2)) and seg_cross(x0, z0, x1, z1, w[1], w[2], w[3], w[4]) then return true end
	end end
	return false
end
-- a straight line you can walk along
local function line_ok(n, x0, z0, x1, z1, clear, avoid)
	local d = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local steps = math.max(1, math.ceil(d / 0.3))
	local lx, lz = x0, z0
	for i = 1, steps do
		local x, z = x0 + (x1 - x0) * i / steps, z0 + (z1 - z0) * i / steps
		if not clear_at(n, x, z, clear, false) or wall_between(n, lx, lz, x, z) then return false end
		if avoid then
			for _, b in ipairs(avoid) do
				if x > b.x0 - 0.5 and x < b.x1 + 0.5 and z > b.z0 - 0.5 and z < b.z1 + 0.5 then return false end
			end
		end
		lx, lz = x, z
	end
	return true
end

-- A* over a half-step grid. Runs a little each frame (it is a coroutine) so the game never stalls:
-- at most about 5 milliseconds of planning per frame.
PLAN_SLICE = 0.003
plan_clock = nil
function plan_resume(co)
	plan_clock = os.clock and os.clock() or nil
	return coroutine.resume(co)
end
NEIGH = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 1, 1, 1.4142 }, { 1, -1, 1.4142 }, { -1, 1, 1.4142 }, { -1, -1, 1.4142 } }
local function find_path(n, sx, sz, gx, gz, clear, floors, budget, avoid)
	local C = NCELL
	local si, sj = math.floor(sx / C + 0.5), math.floor(sz / C + 0.5)
	local gi, gj = math.floor(gx / C + 0.5), math.floor(gz / C + 0.5)
	local function key(i, j) return (i + 20000) * 40000 + (j + 20000) end
	local function h(i, j) local a, b = math.abs(i - gi), math.abs(j - gj) return math.max(a, b) + 0.4142 * math.min(a, b) end
	local ok = {}
	local function passable(i, j)
		local k = key(i, j)
		local v = ok[k]
		if v == nil then
			local x, z = i * C, j * C
			v = clear_at(n, x, z, clear, floors)
			if v and avoid then
				-- keep out of doorways and exits you are not going to
				for _, b in ipairs(avoid) do
					local pd = b.pad or 0.6
					if x > b.x0 - pd and x < b.x1 + pd and z > b.z0 - pd and z < b.z1 + pd then v = false break end
				end
			end
			ok[k] = v
		end
		return v
	end
	-- binary heap
	local heap, hn = {}, 0
	local function push(f, k, i, j)
		hn = hn + 1
		local e = { f, k, i, j }
		local c = hn
		heap[c] = e
		while c > 1 do
			local p = c // 2
			if heap[p][1] <= f then break end
			heap[c], heap[p] = heap[p], heap[c]
			c = p
		end
	end
	local function pop()
		local top = heap[1]
		heap[1] = heap[hn] heap[hn] = nil hn = hn - 1
		local c = 1
		while true do
			local l, r, m = c * 2, c * 2 + 1, c
			if l <= hn and heap[l][1] < heap[m][1] then m = l end
			if r <= hn and heap[r][1] < heap[m][1] then m = r end
			if m == c then break end
			heap[c], heap[m] = heap[m], heap[c]
			c = m
		end
		return top
	end
	local g, came = {}, {}
	local sk = key(si, sj)
	g[sk] = 0
	push(h(si, sj), sk, si, sj)
	local best, bestk, bi, bj = h(si, sj), sk, si, sj
	local count = 0
	while hn > 0 do
		local e = pop()
		local k, i, j = e[2], e[3], e[4]
		local gc = g[k]
		if e[1] - h(i, j) <= gc + 0.0001 then
			local hd = h(i, j)
			if hd < best then best, bestk, bi, bj = hd, k, i, j end
			-- (a goal right against a wall or the edge can never be stood on exactly: once the
			-- search has gone on a while, a step or so short of it will do)
			if hd < 1 or (hd < 3 and count > 1500) then break end
			count = count + 1
			if count > 60000 then break end
			if count % budget == 0 or (count % 24 == 0 and plan_clock and os.clock() - plan_clock > PLAN_SLICE) then
				coroutine.yield()
				plan_clock = os.clock and os.clock()
			end
			for _, d in ipairs(NEIGH) do
				local ni, nj = i + d[1], j + d[2]
				if passable(ni, nj) and not wall_between(n, i * C, j * C, ni * C, nj * C) then
					local nk = key(ni, nj)
					local ng = gc + d[3]
					if ng < (g[nk] or 1e18) then
						g[nk] = ng came[nk] = { k, i, j }
						push(ng + h(ni, nj), nk, ni, nj)
					end
				end
			end
		end
	end
	-- walk back from the closest point reached
	local pts = {}
	local k, i, j = bestk, bi, bj
	while k do
		table.insert(pts, 1, { i * C, j * C })
		local c = came[k]
		if not c then break end
		k, i, j = c[1], c[2], c[3]
	end
	-- straighten it: from each point jump to the farthest point you can walk to in a line
	local out = {}
	local a = 1
	while a < #pts do
		local b = math.min(#pts, a + 40)
		while b > a + 1 and not line_ok(n, pts[a][1], pts[a][2], pts[b][1], pts[b][2], clear * 0.8, avoid) do b = b - 1 end
		out[#out + 1] = pts[b]
		a = b
	end
	return out, best * C
end

-- The same, but knowing about levels: a bridge over a hall, a balcony, stairs between them.
-- Every half step it keeps the height of the floor you would be standing on; you can only step
-- onto floor near that height, and only walls at the height of your body are in the way.
function floor_heights(n, x, z)
	local b = n.fb[math.floor(x / NB) * 100000 + math.floor(z / NB)]
	local out = {}
	if not b then return out end
	for _, t in ipairs(b) do
		local x1, z1, x2, z2, x3, z3 = t[1], t[2], t[3], t[4], t[5], t[6]
		local d = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3)
		if d ~= 0 and t[7] then
			local l1 = ((z2 - z3) * (x - x3) + (x3 - x2) * (z - z3)) / d
			local l2 = ((z3 - z1) * (x - x3) + (x1 - x3) * (z - z3)) / d
			if l1 >= -0.001 and l2 >= -0.001 and l1 + l2 <= 1.001 then
				out[#out + 1] = l1 * t[7] + l2 * t[8] + (1 - l1 - l2) * t[9]
			end
		end
	end
	return out
end
function floor_near(n, x, z, h, reach)
	local best, bd = nil, reach
	for _, y in ipairs(floor_heights(n, x, z)) do
		local d = math.abs(y - h)
		if d <= bd then best, bd = y, d end
	end
	return best
end
-- how high a wall reaches at the point along it nearest to (x, z)
function wall_span_at(w, x, z)
	if not w[7] then return w[5], w[6] end
	local ax, az = w[3] - w[1], w[4] - w[2]
	local l = ax * ax + az * az
	local t = l > 0 and ((x - w[1]) * ax + (z - w[2]) * az) / l or 0
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local lo, hi = nil, nil
	for a = 1, 3 do
		local b = a % 3 + 1
		local ta, ya, tb, yb = w[5 + 2 * a], w[6 + 2 * a], w[5 + 2 * b], w[6 + 2 * b]
		if (ta - t) * (tb - t) <= 0 then
			local y
			if math.abs(tb - ta) < 1e-6 then y = math.max(ya, yb)
				lo, hi = math.min(lo or ya, ya, yb), math.max(hi or ya, ya, yb)
			else
				y = ya + (yb - ya) * (t - ta) / (tb - ta)
				lo, hi = math.min(lo or y, y), math.max(hi or y, y)
			end
		end
	end
	if not lo then return w[5], w[6] end
	return lo, hi
end
function wall_in_band(w, h, x, z)
	if w[5] >= h + 1.4 or w[6] <= h + 0.3 then return false end
	if not x then return true end
	local lo, hi = wall_span_at(w, x, z)
	return lo < h + 1.4 and hi > h + 0.3
end
function clear_at3(n, x, z, h, clear)
	local k = math.floor(x / NB) * 100000 + math.floor(z / NB)
	local bl = n.bb[k]
	if bl then
		for _, o in ipairs(bl) do
			if (x - o[1]) ^ 2 + (z - o[2]) ^ 2 < (o[3] + clear) ^ 2 then return false end
		end
	end
	local b = n.wb[k]
	if not b then return true end
	local c2 = clear * clear
	for _, w in ipairs(b) do
		if seg_dist2(x, z, w[1], w[2], w[3], w[4]) < c2 and wall_in_band(w, h, x, z) then return false end
	end
	return true
end
function wall_between3(n, x0, z0, x1, z1, h)
	for _, k in ipairs({ math.floor(x1 / NB) * 100000 + math.floor(z1 / NB), math.floor(x0 / NB) * 100000 + math.floor(z0 / NB) }) do
		local b = n.wb[k]
		if b then for _, w in ipairs(b) do
			if seg_cross(x0, z0, x1, z1, w[1], w[2], w[3], w[4]) and wall_in_band(w, h, (x0 + x1) / 2, (z0 + z1) / 2) then return true end
		end end
	end
	return false
end
function in_avoid(avoid, x, z, h, pad)
	if not avoid then return false end
	for _, b in ipairs(avoid) do
		local pad = b.pad or pad
		if x > b.x0 - pad and x < b.x1 + pad and z > b.z0 - pad and z < b.z1 + pad
			and (not b.y0 or (h > b.y0 - 0.5 and h < b.y1 + 0.5)) then return true end
	end
	return false
end
STEP_RISE = 0.6
function line_ok3(n, x0, z0, h0, x1, z1, clear, avoid, h1)
	local d = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local steps = math.max(1, math.ceil(d / 0.3))
	local lx, lz, h = x0, z0, h0
	for i = 1, steps do
		local x, z = x0 + (x1 - x0) * i / steps, z0 + (z1 - z0) * i / steps
		-- keep to the floor the route is on (not a floor above or below it)
		local want = h1 and (h0 + (h1 - h0) * i / steps) or h
		local nh = floor_near(n, x, z, want, h1 and 0.45 or STEP_RISE * 0.6)
		if nh and math.abs(nh - h) > STEP_RISE then nh = nil end
		if not nh or not clear_at3(n, x, z, nh, clear) or wall_between3(n, lx, lz, x, z, math.max(h, nh))
			or in_avoid(avoid, x, z, nh, 0.5) then return false end
		lx, lz, h = x, z, nh
	end
	return true
end
function find_path3(n, sx, sy, sz, gx, gz, gy, clear, budget, avoid)
	local C = NCELL
	local si, sj = math.floor(sx / C + 0.5), math.floor(sz / C + 0.5)
	local gi, gj = math.floor(gx / C + 0.5), math.floor(gz / C + 0.5)
	local sh = floor_near(n, sx, sz, sy, 1.5) or sy
	local function key(i, j, h) return ((i + 20000) * 40000 + (j + 20000)) * 64 + (math.floor(h * 2 + 0.5) % 64) end
	local function hd(i, j, h)
		local a, b = math.abs(i - gi), math.abs(j - gj)
		local v = math.max(a, b) + 0.4142 * math.min(a, b)
		if gy then v = v + math.max(0, math.abs(h - gy) - 1.2) * 2 end
		return v
	end
	local heap, hn = {}, 0
	local function push(f, e)
		hn = hn + 1
		local c = hn
		heap[c] = { f, e }
		while c > 1 do
			local p = c // 2
			if heap[p][1] <= f then break end
			heap[c], heap[p] = heap[p], heap[c]
			c = p
		end
	end
	local function pop()
		local top = heap[1]
		heap[1] = heap[hn] heap[hn] = nil hn = hn - 1
		local c = 1
		while true do
			local l, r, m = c * 2, c * 2 + 1, c
			if l <= hn and heap[l][1] < heap[m][1] then m = l end
			if r <= hn and heap[r][1] < heap[m][1] then m = r end
			if m == c then break end
			heap[c], heap[m] = heap[m], heap[c]
			c = m
		end
		return top[2]
	end
	local g, came = {}, {}
	local fh_memo, clear_memo = {}, {}
	local s0 = { si, sj, sh, key(si, sj, sh) }
	g[s0[4]] = 0
	push(hd(si, sj, sh), s0)
	local best, bestn = hd(si, sj, sh), s0
	local count = 0
	while hn > 0 do
		local e = pop()
		local i, j, h, k = e[1], e[2], e[3], e[4]
		local gc = g[k]
		if not e.done then
			e.done = true
			local dd = hd(i, j, h)
			if dd < best then best, bestn = dd, e end
			if dd < 1 or (dd < 3 and count > 1500) then break end
			count = count + 1
			if count > 60000 then break end
			if count % budget == 0 or (count % 24 == 0 and plan_clock and os.clock() - plan_clock > PLAN_SLICE) then
				coroutine.yield()
				plan_clock = os.clock and os.clock()
			end
			for _, d in ipairs(NEIGH) do
				local ni, nj = i + d[1], j + d[2]
				local x, z = ni * C, nj * C
				-- every floor within a step's reach is a way on (a ramp over a floor: both)
				local ck = (ni + 20000) * 40000 + (nj + 20000)
				local fhs = fh_memo[ck]
				if not fhs then fhs = floor_heights(n, x, z) fh_memo[ck] = fhs end
				for _, nh in ipairs(fhs) do
					local ok_here = clear_memo[ck * 64 + (math.floor(nh * 2 + 0.5) % 64)]
					if ok_here == nil then
						ok_here = clear_at3(n, x, z, nh, clear)
						clear_memo[ck * 64 + (math.floor(nh * 2 + 0.5) % 64)] = ok_here
					end
					if math.abs(nh - h) <= STEP_RISE * d[3] and ok_here
						and not wall_between3(n, i * C, j * C, x, z, math.max(h, nh))
						and not in_avoid(avoid, x, z, nh, 0.6) then
						local nk = key(ni, nj, nh)
						local ng = gc + d[3]
						if ng < (g[nk] or 1e18) then
							g[nk] = ng
							local ne = { ni, nj, nh, nk }
							came[nk] = e
							push(ng + hd(ni, nj, nh), ne)
						end
					end
				end
			end
		end
	end
	local pts = {}
	local e = bestn
	while e do
		table.insert(pts, 1, { e[1] * C, e[2] * C, e[3] })
		e = came[e[4]]
	end
	local out = {}
	local a = 1
	while a < #pts do
		local b = math.min(#pts, a + 40)
		while b > a + 1 and not line_ok3(n, pts[a][1], pts[a][2], pts[a][3], pts[b][1], pts[b][2], clear * 0.8, avoid, pts[b][3]) do b = b - 1 end
		out[#out + 1] = pts[b]
		a = b
	end
	return out, best * C
end
-- Exits at the top or bottom of a flight of stairs: the floor inside the exit's box climbs.
-- Call them "stairs up to ..." or "stairs down to ..." (from the height you are at now).
function stairs_mark(list)
	local nv = nav_ready()
	if not nv or nv.nfloors == 0 then return end
	local _, py = player_pos()
	for _, d in ipairs(list) do
		if d.kind == 0 and d.y0 and not EXIT_NAMES[d.id] and not exit_name_here(d.id) and not (d.id >= 20000 and d.id < 30000) then
			local lo, hi, sum, n = math.huge, -math.huge, 0, 0
			for i = 0, 4 do for j = 0, 4 do
				local x, z = d.x0 + (d.x1 - d.x0) * i / 4, d.z0 + (d.z1 - d.z0) * j / 4
				for _, h in ipairs(floor_heights(nv, x, z)) do
					if h >= d.y0 - 0.5 and h <= d.y1 + 0.5 then
						lo, hi, sum, n = math.min(lo, h), math.max(hi, h), sum + h, n + 1
					end
				end
			end end
			if n > 0 and hi - lo > 0.7 then
				local name = (d.label:gsub("^exit to ", ""))
				if name == "exit" or name == "passage" then name = nil end
				if name == "exit outside" then name = "the outside" end      -- not "stairs up to exit outside"
				local mid = sum / n
				local way = ""
				if py and mid > py + 1 then way = " up" elseif py and mid < py - 1 then way = " down" end
				d.label = "stairs" .. way .. (name and (" to " .. name) or "")
			end
		end
	end
end
-- the planner to use: with levels when the map has floors with heights
function plan_path(n, sx, sy, sz, gx, gz, gy, clear, floors, budget, avoid)
	if floors and sy and n.nfloors > 0 then
		local p, rem = find_path3(n, sx, sy, sz, gx, gz, gy, clear, budget, avoid)
		return p, rem
	end
	return find_path(n, sx, sz, gx, gz, clear, floors, budget, avoid)
end

DIRS = { { Up = true }, { Up = true, Right = true }, { Right = true }, { Down = true, Right = true },
               { Down = true }, { Down = true, Left = true }, { Left = true }, { Up = true, Left = true } }
local function dir_toward(dx, dz)
	local ux, uz, rx, rz = screen_axes()
	local f, r = dx * ux + dz * uz, dx * rx + dz * rz
	local a = (math.atan2 or math.atan)(r, f)
	return math.floor(a / (math.pi / 4) + 0.5) % 8
end
-- Doorways and exits a route keeps out of: all but the one you are going to and the one you are
-- standing in (the planner knows their heights, so one on another level is no obstacle)
function avoid_list(tx, tz, px, pz)
	local py = select(2, player_pos())
	local avoid = {}
	for _, d in ipairs(doors()) do
		local mine = tx and math.abs(d.x - tx) < 0.1 and math.abs(d.z - tz) < 0.1
		local here = px > d.x0 and px < d.x1 and pz > d.z0 and pz < d.z1
		-- right next to one (just arrived up a stairway): keep out of the box itself only, so
		-- there is a way to step away from it
		local near = px > d.x0 - 0.8 and px < d.x1 + 0.8 and pz > d.z0 - 0.8 and pz < d.z1 + 0.8
		if not mine and not here then
			if near then
				local y1 = d.y1
				if d.kind == 1 and d.facing and d.y0 then y1 = math.min(d.y1, d.y0 + 2.0) end
				avoid[#avoid + 1] = { x0 = d.x0, x1 = d.x1, z0 = d.z0, z1 = d.z1, y0 = d.y0, y1 = y1, pad = 0.05 }
			elseif d.kind == 1 and d.facing then
				-- the box behind a real door: you only go in by opening the door, so walking past
				-- it is fine (Brigadoom's walkway runs right past the northern tower's door)
				-- (and only at the door's own floor: a roof walk just over the door is not in it)
				avoid[#avoid + 1] = { x0 = d.x0, x1 = d.x1, z0 = d.z0, z1 = d.z1, y0 = d.y0, y1 = d.y0 and math.min(d.y1, d.y0 + 2.0), pad = 0.15 }
			else
				avoid[#avoid + 1] = d
			end
		end
	end
	return avoid
end
-- Where you can walk from where you stand, without going through a door. One map can hold
-- several rooms that are only joined through another map (the side rooms off a hall), so a thing
-- can be close by and still out of reach. Worked out once per room and kept.
REACH = nil
REACH_CELL = 0.5
REACH_MAX = 20000
function reach_key(i, j) return (i + 20000) * 40000 + (j + 20000) end
function reach_region(n, px, py, pz, shut)
	local C = REACH_CELL
	local si, sj = math.floor(px / C + 0.5), math.floor(pz / C + 0.5)
	local R = shut and REACH_SHUT or REACH
	if R and R.n == n and math.abs((R.py or 0) - (py or 0)) < 1.5 then
		for di = -1, 1 do for dj = -1, 1 do
			if R.cells[reach_key(si + di, sj + dj)] then return R end
		end end
		if R.truncated and (px - R.x) ^ 2 + (pz - R.z) ^ 2 < 64 then return R end
	end
	n.py = py
	local avoid = avoid_list(nil, nil, px, pz)
	if shut then
		-- every door of the map closed: which room you are in
		local base, gn = u32(GIMMICK_PTR), u32(GIMMICK_COUNT)
		if gn > 0 and gn <= 200 and inram(base, gn * 0x74) then
			for k = 0, gn - 1 do
				local g = base + k * 0x74
				if u32(g + 4) == 2 then
					local gx, gz = s32(g + 8) / 4096, s32(g + 0x10) / 4096
					if (px - gx) ^ 2 + (pz - gz) ^ 2 > 3 then
						avoid[#avoid + 1] = { x0 = gx - 1.6, x1 = gx + 1.6, z0 = gz - 1.6, z1 = gz + 1.6, pad = 0.05 }
					end
				end
			end
		end
	end
	if n.nfloors > 0 and py then
		local keep = REACH
		local r = reach_region3(n, px, py, pz, avoid)
		if shut then REACH_SHUT, REACH = r, keep end
		return r
	end
	local cells, q, qh = {}, {}, 1
	local function ok(i, j)
		local x, z = i * C, j * C
		if not clear_at(n, x, z, 0.25, true) then return false end
		for _, b in ipairs(avoid) do
			local pd = b.pad or 0.6
			if x > b.x0 - pd and x < b.x1 + pd and z > b.z0 - pd and z < b.z1 + pd then return false end
		end
		return true
	end
	-- start from the nearest open spot (you may be standing against a wall)
	local start = nil
	for r = 0, 2 do
		for di = -r, r do for dj = -r, r do
			if not start and ok(si + di, sj + dj) then start = { si + di, sj + dj } end
		end end
	end
	if not start then if shut then REACH_SHUT = nil else REACH = nil end return nil end
	cells[reach_key(start[1], start[2])] = true
	q[1] = start
	local count, truncated = 1, false
	while qh <= #q do
		local c = q[qh] qh = qh + 1
		local i, j = c[1], c[2]
		for _, d in ipairs(NEIGH) do
			local ni, nj = i + d[1], j + d[2]
			local k = reach_key(ni, nj)
			if cells[k] == nil then
				if ok(ni, nj) and not wall_between(n, i * C, j * C, ni * C, nj * C) then
					cells[k] = true
					count = count + 1
					q[#q + 1] = { ni, nj }
				end
			end
		end
		if count > REACH_MAX then truncated = true break end
	end
	local res = { n = n, cells = cells, py = py, x = px, z = pz, truncated = truncated, count = count }
	if shut then REACH_SHUT = res else REACH = res end
	return res
end
-- the same over floors at different heights (stairs, ramps, balconies)
function reach_region3(n, px, py, pz, avoid, maxc)
	local C = REACH_CELL
	local MAXC = maxc or REACH_MAX
	local si, sj = math.floor(px / C + 0.5), math.floor(pz / C + 0.5)
	local sh = floor_near(n, px, pz, py, 1.5) or py
	local function k3(i, j, h) return reach_key(i, j) * 64 + (math.floor(h * 2 + 0.5) % 64) end
	local cells, seen, q, qh = {}, {}, {}, 1
	local fh_memo = {}
	local function fhs_at(i, j)
		local ck = reach_key(i, j)
		local f = fh_memo[ck]
		if not f then f = floor_heights(n, i * C, j * C) fh_memo[ck] = f end
		return f
	end
	local start = nil
	for r = 0, 2 do
		for di = -r, r do for dj = -r, r do
			if not start then
				for _, h in ipairs(fhs_at(si + di, sj + dj)) do
					if not start and math.abs(h - sh) < 1.0 and clear_at3(n, (si + di) * C, (sj + dj) * C, h, 0.25) then start = { si + di, sj + dj, h } end
				end
			end
		end end
	end
	if not start then REACH = nil return nil end
	seen[k3(start[1], start[2], start[3])] = true
	cells[reach_key(start[1], start[2])] = true
	q[1] = start
	local count, truncated = 1, false
	while qh <= #q do
		local c = q[qh] qh = qh + 1
		local i, j, h = c[1], c[2], c[3]
		for _, d in ipairs(NEIGH) do
			local ni, nj = i + d[1], j + d[2]
			local x, z = ni * C, nj * C
			for _, nh in ipairs(fhs_at(ni, nj)) do
				local k = k3(ni, nj, nh)
				if not seen[k] and math.abs(nh - h) <= STEP_RISE * d[3] then
					if clear_at3(n, x, z, nh, 0.25) and not wall_between3(n, i * C, j * C, x, z, math.max(h, nh))
						and not in_avoid(avoid, x, z, nh, 0.6) then
						seen[k] = true
						cells[reach_key(ni, nj)] = true
						count = count + 1
						q[#q + 1] = { ni, nj, nh }
					end
				end
			end
		end
		if count > MAXC then truncated = true break end
		-- (the whole of a big field, worked out a little each frame)
		if maxc and count % 128 == 0 and plan_clock and os.clock() - plan_clock > PLAN_SLICE and coroutine.isyieldable() then
			coroutine.yield()
		end
	end
	local res = { n = n, cells = cells, cells3 = seen, k3 = k3, py = py, x = px, z = pz, truncated = truncated, count = count }
	if not maxc then REACH = res end
	return res
end
-- A big open map (a field) is too big to work out in one go: work out once, over a few frames,
-- where you can walk from where you are, and keep it while you stay in that part of the field
-- (a river or a cliff splits some fields in two: an exit on the far side is out of reach).
REACH_BIG = { n = nil, co = nil, R = nil }
function reach_big_get(n, px, py, pz)
	local B = REACH_BIG
	if (n.nfloors or 0) == 0 then return nil end
	if B.n == n and B.R and reach_near(B.R, px, pz) < 1.5 then return B.R end
	if B.co and B.n == n then return nil end          -- still working it out
	B.n, B.R = n, nil
	local av = avoid_list(nil, nil, px, pz)
	B.co = coroutine.create(function() return reach_region3(n, px, py, pz, av, 200000) end)
	return nil
end
function reach_big_step()
	local B = REACH_BIG
	if not B.co then return end
	if nav_ready() ~= B.n then B.co, B.n = nil, nil return end
	plan_clock = os.clock and os.clock() or nil
	local ok, R = coroutine.resume(B.co)
	if coroutine.status(B.co) == "dead" then
		B.co = nil
		if ok and R and not R.truncated then B.R = R end
	end
end
-- with floors at different heights: can you get near this spot at the height it is at (a chest
-- on top of a tower stands over ground you can walk on)? nil when it cannot be told
function reach_near3(R, n, x, z, y)
	if not R.cells3 or not y then return nil end
	local fh, fd = nil, 1.5
	for _, h in ipairs(floor_heights(n, x, z)) do
		if math.abs(h - y) < fd then fh, fd = h, math.abs(h - y) end
	end
	if not fh then return nil end
	local C = REACH_CELL
	local ci, cj = math.floor(x / C + 0.5), math.floor(z / C + 0.5)
	for di = -5, 5 do for dj = -5, 5 do
		for dh = -1, 1 do
			if R.cells3[R.k3(ci + di, cj + dj, fh + dh * 0.5)] then return true end
		end
	end end
	return false
end
-- can you get within talking distance of this spot (across a counter is fine)?
function reach_near(R, x, z)
	local C = REACH_CELL
	local ci, cj = math.floor(x / C + 0.5), math.floor(z / C + 0.5)
	local best = 1e9
	for di = -6, 6 do for dj = -6, 6 do
		if R.cells[reach_key(ci + di, cj + dj)] then
			local dd = ((ci + di) * C - x) ^ 2 + ((cj + dj) * C - z) ^ 2
			if dd < best then best = dd end
		end
	end end
	return math.sqrt(best)
end
REACH_TALK = 2.2
REACH_DOOR = 2.2
-- mark the things in the list you cannot walk to from here, and put them after the rest
function reach_mark(list)
	local n = nav_ready()
	local px, py, pz = player_pos()
	if not n or not px then return list end
	-- just arrived: you are put in the new map a moment after it changes, so where you stand is
	-- not known yet ("Doors, 6, all in other rooms" on coming into Zere)
	if frame - code_changed_frame < 150 or fading() then return list end
	local ok, R
	if n.reach_big then
		-- a big open map (a field): worked out bit by bit (until then, nothing is marked)
		ok, R = pcall(reach_big_get, n, px, py, pz)
		if not ok or not R then return list end
	else
		ok, R = pcall(reach_region, n, px, py, pz)
		if ok and R and R.truncated then n.reach_big = true pcall(reach_big_get, n, px, py, pz) end
		if not ok or not R or R.truncated then return list end
		-- a scrap of floor (lying in bed, standing on a table in a scene): no telling yet
		if (R.count or 0) < 16 then return list end
	end
	for _, it in ipairs(list) do
		-- (an exit is a box at the map's edge you walk out through: it only has to be close to
		-- where you can walk; one across a river is out of reach)
		if not it.mark then
			local d = reach_near(R, it.x, it.z)
			it.away = d
			it.unreachable = d > (it.kind == 0 and 4.0 or it.kind and REACH_DOOR or REACH_TALK) or nil
			local iy = it.y0 and it.y1 and (it.y0 + it.y1) / 2 or it.fy
			-- (not for exits: a stairway's exit box sits up at the top of its steps, above the floor
			-- you walk up from)
			if not it.unreachable and iy and it.kind ~= 0 and reach_near3(R, n, it.x, it.z, iy) == false then it.unreachable = true end
			it.level = it.unreachable and level_word(n, py, it.x, it.z, it.kind ~= 0 and iy or nil) or nil
		end
	end
	return list
end
-- out of reach on a different level (from a castle's wall walk, the courtyard below): "lower down"
-- or "higher up", when nothing at that spot is at about your height
function level_word(n, py, x, z, y)
	if not py or (n.nfloors or 0) == 0 then return nil end
	local fs = floor_heights(n, x, z)
	if #fs == 0 then return nil end
	local best, bd = nil, 1e9
	for _, h in ipairs(fs) do
		local d = math.abs(h - py)
		if d < bd then best, bd = h, d end
	end
	if bd < 1.0 and not y then return nil end
	-- a door's box says how high it is (a terrace door has the courtyard under it too)
	if y then
		local yb, yd = nil, 1.5
		for _, h in ipairs(fs) do if math.abs(h - y) < yd then yb, yd = h, math.abs(h - y) end end
		if not yb then return nil end
		if math.abs(yb - py) < 1.0 then return nil end
		best = yb
	end
	return best < py and "lower down" or "higher up"
end
-- said when a thing on the list cannot be walked to from here
function unreachable_msg(it)
	if not it.unreachable then return nil end
	local code = map_code() or ""
	local what = (it.kind == 1) and "That door is" or "It is"
	if it.level then
		return "There is no way to " .. it.label .. " from here. " .. what .. " " .. it.level .. ", on another level from where you are. Go through a door or find stairs to get there."
	end
	if code:match("^F") or code:match("^S") or it.kind == 0 then
		-- out in the open: water, cliffs or a fence in between
		return "There is no way to " .. it.label .. " from here. It is across water, a cliff or a fence; the way there is round through another part of this area, or another area."
	end
	return "There is no way to " .. it.label .. " from here. " .. what .. " in another room or behind a wall. Go through a door to get there."
end
function reach_test_g()
	local list = build_nearby_g()
	local px, py, pz = player_pos()
	return list, REACH, px, py, pz
end

local walk = nil
local function stop_walk(msg)
	walk = nil
	if msg and (msg:find("^Arrived") or msg:find("^In front of")) and sound then pcall(sound.play, "chime", 0, 0, -0.5, 0.8) end
	if msg then say(msg, true) end
end
dq9_debug = function() return walk end
-- Shopkeepers and innkeepers stand behind a counter: a raised top between two walls. Walking
-- up behind them is the wrong side ("check in over the counter"), so for a person with a counter
-- right next to them, go to the other side of it and face them across it. Of the two sides the
-- customers' side is the roomier one.
-- Where the game lets you talk to someone from: shopkeepers, bank clerks and the like have a
-- box set out in front of their counter (stored just before their placement record: a word
-- 0x50, then the box's far x, far z, near x, near z). Its middle, or the nearest clear spot in it.
function zone_box(o)
	local r = u32(o + 0x0C)
	if not inram(r - 0x20, 0x40) or u32(r - 0x18) ~= 0x50 then return nil end
	local x1, z1, x0, z0 = s32(r - 0x14) / 4096, s32(r - 0x10) / 4096, s32(r - 0x0C) / 4096, s32(r - 0x08) / 4096
	if not (x1 > x0 and z1 > z0 and x1 - x0 < 8 and z1 - z0 < 8) then return nil end
	local ox, oz = s32(o + 0x24) / 4096, s32(o + 0x2C) / 4096
	if (ox - (x0 + x1) / 2) ^ 2 + (oz - (z0 + z1) / 2) ^ 2 > 36 then return nil end
	-- the box is where you talk to them from: right by them (the old woman at Zere's inn points
	-- at a box by the old man asleep across the room)
	local nx, nz = math.max(x0, math.min(ox, x1)), math.max(z0, math.min(oz, z1))
	if (ox - nx) ^ 2 + (oz - nz) ^ 2 > 3.0 ^ 2 then return nil end
	return x0, z0, x1, z1
end
function counter_zone(n, o, y)
	if not o or not inram(o, 0x30) then return nil end
	local x0, z0, x1, z1 = zone_box(o)
	if not x0 then
		-- each person is two objects in the same spot; the box can be on the other one
		local ox, oz = s32(o + 0x24), s32(o + 0x2C)
		local cnt = u32(OBJ_COUNT)
		for i = 0, (cnt <= 64 and cnt or 0) - 1 do
			local q = u32(OBJ_TABLE + 4 * i)
			if q ~= o and inram(q, 0x30) and math.abs(s32(q + 0x24) - ox) < 64 and math.abs(s32(q + 0x2C) - oz) < 64 then
				x0, z0, x1, z1 = zone_box(q)
				if x0 then break end
			end
		end
	end
	if not x0 then return nil end
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	if not n then return { x = cx, z = cz } end
	local best, bd = nil, 1e9
	for i = 0, 6 do for j = 0, 6 do
		local x, z = x0 + (x1 - x0) * (0.15 + 0.7 * i / 6), z0 + (z1 - z0) * (0.15 + 0.7 * j / 6)
		local d = (x - cx) ^ 2 + (z - cz) ^ 2
		if d < bd and clear_at3(n, x, z, y, 0.3) then best, bd = { x = x, z = z }, d end
	end end
	return best or { x = cx, z = cz }
end
function counter_approach(n, x, z, y, o)
	if not n then return nil end
	local zb = counter_zone(n, o, y)
	if zb then return zb end
	local function level(px, pz, h)
		for _, f in ipairs(floor_heights(n, px, pz)) do if math.abs(f - h) < 0.25 then return true end end
		return false
	end
	local function raised(px, pz, h)
		for _, f in ipairs(floor_heights(n, px, pz)) do if f > h + 0.3 and f < h + 1.3 then return true end end
		return false
	end
	local function depth(px, pz, dx, dz, h)
		local d = 0
		while d < 8 do
			local nx, nz = px + dx * (d + 0.5), pz + dz * (d + 0.5)
			if wall_between3(n, px + dx * d, pz + dz * d, nx, nz, h) or not level(nx, nz, h) then break end
			d = d + 0.5
		end
		return d
	end
	local best = nil
	for _, dv in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		local dx, dz = dv[1], dv[2]
		local t0, t1 = nil, nil
		local t = 0.2
		while t <= 4.2 do
			local px, pz = x + dx * t, z + dz * t
			local r = raised(px, pz, y)
			if not t0 then
				if r then t0 = t elseif t > 2.2 then break end
			elseif not r then t1 = t break end
			t = t + 0.1
		end
		if t0 and t1 and t1 - t0 < 2.0 then
			local ax, az = x + dx * (t1 + 0.5), z + dz * (t1 + 0.5)
			if level(ax, az, y) and clear_at3(n, ax, az, y, 0.3)
				and depth(ax, az, dx, dz, y) > depth(x, z, -dx, -dz, y) then
				if not best or t1 < best.t then best = { x = ax, z = az, t = t1 } end
			end
		end
	end
	if best then return best end
	return talk_across(n, x, z, y, o)
end
-- Which way a person faces: their turn is 4.12 fixed point radians, 0x10 bytes after their place
-- (0 faces down the map, +z; a quarter turn faces +x). Shopkeepers face the side you talk to
-- them from. Snapped to the nearest of the map's four directions.
function person_facing(o, x, z)
	if not o or not inram(o, 0x80) then return nil end
	for _, po in ipairs({ 0x24, 0x64 }) do
		if math.abs(s32(o + po) / 4096 - x) < 0.05 and math.abs(s32(o + po + 8) / 4096 - z) < 0.05 then
			local a = u16(o + po + 0x10) / 4096
			local fx, fz = math.sin(a), math.cos(a)
			if math.abs(fx) >= math.abs(fz) then return (fx >= 0 and 1 or -1), 0 end
			return 0, (fz >= 0 and 1 or -1)
		end
	end
	return nil
end
-- Someone you cannot walk up to, behind furniture the game lets you talk across (a counter with
-- no raised top in the map, as at the Angel Falls inn): the nearest spot you can walk to, straight
-- up, down, left or right of them, with only furniture between (not a wall).
function talk_across(n, x, z, y, o)
	local px, py, pz = player_pos()
	if not px or not reach_region then return nil end
	local ok, R = pcall(reach_region, n, px, py, pz)
	if not ok or not R or not R.cells then return nil end
	local C = REACH_CELL
	local function reachable(ax, az, r)
		local si, sj = math.floor(ax / C + 0.5), math.floor(az / C + 0.5)
		for di = -r, r do for dj = -r, r do
			if R.cells[reach_key(si + di, sj + dj)] then return true end
		end end
		return false
	end
	if reachable(x, z, 1) then return nil end          -- you can walk right up to them
	-- each wall is two triangles over the same line on the ground; furniture has at least one
	-- of them marked (kind 3), a building's wall has neither
	local function crossing(ax, az)
		local seen, groups = {}, {}
		for _, k in ipairs({ math.floor(x / NB) * 100000 + math.floor(z / NB), math.floor(ax / NB) * 100000 + math.floor(az / NB),
		                     math.floor((x + ax) / 2 / NB) * 100000 + math.floor((z + az) / 2 / NB) }) do
			for _, w in ipairs(n.wb[k] or {}) do
				if not seen[w] and seg_cross(x, z, ax, az, w[1], w[2], w[3], w[4]) and wall_in_band(w, y) then
					seen[w] = true
					local a1, a2 = string.format("%.1f,%.1f", w[1], w[2]), string.format("%.1f,%.1f", w[3], w[4])
					local key = a1 < a2 and (a1 .. "|" .. a2) or (a2 .. "|" .. a1)
					groups[key] = groups[key] or (w.k == 3)
				end
			end
		end
		local any = false
		for _, soft in pairs(groups) do
			if not soft then return false end
			any = true
		end
		return any
	end
	-- every spot you can walk to near them (any way round: some counters run on a slant) with only
	-- furniture between, or that lies the way they face (a shopkeeper faces the side you talk to
	-- them from, whatever the counter is marked as); the nearest wins, the way they face helping
	local ffx, ffz = person_facing(o, x, z)
	local best
	for k = 0, 23 do
		local ang = k * math.pi / 12
		local cx, cz = math.cos(ang), math.sin(ang)
		local facing_dot = ffx and (cx * ffx + cz * ffz) or 0
		local t = 0.8
		while t <= 2.4 do
			local ax, az = x + cx * t, z + cz * t
			if clear_at3(n, ax, az, y, 0.3) and reachable(ax, az, 0) then
				if facing_dot > 0.5 or crossing(ax, az) then
					local score = t - 0.4 * facing_dot
					if not best or score < best.score then best = { x = ax, z = az, t = t, score = score } end
				end
				break
			end
			t = t + 0.1
		end
	end
	return best
end
-- The spot in front of a sign (or statue) that it can be read from, and the way to face.
-- Signs are set up to be read facing the camera: stand on the camera's side of it (below it on
-- screen) and face up.
function sign_front(n, it)
	if not it.rot or not it.thing or it.item then return nil end
	local ux, uz = screen_axes_g()
	local fx, fz = -ux, -uz
	local _, py = player_pos()
	for _, d in ipairs({ 1.1, 1.4, 0.8, 1.8 }) do
		local x, z = it.x + fx * d, it.z + fz * d
		if not n or clear_at3(n, x, z, py or 0, 0.3) then return { x = x, z = z } end
	end
	return nil
end
local function start_walk()
	local it = sel_item
	if not it then say("Pick something on the list first.") return end
	local px, _, pz = player_pos()
	if not px then say("Cannot walk right now.") return end
	if reach_mark and it.code == map_code() then reach_mark({ it }) end
	if it.unreachable then say(unreachable_msg(it), true) return end
	if BEACON then BEACON = nil end      -- an auto walk takes over from the beacon
	-- a door the story keeps locked for now: no use walking into it (one with a keyhole: you
	-- may have the key, so go)
	if it.locked and not it.lock_key and it.inside_lock then say(it.label:gsub("^%l", string.upper) .. ". It opens from its other side: find the way round to there.", true) return end
	if it.locked and not it.lock_key then say(it.label:gsub("^%l", string.upper) .. ". It will not open yet.", true) return end
	-- things bumped into on earlier walks (often a person who has since moved) are forgotten
	local nv0 = nav_for()
	if nv0 then nv0.bb = {} end
	walk = { x = it.x, z = it.z, tx0 = it.x, tz0 = it.z, gy = it.y0 and (it.y0 + 1) or nil, label = it.label, obj = it.obj, posoff = it.posoff or 0x24, start = frame, code = map_code(), sx = px, sz = pz,
	         best = 1e9, progress = frame, side = 1, side_until = 0, tries = 0, push = 0, exit = (it.kind == 0) or nil, place = place_key(),
	         person = (it.obj and not it.thing and not it.item and not it.monster) or nil,
	         doorlike = (it.kind == 1 and not it.nx) or nil, item = it }
	walk_resume = nil
	if it.nx then
		-- a door: its thin side faces the way in. Start from the side you are on.
		-- (a door in front of its exit box is always entered from the door's own side)
		local sgn = ((px - it.x) * it.nx + (pz - it.z) * it.nz) >= 0 and 1 or -1
		if it.facing then sgn = 1 end
		-- stairs and the like can only be walked into from one end: if a wall or railing closes
		-- off your side of it and not the other, go round to the other
		local nvw = nav_ready()
		if nvw and not it.facing and it.kind == 0 then
			local _, py0 = player_pos()
			local function shut(sg)
				local fx, fz = it.x + it.nx * sg * 1.8, it.z + it.nz * sg * 1.8
				local ex, ez = it.x + it.nx * sg * 0.3, it.z + it.nz * sg * 0.3
				local h = floor_near and floor_near(nvw, fx, fz, py0 or 0, 1.5) or py0 or 0
				return wall_between3(nvw, fx, fz, ex, ez, h)
			end
			-- (only to a side with floor to stand on: past an exit at the edge of a field there
			-- is nothing, and no walls either)
			local function floor_there(sg)
				return #floor_heights(nvw, it.x + it.nx * sg * 1.8, it.z + it.nz * sg * 1.8) > 0
			end
			if shut(sgn) and not shut(-sgn) and floor_there(-sgn) then sgn = -sgn end
		end
		walk.door = { x = it.x, z = it.z, nx = it.nx * sgn, nz = it.nz * sgn, flipped = it.facing or false, wx = it.wx, wz = it.wz }
		local out = it.facing and 1.4 or 1.8
		walk.x, walk.z = it.x + walk.door.nx * out, it.z + walk.door.nz * out
		walk.stage = "front"
	end
	-- a sign: go to the side it can be read from and face it
	if it.rot and it.thing and not it.item then
		local fr = sign_front(nav_ready(), it)
		if fr then
			walk.x, walk.z, walk.obj, walk.face = fr.x, fr.z, nil, { it.x, it.z }
			local lb = it.label:gsub("%.+$", "")
			walk.face_msg = "In front of " .. lb .. ". Press A to read it."
			say("Walking to the front of " .. lb .. ". Press any button to stop.", true)
			return
		end
	end
	-- someone behind a counter: go round to the front of it
	if it.obj and not it.nx then
		local n = nav_ready()
		local _, py = player_pos()
		local ap = n and counter_approach(n, it.x, it.z, it.y0 or py or 0, it.obj)
		if ap then
			walk.x, walk.z, walk.obj, walk.face = ap.x, ap.z, nil, { it.x, it.z }
			say("Walking to " .. it.label .. ", across the counter. Press any button to stop.", true)
			return
		end
	end
	say("Walking to " .. it.label .. ". Press any button to stop.", true)
end
-- The way to press to face something square on (up, down, left or right on the screen), not on
-- a slant: on a slant, A can go to whoever stands beside it instead
function cardinal_dir(fx, fz)
	local ux, uz, rx, rz = screen_axes()
	local f, r = fx * ux + fz * uz, fx * rx + fz * rz
	local vx, vz
	if math.abs(f) >= math.abs(r) then vx, vz = (f >= 0 and ux or -ux), (f >= 0 and uz or -uz)
	else vx, vz = (r >= 0 and rx or -rx), (r >= 0 and rz or -rz) end
	return dir_toward(vx, vz)
end
-- Exits such as stairs: the map of walls cannot always reach the exit box itself (a stairway
-- goes down out of the floor). Near it, walk straight into it: toward it, then along each of
-- the two screen directions it lies in, until the place changes.
function start_exit_push(w, px, pz)
	if w.door then w.x, w.z, w.obj = w.door.x, w.door.z, nil end      -- the exit box itself
	local dx, dz = w.x - px, w.z - pz
	local main = dir_toward(dx, dz)
	local tries = { main }
	if main % 2 == 1 then tries[#tries + 1] = (main - 1) % 8 tries[#tries + 1] = (main + 1) % 8
	else tries[#tries + 1] = (main - 1) % 8 tries[#tries + 1] = (main + 1) % 8 end
	-- then past it (the exit box of a stairway can sit just beyond the top step)
	w.pushing = { tries = tries, i = 1, since = frame, best = 1e9, bx = px, bz = pz, prog = frame, start = frame }
end
function exit_push(w, px, pz, dx, dz, d)
	local p = w.pushing
	local moved = math.abs(px - p.bx) + math.abs(pz - p.bz)
	if moved > 0.15 then p.bx, p.bz, p.prog = px, pz, frame end
	-- stuck against something for a moment, or walking away from it: try the next way
	if frame - p.prog > 20 or (frame - p.since > 30 and d > p.best + 1.0) then
		p.i, p.since, p.best, p.prog = p.i + 1, frame, 1e9, frame
		if not p.tries[p.i] then
			local label, tx, tz = w.label, w.x, w.z
			stop_walk()
			say("As close as you can get. " .. label:gsub("^%l", string.upper) .. " is " .. directions_to(tx, tz) .. ". Try walking into it yourself.", true)
			return
		end
	end
	if d < p.best then p.best = d end
	if frame - p.start > 60 * 8 then stop_walk("At " .. w.label .. ", but it did not take you through. Try walking into it yourself.") return end
	local dir = p.tries[p.i]
	-- the first way keeps aiming at the exit as you move
	if p.i == 1 and d > 0.3 then dir = dir_toward(dx, dz) end
	pcall(function() joypad.set(DIRS[dir + 1]) end)
end
-- A long walk cut short by a monster: once the battle is over and you can move again, walk on
-- to the same place (any button stops it, as always).
walk_resume = nil
function walk_resume_step()
	local r = walk_resume
	if not r or walk then return end
	if not r.battle then
		if in_battle() then r.battle = true
		elseif frame - r.frame > 120 then walk_resume = nil end      -- no battle came: you stopped it
		return
	end
	-- (wait for the battle's last messages to go, and for you to stop pressing buttons to clear
	-- them: a press would stop the walk again straight away)
	if in_battle() or frame - battle_seen_frame < 150 or frame - last_dialogue_frame < 90 or fading()
		or frame - USER_INPUT_FRAME < 45 then return end
	if map_code() ~= r.code or frame - r.frame > 60 * 120 then walk_resume = nil return end
	walk_resume = nil
	sel_item = r.it
	start_walk()
end
local function walk_step(host_pressed)
	if not walk then return end
	local function keep_resume() if walk and walk.item and (frame - walk.start) > 60 then walk_resume = { it = walk.item, code = walk.code, frame = frame } end end
	if host_pressed then keep_resume() stop_walk("Stopped.") return end
	if map_code() ~= walk.code or (walk.place and place_key() ~= walk.place) then stop_walk() return end   -- went through a door
	if in_battle() or frame - last_dialogue_frame < 10 then
		if in_battle() then keep_resume() if walk_resume then walk_resume.battle = true end end
		stop_walk() return
	end
	local px, _, pz = player_pos()
	if not px then stop_walk() return end
	if walk.obj then                                                     -- people move: follow them
		local x, z = s32(walk.obj + walk.posoff) / 4096, s32(walk.obj + walk.posoff + 8) / 4096
		if math.abs(x) < 2000 and math.abs(z) < 2000 then walk.x, walk.z = x, z end
	end
	if frame - walk.start > 60 * 240 then stop_walk("Could not get there.") return end
	local dx, dz = walk.x - px, walk.z - pz
	local d = math.sqrt(dx * dx + dz * dz)
	if WALK_DEBUG and frame % 6 == 0 then
		local pts = {}
		for k, q in ipairs(walk.path or {}) do if k >= (walk.pi or 1) then pts[#pts + 1] = string.format("(%.1f,%.1f)", q[1], q[2]) end end
		log_line(string.format("walk pos %.2f %.2f stage %s tgt %.2f %.2f rem %s push %s path %s", px, pz, tostring(walk.stage), walk.x, walk.z, tostring(walk.rem), tostring(walk.pushing and walk.pushing.i), table.concat(pts, " ")))
	end
	if walk.pushing then exit_push(walk, px, pz, dx, dz, d) return end
	-- in front of the door (or as near to the spot in front as the route goes: the spot in front
	-- of a stairway can be too close to a wall to stand on)
	local route_done = walk.path and not walk.path[walk.pi] and (walk.rem or 0) <= 1.0
	if walk.stage == "front" and (d < 0.5 or (route_done and d < 1.3)) then
		walk.stage, walk.x, walk.z = "in", walk.door.x - walk.door.nx * 0.6, walk.door.z - walk.door.nz * 0.6
		-- through the door and on into the exit box behind it
		if walk.door.wx then walk.x, walk.z = walk.door.wx - walk.door.nx * 0.5, walk.door.wz - walk.door.nz * 0.5 end
		walk.best, walk.progress, walk.tries, walk.follow, walk.stall, walk.path, walk.co = 1e9, frame, 0, nil, 0, nil, nil
		return
	end
	-- a door with no exit behind it (one inside a building, or a town's shop door the map does
	-- not give a way through for): walk on through it, the way you came at it
	if walk.doorlike and not walk.door and d < 1.0 and d > 0.05 then
		local nx, nz = (px - walk.x) / d, (pz - walk.z) / d
		walk.door = { x = walk.x, z = walk.z, nx = nx, nz = nz, flipped = true }
		walk.stage, walk.x, walk.z = "in", walk.x - nx * 1.2, walk.z - nz * 1.2
		walk.best, walk.progress, walk.tries, walk.push, walk.follow, walk.stall, walk.path, walk.co = 1e9, frame, 0, 0, nil, 0, nil, nil
		return
	end
	if walk.stage == "in" and walk.doorlike and d < 0.4 then stop_walk("Through " .. walk.label .. ".") return end
	if walk.stage == "in" then
		if d < 0.3 then walk.push = walk.push + 1 end
		if walk.push > 40 or (frame - walk.progress > 40) then
			if not walk.door.flipped then
				-- nothing opened from this side: try the other side of the door
				local dr = walk.door
				dr.nx, dr.nz, dr.flipped = -dr.nx, -dr.nz, true
				walk.stage, walk.x, walk.z = "front", dr.x + dr.nx * 1.8, dr.z + dr.nz * 1.8
				walk.best, walk.progress, walk.tries, walk.push, walk.follow, walk.stall, walk.path, walk.co = 1e9, frame, 0, 0, nil, 0, nil, nil
				return
			end
			if walk.label == "entrance" then stop_walk("At the entrance. Walk into it or press A.") return end
			-- the game can take a moment to say a door is locked: wait for it before giving up
			walk.giveup = walk.giveup or frame
			if door_locked_text() then
				local label = walk.label
				stop_walk()
				door_locked.said = frame
				say(label:gsub("^%l", string.upper) .. " is locked.", true)
				return
			end
			if frame - walk.giveup < 40 then return end
			stop_walk("At " .. walk.label .. ", but it did not open. Try walking into it yourself.") return
		end
	elseif walk.exit and not walk.door and d < 0.7 then
		start_exit_push(walk, px, pz) return
	elseif not walk.door and d < (walk.obj and 1.4 or (walk.face and 0.35 or 0.7)) then
		-- (across a counter, the talk only reaches straight across: get right in front of them)
		-- next to someone: turn to them, so A talks to them
		if walk.obj and not walk.face then walk.face = { walk.x, walk.z } walk.face_msg = "Arrived at " .. walk.label .. "." end
		if walk.face then
			-- turn to face them across the counter
			walk.face_end = walk.face_end or frame + 10
			if frame < walk.face_end then
				local fx, fz = walk.face[1] - px, walk.face[2] - pz
				pcall(function() joypad.set(DIRS[dir_toward(fx, fz) + 1]) end)
				return
			end
			stop_walk(walk.face_msg or ("Arrived at " .. walk.label .. ", across the counter. Press A to talk.")) return
		end
		stop_walk("Arrived at " .. walk.label .. ".") return
	end
	if math.abs(px - walk.sx) + math.abs(pz - walk.sz) > 0.3 then walk.moved = true end
	if not walk.moved and frame - (walk.checked_from or walk.start) > 150 and not walk.co then stop_walk("You cannot move right now.") return end
	if walk.stage == "in" then
		-- straight into the door
		if d < walk.best - 0.25 then walk.best, walk.progress = d, frame end
		pcall(function() joypad.set(DIRS[dir_toward(dx, dz) + 1]) end)
		return
	end
	-- Follow a planned route when the map's walls are known.
	local nv = not walk.nopath and nav_for()
	if nv then
		if walk.path and walk.obj and ((walk.x - walk.goal[1]) ^ 2 + (walk.z - walk.goal[2]) ^ 2) > 4 then walk.path = nil end
		if not walk.path then
			if not walk.co then
				local sx, sz, gx, gz = px, pz, walk.x, walk.z
				walk.goal = { gx, gz }
				local avoid = avoid_list(walk.tx0, walk.tz0, px, pz)
				nv.py = select(2, player_pos())
				local sy = select(2, player_pos())
				local gy = walk.gy
				walk.co = coroutine.create(function()
					local p, rem = plan_path(nv, sx, sy, sz, gx, gz, gy, 0.45, true, 20000, avoid)
					-- a narrow way (between a wall and a stair rail): try again keeping less room
					if rem > 1.0 then
						local p2, rem2 = plan_path(nv, sx, sy, sz, gx, gz, gy, 0.3, true, 20000, avoid)
						if rem2 < rem - 0.4 then p, rem = p2, rem2 end
					end
					-- a narrow winding stair (Brigadoom's eastern tower): less room still (only for
					-- somewhere near: out in a big field each try is a long search)
					if rem > 1.0 and (gx - sx) ^ 2 + (gz - sz) ^ 2 < 400 then
						local p2, rem2 = plan_path(nv, sx, sy, sz, gx, gz, gy, 0.2, true, 20000, avoid)
						if rem2 < rem - 0.4 then p, rem = p2, rem2 end
					end
					if rem > 1.5 then
						local p2, rem2 = find_path(nv, sx, sz, gx, gz, 0.3, false, 20000, avoid)
						if rem2 < rem - 1 then p, rem = p2, rem2 end
					end
					return p, rem
				end)
			end
			local ok, p, rem = plan_resume(walk.co)
			if not ok then
				walk.nopath, walk.co = true, nil
			elseif coroutine.status(walk.co) == "dead" then
				walk.co, walk.path, walk.pi, walk.wbest, walk.wprog, walk.rem = nil, p or {}, 1, 1e9, frame, rem or 0
				walk.plan_d = math.sqrt((walk.x - px) ^ 2 + (walk.z - pz) ^ 2)
				walk.seg0 = { px, pz }
				walk.checked_from = frame
			end
			return
		end
		local wp = walk.path[walk.pi]
		while wp and ((wp[1] - px) ^ 2 + (wp[2] - pz) ^ 2) < 0.25 do
			walk.seg0 = { wp[1], wp[2] }
			walk.pi, walk.wbest, walk.wprog = walk.pi + 1, 1e9, frame
			wp = walk.path[walk.pi]
		end
		if wp then
			local wx, wz = wp[1] - px, wp[2] - pz
			local wd = math.sqrt(wx * wx + wz * wz)
			-- Keep to the line between the waypoints: with only eight directions to press, aiming
			-- straight at a far waypoint drifts sideways (off the top of a stairway). Aim at a
			-- point on the line a little ahead of you instead.
			local s0 = walk.pi > 1 and walk.path[walk.pi - 1] or walk.seg0 or { walk.sx, walk.sz }
			local ax, az = wp[1] - s0[1], wp[2] - s0[2]
			local L = math.sqrt(ax * ax + az * az)
			local aimx, aimz = wx, wz
			if L > 0.5 then
				local t = ((px - s0[1]) * ax + (pz - s0[2]) * az) / L
				local ahead = math.min(L, math.max(0, t) + 0.5)
				aimx, aimz = s0[1] + ax / L * ahead - px, s0[2] + az / L * ahead - pz
			end
			if wd < walk.wbest - 0.2 then walk.wbest, walk.wprog = wd, frame end
			if frame - walk.wprog > 30 then
				-- something the walls do not show is in the way: remember it and plan around it
				walk.replans = (walk.replans or 0) + 1
				if walk.replans > 12 then walk.nopath = true return end
				nav_block(nv, px + wx / math.max(wd, 0.01) * 0.8, pz + wz / math.max(wd, 0.01) * 0.8, 0.5)
				walk.path = nil
				return
			end
			pcall(function() joypad.set(DIRS[dir_toward(aimx, aimz) + 1]) end)
			return
		end
		-- the route is done: the last bit is straight
		dx, dz = walk.x - px, walk.z - pz
		if walk.exit and (walk.rem or 0) > 1.0 and d < 4 then start_exit_push(walk, px, pz) return end
		if walk.door and (walk.rem or 0) > 3.0 and walk.stage == "front" and not walk.door.flipped and not walk.exit then
			-- no way to this side of the door: try its other side
			local dr = walk.door
			dr.nx, dr.nz, dr.flipped = -dr.nx, -dr.nz, true
			walk.x, walk.z = dr.x + dr.nx * 1.8, dr.z + dr.nz * 1.8
			walk.path, walk.co, walk.best, walk.progress = nil, nil, 1e9, frame
			return
		end
		if walk.door and (walk.rem or 0) > 3.0 and walk.stage == "front" and walk.door.flipped and not walk.exit then
			-- a door on the far side of a wall: reached from another part of the place
			local label = walk.label
			stop_walk()
			say("There is no way to " .. label .. " from here. It is reached from another part of this place, through another door.", true)
			return
		end
		-- a long way across a big field: the plan only reaches so far. Got a good way nearer:
		-- plan on from here instead of stopping
		local dnow = math.sqrt(dx * dx + dz * dz)
		if (walk.rem or 0) > 1.0 and dnow > 4 and walk.plan_d and dnow < walk.plan_d - 3 and (walk.extends or 0) < 12 then
			walk.extends = (walk.extends or 0) + 1
			walk.path, walk.co, walk.final = nil, nil, nil
			return
		end
		if (walk.rem or 0) > 1.0 and walk.stage ~= "in" then
			-- the route could not reach it (a shop counter, a fence): turn to face it and stop here
			-- someone close by, straight up, down, left or right: most likely across a counter,
			-- and the game lets you talk across one, so face them square on
			local ux, uz, rx, rz = screen_axes()
			local f, r = dx * ux + dz * uz, dx * rx + dz * rz
			local square = walk.person and math.sqrt(dx * dx + dz * dz) < 3.3 and math.min(math.abs(f), math.abs(r)) < 0.8
			local face = math.abs(f) >= math.abs(r) and (f >= 0 and "up" or "down") or (r >= 0 and "right" or "left")
			walk.final = walk.final or frame + 12
			if frame < walk.final then
				local dir = dir_toward(dx, dz)
				-- right by it (a treasure chest a step away): face it square on, not on a slant,
				-- or A goes to whoever stands beside it
				if square or math.sqrt(dx * dx + dz * dz) < 2.2 then dir = cardinal_dir(dx, dz) end
				pcall(function() joypad.set(DIRS[dir + 1]) end)
				return
			end
			local label, tx, tz = walk.label, walk.x, walk.z
			stop_walk()
			if square then
				pcall(sound.play, "chime", 0, 0, -0.5, 0.8)
				say("As close as you can get. " .. label:gsub("^%l", string.upper) .. " is " .. directions_to(tx, tz) .. ", most likely across a counter. Facing " .. face .. ". Press A to talk.", true)
			elseif math.sqrt(dx * dx + dz * dz) < 1.6 then
				-- a step away and turned to it (a treasure chest against a wall): that is there
				pcall(sound.play, "chime", 0, 0, -0.5, 0.8)
				say("In front of " .. label .. ", " .. directions_to(tx, tz) .. ". Press A.", true)
			else
				say("As close as you can get. " .. label:gsub("^%l", string.upper) .. " is " .. directions_to(tx, tz) .. ".", true)
			end
			return
		end
	end
	-- Head straight for the target. When a wall stops you, follow the wall (keeping it on one
	-- side) until you are closer than where you hit it, then head straight again. If one side
	-- leads nowhere for a long time, try the other side.
	walk.tick = walk.tick or frame
	walk.tx = walk.tx or px
	walk.tz = walk.tz or pz
	walk.hand = walk.hand or 1
	walk.dir = walk.dir or dir_toward(dx, dz)
	if frame - walk.tick >= 8 then
		local moved = math.sqrt((px - walk.tx) ^ 2 + (pz - walk.tz) ^ 2)
		walk.tick, walk.tx, walk.tz = frame, px, pz
		local goal = dir_toward(dx, dz)
		local f = walk.follow
		if not f then
			if moved < 0.2 then walk.stall = (walk.stall or 0) + 1 else walk.stall = 0 end
			walk.dir = goal
			if walk.stall >= 2 then
				walk.stall = 0
				walk.follow = { h = (goal - 2 * walk.hand) % 8, hit = d, since = frame, best = d, good = 0 }
				walk.dir = walk.follow.h
			end
		else
			if d < f.best - 0.25 then f.best, f.since = d, frame end
			if d < f.hit - 1.0 then
				walk.follow, walk.dir, walk.stall = nil, goal, 0
			else
				if moved >= 0.2 then
					f.good = f.good + 1
					if f.good >= 2 then f.good = 0 f.h = (f.h + walk.hand) % 8 end   -- lean back toward the wall
				else
					f.good = 0
					f.h = (f.h - walk.hand) % 8                                     -- turn away from it
				end
				walk.dir = f.h
				if frame - f.since > 60 * 20 then
					walk.flips = (walk.flips or 0) + 1
					if walk.flips > 3 then stop_walk("Could not find a way there. Try walking part of the way, then press J again.") return end
					walk.hand = -walk.hand
					walk.follow = { h = (goal - 2 * walk.hand) % 8, hit = d, since = frame, best = d, good = 0 }
					walk.dir = walk.follow.h
				end
			end
		end
	end
	local b = {}
	for k, v in pairs(DIRS[walk.dir + 1]) do b[k] = v end	pcall(function() joypad.set(b) end)
end

------------------------------------------------------------------------------ alerts --------
-- "The door is locked.": the game leaves those words in its message buffer (and lets you go on
-- walking while it shows them), so walking into the same locked door again shows the message
-- with nothing new to read. Walking into a door that the buffer says is locked: say it again.
door_locked = { said = -1000 }
function door_locked_text()
	local t = clean(cstring(DLG, 120))
	if t:find("is locked", 1, true) then return t end
	return nil
end
local still_frames, last_px, last_pz, bumped = 0, nil, nil, false
local close_to = {}

-- the bump sound: a thud from the way you are pushing, a moment after you stop against something
-- (quicker than the spoken "blocked", and it says which side)
BUMP = { still = 0, done = false, lx = nil, lz = nil }
function bump_sound(pad)
	if not BUMP_SOUND_ON or not sound then return end
	local px, _, pz = player_pos()
	if not px then return end
	local push = pad.up or pad.down or pad.left or pad.right
	local b = BUMP
	if push and u8(0x02109DA4) == 1 and b.lx and math.abs(px - b.lx) < 0.01 and math.abs(pz - b.lz) < 0.01
	   and frame - last_dialogue_frame > 60 and frame - last_menu_frame > 120 and not in_battle() and not walk then
		b.still = b.still + 1
		if b.still == 5 and not b.done then
			b.done = true
			local x = (pad.right and 1 or 0) - (pad.left and 1 or 0)
			local z = (pad.down and 1 or 0) - (pad.up and 1 or 0)
			pcall(sound.play, "bump", x * 1.2, -0.3, z * 1.2, 0.9)
		end
	else
		b.still = 0
		if not push or (b.lx and (math.abs(px - b.lx) > 0.02 or math.abs(pz - b.lz) > 0.02)) then b.done = false end
	end
	b.lx, b.lz = px, pz
end

local function alerts(pad)
	-- Battle Records' screens leave the game's "walking" mark on: pushing the D-pad there is not
	-- walking into anything (until you are seen to move again)
	do
		local qx, _, qz = player_pos()
		if qx and last_px and (math.abs(qx - last_px) > 0.01 or math.abs(qz - last_pz) > 0.01) then
			if rec then rec.spoke_frame = nil end
			if ui then ui.spoke_frame = nil end
		end
		if (rec and rec.spoke_frame and frame - rec.spoke_frame < 3600) or (ui and ui.spoke_frame and frame - ui.spoke_frame < 3600) then
			last_px, last_pz = qx, qz
			return
		end
	end
	pcall(bump_sound, pad)
	if not ALERTS_ON then return end
	local px, _, pz = player_pos()
	if not px then return end
	local moving_input = pad.up or pad.down or pad.left or pad.right
	if moving_input and u8(0x02109DA4) == 1 and last_px and math.abs(px - last_px) < 0.01 and math.abs(pz - last_pz) < 0.01
	   and frame - last_dialogue_frame > 60 and frame - last_menu_frame > 120
	   and not in_battle() and not pending and kb_name == nil and not gk.on    -- (not while typing a name)
	   and frame - code_changed_frame > 60 and not fading() then
		still_frames = still_frames + 1
		if still_frames == 12 and not bumped then
			bumped = true
			-- against a door the game says is locked: say that
			local lt = door_locked_text()
			if lt then
				lt = nil
				for _, d in ipairs(doors()) do
					if d.kind == 1 and (d.x - px) ^ 2 + (d.z - pz) ^ 2 < 4 then lt = door_locked_text() break end
				end
			end
			say(lt or "blocked", true)
		end
	else
		still_frames = 0
		if not moving_input or (last_px and (math.abs(px - last_px) > 0.02 or math.abs(pz - last_pz) > 0.02)) then
			bumped = false
		end
	end
	last_px, last_pz = px, pz
	-- someone right next to you (off: the nearby list is where you hear about people and monsters)
	if NEARBY_ALERTS and frame % 10 == 0 and not in_battle() and frame - last_dialogue_frame > 60 and not pending then
		local around = characters()
		for _, m in ipairs(monsters()) do around[#around + 1] = m end
		for _, c in ipairs(around) do
			local d = math.sqrt((c.x - px) ^ 2 + (c.z - pz) ^ 2)
			local near = c.monster and 5 or 1.8
			if d > near + 1.2 then close_to[c.obj] = nil end
			if d < near and not close_to[c.obj] then
				close_to[c.obj] = true
				queue(c.label .. " " .. directions_to(c.x, c.z))
			end
		end
	end
end

------------------------------------------------------------------------------ party ---------
REC0, REC_SIZE = 0x020F3888, 0x964
VOCATIONS = { [0] = "", "Warrior", "Priest", "Mage", "Martial Artist", "Thief", "Minstrel",
	"Gladiator", "Armamentalist", "Paladin", "Sage", "Luminary", "Ranger" }
IN_BATTLE = 0x020EF0E8

local function party_records()
	local list = {}
	local hero = cstring(0x020FB258, 12)
	for k = 0, 3 do
		local n = REC0 + k * REC_SIZE
		local name = cstring(n, 12)
		local maxhp = u16(n + 0x30)
		if printable(name) and maxhp > 1 and maxhp < 1000 and name ~= "NineJJ" then
			local r = { addr = n, name = name, hp = u16(n - 0x20), mp = u16(n - 0x1E), maxhp = maxhp,
			            maxmp = u16(n + 0x32), voc = u8(n + 0x914) }   -- the vocation (a word at +0x914)
			local lv = u16(n + 0x130 + 2 * r.voc)
			if lv > 0 and lv < 100 then r.level = lv end
			r.slot = k
			if name == hero then table.insert(list, 1, r) r.hero = true else list[#list + 1] = r end
		end
	end
	-- the hero's name is not always where it is looked for; the hero's record is the last of the
	-- four (the companions fill them from the first), and the party goes hero first, then the
	-- companions in the order they joined, as on the battle screen
	if not (list[1] and list[1].hero) then
		for i, r in ipairs(list) do
			if r.slot == 3 and i > 1 then table.remove(list, i) table.insert(list, 1, r) break end
		end
	end
	return list
end
party_records_g = party_records

-- Experience: remember everyone's total outside battles; the battle adds the reward just before
-- "... receives some experience!", so the difference is what was earned.
local exp_before = {}
battle_seen_frame, exp_frozen, exp_freeze_pos = -1000, false, nil
local function snapshot_experience()
	for _, r in ipairs(party_records()) do exp_before[r.name] = u32(r.addr + 0x114) end
end
experience_fix = function(text)
	if not text:lower():find("experience", 1, true) then return text end
	local gains = {}
	for _, r in ipairs(party_records()) do
		local before = exp_before[r.name]
		local now = u32(r.addr + 0x114)
		if before and now > before and now - before < 10000000 then gains[#gains + 1] = { r.name, now - before } end
	end
	if #gains == 0 then return text end
	if #gains == 1 and text:find("some experience", 1, true) then
		return (text:gsub("some experience", gains[1][2] .. " experience points"))
	end
	local parts = {}
	for _, g in ipairs(gains) do parts[#parts + 1] = g[1] .. " " .. g[2] end
	return text .. " Experience: " .. table.concat(parts, ", ") .. "."
end

-- In a battle the live numbers are kept in the battle's own copy of each fighter. Find it once per
-- battle by looking for the leader's maximum HP and MP side by side, then trust it while it checks out.
BATTLE_STRIDE = 0x448

-- Whose turn it is to pick a command: the battle keeps the number of that fighter here
-- (fighters are 0x448 bytes apart, in the battle's own order), with max HP and MP at the start.
BATTLE_ACTOR_IDX, BATTLE_FIGHTER0 = 0x0239532C, 0x02395B10
function battle_actor_name()
	local idx = u8(BATTLE_ACTOR_IDX)
	if idx > 3 then return nil end
	local b = BATTLE_FIGHTER0 + idx * BATTLE_STRIDE
	if u32(b - 8) - u32(b - 4) ~= 0x18 then return nil end
	local mh, mm = u16(b), u16(b + 2)
	if u16(b + 4) == 0 then return nil end            -- the dead do not pick commands
	local found = nil
	for _, r in ipairs(party_records()) do
		if r.maxhp == mh and r.maxmp == mm then
			if found then return nil end        -- two alike: can't tell
			found = r.name
		end
	end
	return found
end
function turn_text(name)
	return (name:gsub("^%l", string.upper)) .. "'s turn. "
end

-- everyone's HP and MP right now (in a battle, from the fighters)
-- In a battle the records keep the HP and MP from before it; the battle's own fighters (0x448
-- bytes apart from BATTLE_FIGHTER0, in their own order: max HP, max MP, HP, MP) have them now.
-- Each fighter goes to the party member with the same max HP and max MP.
function battle_values(members)
	if #members == 0 or not in_battle() then return members end
	local used = {}
	for i = 0, 3 do
		local b = BATTLE_FIGHTER0 + i * BATTLE_STRIDE
		if inram(b, 8) and u32(b - 8) - u32(b - 4) == 0x18 then
			local mh, mm, hp, mp = u16(b), u16(b + 2), u16(b + 4), u16(b + 6)
			if mh > 0 and hp <= mh and mp <= mm then
				for _, r in ipairs(members) do
					if not used[r] and r.maxhp == mh and r.maxmp == mm then
						r.hp, r.mp, used[r] = hp, mp, true
						break
					end
				end
			end
		end
	end
	return members
end
function party_now()
	return battle_values(party_records())
end
-- H: everyone's HP.  M: everyone's MP.
function say_hp_mp(which)
	local members = party_now()
	if #members == 0 then say("No party information.") return end
	local parts = {}
	for _, r in ipairs(members) do
		local name = r.name:gsub("^%l", string.upper)
		if which == "hp" then
			parts[#parts + 1] = name .. (r.hp == 0 and ", dead" or (", " .. r.hp .. " of " .. r.maxhp .. " HP"))
		elseif r.maxmp > 0 then
			parts[#parts + 1] = name .. ", " .. r.mp .. " of " .. r.maxmp .. " MP"
		else
			parts[#parts + 1] = name .. ", no MP"
		end
	end
	say(table.concat(parts, ". "), true)
end
local function say_party(short)
	local members = battle_values(party_records())
	if #members == 0 then say("No party information.") return end
	local in_battle = in_battle()
	local parts = {}
	for _, r in ipairs(members) do
		local s = r.name .. ", " .. r.hp .. " of " .. r.maxhp .. " HP"
		if r.maxmp > 0 then s = s .. ", " .. r.mp .. " of " .. r.maxmp .. " MP" end
		if not in_battle and not short then
			local voc = VOCATIONS[r.voc]
			if r.level then s = s .. ", level " .. r.level end
			if voc and voc ~= "" then s = s .. " " .. voc end
		end
		parts[#parts + 1] = s
	end
	say(table.concat(parts, ". "), true)
end


-- Each party record keeps the names of the equipment it is drawn with, in lower case, 0x30 bytes
-- apart starting at +0x534. Slot order seen in the game: body, legs, (2), feet, (4), weapon, shield.
-- Slots 2 and 4 were empty on every save tested; they are taken to be arms and head.
EQUIP_SLOTS = { { 5, "weapon" }, { 6, "shield" }, { 4, "head" }, { 0, "body" },
	{ 2, "arms" }, { 1, "legs" }, { 3, "feet" } }
local function say_equipment()
	local out = {}
	for _, r in ipairs(party_records()) do
		local worn = {}
		for _, slot in ipairs(EQUIP_SLOTS) do
			local item = clean(cstring(r.addr + 0x534 + slot[1] * 0x30, 0x30))
			if item ~= "" and printable(item) then worn[#worn + 1] = slot[2] .. " " .. item end
		end
		out[#out + 1] = r.name .. ": " .. (#worn > 0 and table.concat(worn, ", ") or "nothing equipped")
	end
	say(#out > 0 and table.concat(out, ". ") or "No party information.")
end

-- The equipment screen draws its list as pictures, so it is read here: the list control has a
-- recognisable shape (count, 1, 1, count, ..., cursor, then four pointers back into itself).
EQUIP_LIST = 0x0230FBB8
EQUIP_SCREEN_SLOTS = { { 5, "Weapon" }, { 6, "Shield" }, { 4, "Head" }, { 0, "Body" },
	{ 2, "Arms" }, { 1, "Legs" }, { 3, "Feet" }, { nil, "Accessory" } }
local equip_cursor = nil
local function list_control_ok(b, count)
	return u32(b) == count and u32(b + 0x20) == b + 8 and u32(b + 0x24) == b + 0xC
		and u32(b + 0x28) == b + 0x18 and u32(b + 0x2C) == b + 0x1C
end
EQUIP_SHOWN = 0x0230FB78          -- number of the item the top screen is showing
local equip_grid_item = nil
local function item_name(id)
	if id == 0xFFFF or id == 0 then return nil end
	local n = ITEM_NAMES[id]
	return n and (n:gsub("^%l", string.upper)) or ("item " .. id)
end
local equip_state, equip_due = nil, nil
------------------------------------------------------------------------------ shop screens --
-- Shops (and other screens built the same way) are laid out as a numbered list of boxes: text
-- boxes point at their words, number boxes hold a number (a price). The screen remembers which
-- box the cursor is on, so the script reads that box and the other boxes on the same line.
LAYOUT_PTR = 0x02108EE4
local lay_state, lay_pending, lay_since = nil, nil, 0
lay_base, lay_base_since = nil, 0
ls_cache, ls_table = {}, nil
function layout_string_raw(t, sid)
	local e, n = u32(t), u16(t + 4)
	if n > 2000 or not inram(e, n * 8) then return nil end
	for k = 0, n - 1 do
		if u16(e + k * 8) == sid then          -- the upper half of the id is sometimes junk
			local s = clean(cstring(u32(e + k * 8 + 4), 80))
			if s ~= "" and not s:match("^<") then return s end
			return nil
		end
	end
	return nil
end
local function layout_string(L, sid)
	local t = u32(L)
	if not inram(t, 8) then return nil end
	if t ~= ls_table then ls_cache, ls_table = {}, t end
	local c = ls_cache[sid]
	if type(c) == "string" then return c end
	if type(c) == "number" and frame - c < 30 then return nil end
	local v = layout_string_raw(t, sid)
	ls_cache[sid] = v or frame
	return v
end
local function layout_box(L, W, i)
	local a = W + 0x30 * i
	local v, fl = u32(a), u16(a + 0x12)
	local kind = fl >> 8
	if kind == 0xFA or kind == 0xAA then
		if inram(v, 1) then
			local s = clean(cstring(v, 80))
			if s ~= "" then return (s:gsub("^%l", string.upper)) end
		end
		local sid = u16(a + 0x0E)
		if sid ~= 0xFFFF then return layout_string(L, sid) end
	elseif (kind == 0xF8 or kind == 0xA8) and (fl & 0xFF) == 3 then
		return tostring(v)
	end
	return nil
end
-- The next fighter's command list can look exactly like the last one, so the menu reader
-- sees no change: say whose turn it is once the turn has moved on and held still.
battle_actor_since, battle_actor_seen = 0, nil
battle_actor_text, battle_actor_frame, battle_start_frame = nil, -1000, nil
function watch_battle_actor()
	if not in_battle() then battle_actor_said, battle_actor_seen, battle_start_frame, battle_fight_seen = nil, nil, nil, nil return end
	battle_start_frame = battle_start_frame or frame
	-- back at Fight / Examine / Flee: the first fighter's turn is news again
	if menu_raw_seen:find("<N=0>Fight</N>", 1, true) then battle_actor_said, battle_fight_seen = nil, true end
	if not battle_fight_seen and frame - battle_start_frame < 240 then return end
	-- the list left over from the last battle is not this battle's
	if last_menu_frame <= battle_start_frame or frame - last_menu_frame < 20 then return end
	if battle_phase() ~= 3 or not menu_raw_seen:find("<N=0>Attack</N>", 1, true) then return end
	local who = battle_actor_name()
	if who ~= battle_actor_seen then battle_actor_seen, battle_actor_since = who, frame return end
	if not who or who == battle_actor_said or frame - battle_actor_since < 8 then return end
	if frame - last_menu_spoken < 8 then return end
	local cursor = tonumber(menu_raw_seen:match("<CURSOR=(%d+)>") or "")
	local items, count = parse_menu(menu_raw_seen)
	pcall(mon_label_list, items, menu_raw_seen)
	local it = cursor and items[cursor]
	if not it then return end
	battle_actor_said = who
	battle_actor_text, battle_actor_frame = describe_item(it, cursor, count), frame
	last_menu_spoken = frame
	say(turn_text(who) .. battle_actor_text, true)
end

-- The "How many?" window (buying or selling several of an item) is part of the same layout as
-- the list under it: a box holding "How many?", then the number chosen and the total price.
-- The layout also lists its windows (+0x0C, count +0x10, 0x18 bytes each: the boxes in it +0,
-- window number +8, x y w h +0x0A, how many boxes +0x13). The windows on screen are kept in
-- slots of 0xE0 bytes after the window keeper (+0x30): width, height, x, y at +4 and the
-- window number at +0x20. While buying, a window under the list says how many each person
-- and the bag already hold: a name with a number on the same line.
qty = { W = nil, idx = nil, checked = -1000, said = nil, pending = nil, since = 0 }
function layout_windows(L)
	local t, n = u32(L + 0x0C), u16(L + 0x10)
	if n == 0 or n > 64 or not inram(t, n * 0x18) then return {} end
	local out = {}
	for k = 0, n - 1 do
		local e = t + k * 0x18
		local list, c = u32(e), u8(e + 0x13)
		local boxes = {}
		if c > 0 and c < 64 and inram(list, c * 2) then
			for j = 0, c - 1 do boxes[#boxes + 1] = u16(list + j * 2) end
		end
		out[#out + 1] = { id = u16(e + 8), x = u16(e + 0x0A), y = u16(e + 0x0C), w = u16(e + 0x0E), h = u16(e + 0x10), boxes = boxes }
	end
	return out
end
function window_open(L, win)
	local m = u32(L + 0x30)
	if not inram(m, 0xA4 + 16 * 0xE0) then return false end
	for k = 0, 15 do
		local sl = m + 0xA4 + k * 0xE0
		if u8(sl + 0x20) == (win.id & 0xFF) and u16(sl + 4) == win.w and u16(sl + 6) == win.h
			and u16(sl + 8) == win.x and u16(sl + 0x0A) == win.y then return true, u8(sl + 0x21) end
	end
	return false
end
function qty_find(L, W, count)
	if qty.W == W and qty.idx then return qty.idx end
	if qty.W == W and frame - qty.checked < 60 then return nil end
	qty.W, qty.idx, qty.checked, qty.win = W, nil, frame, nil
	for i = 0, count - 1 do
		local a = W + 0x30 * i
		local k, sid = u16(a + 0x12) >> 8, u16(a + 0x0E)
		if (k == 0xFA or k == 0xAA) and sid ~= 0xFFFF and layout_string(L, sid) == "How many?" then
			for _, w in ipairs(layout_windows(L)) do
				for _, b in ipairs(w.boxes) do if b == i then qty.win = w end end
			end
			if qty.win then qty.idx = i end
			return qty.idx
		end
	end
	return nil
end
function qty_number(W, i)
	local a = W + 0x30 * i
	local k = u16(a + 0x12)
	if ((k >> 8) == 0xF8 or (k >> 8) == 0xFA or (k >> 8) == 0xA8) and (k & 0xFF) == 3 then return u32(a) end
	return nil
end
-- "Retro 1, Bag 0": the rows of the other windows on screen that are a name and a number
-- (not the list the cursor is in, and not the How many? window itself)
function qty_held(L, W, count, sel, skip)
	local out = {}
	for _, w in ipairs(layout_windows(L)) do
		local mine = false
		for _, b in ipairs(w.boxes) do if b == sel or b == skip then mine = true end end
		local open, how = false, 0
		if not mine and #w.boxes > 1 then open, how = window_open(L, w) end
		-- (+0x21 bit 0x20: a window kept out of sight, such as the empty "Cannot Equip" one)
		if open and how & 0x20 == 0 then
			local names, nums = {}, {}
			for _, i in ipairs(w.boxes) do
				if i < count and box_shown(W, i) then
					local a = W + 0x30 * i
					local n = qty_number(W, i)
					if n then nums[#nums + 1] = { u16(a + 6), u16(a + 8), n }
					elseif (u16(a + 0x12) >> 8) == 0xFA or (u16(a + 0x12) >> 8) == 0xAA then
						local t = layout_box(L, W, i)
						if t and t ~= "" then names[#names + 1] = { u16(a + 6), u16(a + 8), t } end
					end
				end
			end
			table.sort(names, function(x, y) return x[2] < y[2] end)
			for _, nm in ipairs(names) do
				local got = nil
				for _, nu in ipairs(nums) do
					if math.abs(nu[2] - nm[2]) <= 2 and nu[1] > nm[1] + 20 then got = nu[3] break end
				end
				out[#out + 1] = got and (nm[3] .. " " .. got) or nm[3]
			end
		end
	end
	return out
end
-- true while the window is open (the list under it is then left alone)
function read_quantity(L, W, count, sel)
	local i = qty_find(L, W, count)
	if not i or not window_open(L, qty.win) then qty.said, qty.pending = nil, nil return false end
	local n, total = nil, nil
	for j = i + 1, math.min(count - 1, i + 8) do
		local v = qty_number(W, j)
		if v then if not n then n = v elseif not total then total = v break end end
	end
	if not n then return true end
	local line = tostring(n) .. (total and (", " .. total .. " gold") or "")
	if line == qty.said then qty.pending = nil return true end
	if line ~= qty.pending then qty.pending, qty.since = line, frame return true end
	if frame - qty.since < 3 then return true end
	local first = qty.said == nil
	qty.said, qty.pending = line, nil
	if first then
		local text = "How many? " .. line .. ". Up and down change it."
		local held = qty_held(L, W, count, sel, i)
		if #held > 0 then text = text .. " Held: " .. table.concat(held, ", ") .. "." end
		say(text, true)
	else
		say(line, true)
	end
	return true
end

-- A box is drawn while it has a size and bit 0 of +0x2A is clear (the game hides the boxes
-- it does not need, such as "Cannot Equip" for someone who can).
function box_shown(W, i)
	local a = W + 0x30 * i
	return u16(a + 0x0A) ~= 0 and (u8(a + 0x2A) & 1) == 0
end
lw_cache = { L = nil, t = nil, list = nil }
function layout_windows_cached(L)
	local t = u32(L + 0x0C)
	if lw_cache.L ~= L or lw_cache.t ~= t or not lw_cache.list then lw_cache.L, lw_cache.t, lw_cache.list = L, t, layout_windows(L) end
	return lw_cache.list
end
function window_of(L, i)
	for _, w in ipairs(layout_windows_cached(L)) do
		for _, b in ipairs(w.boxes) do if b == i then return w end end
	end
	return nil
end
-- The shop's comparison windows: while browsing, one line per person ("retro 40 > 45",
-- "hero Cannot Equip") under the name of the attribute; on the "Who?" list, one line for the
-- person the cursor is on. Read them as "Retro, Defence up 5, 40 to 45. Hero, cannot equip."
function compare_text(L, W, count, w)
	local items = {}
	local has_cannot = false
	for _, i in ipairs(w.boxes) do
		if i < count and box_shown(W, i) then
			local a = W + 0x30 * i
			local fl, sid = u16(a + 0x12), u16(a + 0x0E)
			local it = { x = u16(a + 6), y = u16(a + 8) }
			if (fl & 0xFF) == 3 and ((fl >> 8) & 0x0F) == 8 then it.num = u32(a)
			elseif ((fl >> 8) & 0x0F) == 0x0A then
				local named = sid ~= 0xFFFF and layout_string(L, sid) or nil
				if named == "Cannot Equip" then it.cannot, has_cannot = true, true
				elseif named == "Equipped" then it.equipped = true
				elseif named then it.label = named
				else it.name = layout_box(L, W, i) end
			end
			if it.num or it.cannot or it.equipped or it.label or it.name then items[#items + 1] = it end
		end
	end
	-- only the windows that can say "Cannot Equip" or "Equipped" are comparisons
	local can_say = false
	for _, i in ipairs(w.boxes) do
		local sid = u16(W + 0x30 * i + 0x0E)
		local t = sid ~= 0xFFFF and layout_string(L, sid) or nil
		if t == "Cannot Equip" or t == "Equipped" then can_say = true break end
	end
	if not can_say then return nil end
	table.sort(items, function(p, q) if p.y ~= q.y then return p.y < q.y end return p.x < q.x end)
	local rows, row = {}, nil
	for _, it in ipairs(items) do
		if not row or math.abs(it.y - row.y) > 2 then row = { y = it.y, nums = {} } rows[#rows + 1] = row end
		if it.num then row.nums[#row.nums + 1] = it.num end
		if it.cannot then row.cannot = true end
		if it.equipped then row.equipped = true end
		if it.label then row.label = it.label end
		if it.name then row.name = it.name end
	end
	local stat, out = nil, {}
	for _, r in ipairs(rows) do
		if #r.nums == 0 and not r.cannot and not r.equipped then
			if r.label and not stat then stat = r.label end
		else
			local t
			if r.cannot then t = "cannot equip"
			elseif r.equipped then t = "already equipped"
			elseif #r.nums >= 2 then
				local d = r.nums[2] - r.nums[1]
				t = (stat and (stat .. " ") or "") .. (d > 0 and ("up " .. d) or d < 0 and ("down " .. -d) or "no change")
					.. ", " .. r.nums[1] .. " to " .. r.nums[2]
			end
			if t then out[#out + 1] = (r.name and (r.name .. ", ") or "") .. t end
		end
	end
	if #out == 0 then return nil end
	return table.concat(out, ". ")
end
-- the comparison on show next to the list the cursor is in
function open_slots(L)
	local m, out = u32(L + 0x30), {}
	if not inram(m, 0xA4 + 16 * 0xE0) then return out end
	for k = 0, 15 do
		local sl = m + 0xA4 + k * 0xE0
		local id = u8(sl + 0x20)
		if id ~= 0xFF and (u8(sl + 0x21) & 0x20) == 0 then
			out[#out + 1] = { id = id, w = u16(sl + 4), h = u16(sl + 6), x = u16(sl + 8), y = u16(sl + 0x0A) }
		end
	end
	return out
end
function shop_compare(L, W, count, selwin)
	local slots = open_slots(L)
	for _, w in ipairs(layout_windows_cached(L)) do
		if w ~= selwin and #w.boxes > 2 then
			local open = false
			for _, sl in ipairs(slots) do
				if sl.id == (w.id & 0xFF) and sl.w == w.w and sl.h == w.h and sl.x == w.x and sl.y == w.y then open = true break end
			end
			if open then
				local t = compare_text(L, W, count, w)
				if t then return t end
			end
		end
	end
	return nil
end

EQUIP_POPUP = { Equip = true, Move = true, Discard = true, Cancel = true }
layout_box_g = function(...) return layout_box(...) end
local function read_layout()
	local p = u32(LAYOUT_PTR)
	if p == 0 or not inram(p, 0x40) then lay_state = nil return end
	-- two layouts can be up at once (a list below, details above): the pointer follows the one
	-- drawn last, which may have no cursor. Then use the last one that had a cursor.
	local fallback_ok, using_fallback = true, false
	if u16(p - 4 + 0x36) == 0xFFFF and not lay_good then lay_good = 0x02389268 end   -- where the list usually is
	if u16(p - 4 + 0x36) == 0xFFFF and fallback_ok and lay_good and lay_good ~= p and inram(lay_good, 0x40) then
		local g = lay_good - 4
		local gs, gn = u16(g + 0x36), u16(g + 8)
		if gs ~= 0xFFFF and gn > 0 and gn < 1000 and inram(u32(g + 4), gn * 0x30) then p, using_fallback = lay_good, true end
	end
	local L = p - 4
	local W, count, sel = u32(L + 4), u16(L + 8), u16(L + 0x36)
	if sel ~= 0xFFFF then lay_good, lay_good_frame = p, frame end
	if count == 0 or count > 1000 or not inram(W, count * 0x30) then return end
	if read_quantity(L, W, count, sel) then return end
	-- the cursor holds a box's id (+4), which is usually, but not always, its place in the array
	if sel >= count or u16(W + 0x30 * sel + 4) ~= sel then
		local found = nil
		for i = 0, count - 1 do if u16(W + 0x30 * i + 4) == sel then found = i break end end
		if not found then return end
		sel = found
	end
	-- a new message (the shopkeeper speaking again) means the same menu is news again
	-- (but not the list you just left, which stays in memory for a moment while the menu comes back)
	if lay_serial ~= dialogue_serial and not using_fallback then lay_serial, lay_skip, lay_state, lay_rearm = dialogue_serial, lay_state, nil, frame end
	local text = layout_box(L, W, sel)
	if not text then return end
	local a = W + 0x30 * sel
	local sx, sy = u16(a + 6), u16(a + 8)
	-- the boxes of one list are chained together: count them for "2 of 6"
	local first, guard = a, 0
	while guard < 60 do
		local pv = u32(first + 0x18)
		if not inram(pv, 0x30) or (pv - W) % 0x30 ~= 0 then break end
		first, guard = pv, guard + 1
	end
	local pos, total, it, last = 0, 0, first, sel
	local popup_like = true
	guard = 0
	while it and guard < 60 do
		local id = (it - W) // 0x30
		if id > last then last = id end
		local bt = layout_box(L, W, id)
		if bt then
			total = total + 1
			if it == a then pos = total end
			if not EQUIP_POPUP[bt] then popup_like = false end
		end
		local nx = u32(it + 0x1C)
		if not inram(nx, 0x30) or (nx - W) % 0x30 ~= 0 then break end
		it, guard = nx, guard + 1
	end
	-- the boxes on this line that belong to it (a price, how many you have): they come right
	-- after the list. Only lists of names have them.
	local extra = {}
	-- (only boxes in the same window: another window can have a line at the same height)
	local selwin = window_of(L, sel)
	local inwin = nil
	if selwin then inwin = {} for _, b in ipairs(selwin.boxes) do inwin[b] = true end end
	if u16(a + 0x12) == 0xFA04 or (u16(a + 0x12) >> 8) == 0xAA then
		for i = last + 1, math.min(count - 1, last + 45) do
			local b = W + 0x30 * i
			local bx, by = u16(b + 6), u16(b + 8)
			if math.abs(by - sy) <= 1 and bx >= sx + 30 and u16(b + 0x0A) > 0 and (not inwin or inwin[i]) then
				local t = layout_box(L, W, i)
				if t then extra[#extra + 1] = { bx, t } end
			end
		end
	end
	local shop = layout_string(L, 5) == "Buy"
	table.sort(extra, function(x, y) return x[1] < y[1] end)
	if text:match("^%?%?%?+$") then text = "not found yet" end      -- a monster or item not seen yet
	local line = text
	for k, e in ipairs(extra) do
		local t = e[2]
		if shop and t:match("^%d+$") then t = t .. (k == 1 and " gold" or " held") end
		line = line .. ", " .. t
	end
	line = line:gsub("Lv%.,%s*(%d+)", "level %1")
	-- the comparison is redrawn a few frames after the cursor moves: until then it still shows
	-- the last item, so wait for it before saying the line
	local compare = nil
	if shop then
		if line ~= lay_base then lay_base, lay_base_since = line, frame end
		if frame - lay_base_since < 10 then return end
		compare = shop_compare(L, W, count, selwin)
	end
	-- the little Equip / Move / Discard / Cancel list on the equipment screen stays in memory
	-- after it closes, and the list of who to equip then moves its old cursor
	if total == 4 and popup_like then
		if not equip_popup_open and frame - (equip_popup_arm or -1000) < 60 then equip_popup_open = true end
		if not equip_popup_open then
			local w = equip_who_items and equip_who_items[pos - 1]
			if not w then return end
			line = w.text
		end
	end
	if total > 1 then line = line .. ", " .. pos .. " of " .. total end
	-- the Defeated Monster List's first choice (View All Monsters / View By Family): say how
	-- complete the list is, once (the numbers are boxes of kind 0xFA03 beside the words)
	if text:match("^View ") and layout_string(L, 2) == "Defeated Monster List Completion:" and MON_HEAD_SAID ~= W then
		MON_HEAD_SAID = W
		local nums = {}
		for i = 0, math.min(count - 1, 12) do
			local b = W + 0x30 * i
			if u16(b + 0x12) == 0xFA03 then nums[#nums + 1] = { y = u16(b + 8), v = u32(b) } end
		end
		table.sort(nums, function(p, q) return p.y < q.y end)
		if nums[1] and nums[2] then
			line = "Defeated Monster List, " .. nums[1].v .. " percent complete, " .. nums[2].v .. " kinds of monster defeated. " .. line
		end
	end
	-- the Defeated Monster List is two columns read across (Slime, Cruelcumber, Teeny sanguini
	-- ...): count along the rows, and say the page (its "1 / 3" at the bottom)
	if layout_string(L, 0x17) == "Defeated Monster List" and u16(a + 0x12) == 0xFA02 then
		local names = {}
		for i = 0, count - 1 do
			local b = W + 0x30 * i
			if u16(b + 0x12) == 0xFA02 and u16(b + 0x0E) == 0 and u16(b + 0x0A) > 0 then names[#names + 1] = { i = i, x = u16(b + 6), y = u16(b + 8) } end
		end
		table.sort(names, function(p, q) if math.abs(p.y - q.y) > 3 then return p.y < q.y end return p.x < q.x end)
		local at = 0
		for k, nb in ipairs(names) do if nb.i == sel then at = k end end
		local pg, pgs = nil, nil
		for i = 0, count - 1 do
			local b = W + 0x30 * i
			if u16(b + 0x12) == 0xF803 and u16(b + 8) > 110 then
				if not pg then pg = u32(b) else pgs = u32(b) end
			end
		end
		if at > 0 then
			line = (text:match("^%?%?%?+$") and "not found yet" or text) .. ", " .. at .. " of " .. #names
			if pg and pgs and pgs > 1 then line = line .. ", page " .. pg .. " of " .. pgs end
		end
	end
	-- its View By Family: three columns of families, read across, with how many of that family
	-- you have defeated (the number beside "... Family Monsters Defeated:")
	if layout_string(L, 0x17) == "Defeated Monster List" and text:match(" Family$") then
		local fams = {}
		for i = 0, count - 1 do
			local b = W + 0x30 * i
			local t = layout_box(L, W, i)
			-- (not the tab over a family's list or "View By Family" at the top: those sit higher)
			if t and t:match(" Family$") and u16(b + 0x12) == u16(a + 0x12) and u16(b + 8) > 5 and t ~= "View By Family" then fams[#fams + 1] = { i = i, x = u16(b + 6), y = u16(b + 8) } end
		end
		table.sort(fams, function(p, q) if math.abs(p.y - q.y) > 3 then return p.y < q.y end return p.x < q.x end)
		local at = 0
		for k, f in ipairs(fams) do if f.i == sel then at = k end end
		local got = nil
		for i = 0, math.min(count - 1, 12) do
			local b = W + 0x30 * i
			if u16(b + 0x12) == 0xFA03 and u16(b + 8) == 13 then got = u32(b) end
		end
		if at > 0 then line = text .. (got and (", " .. got .. " defeated") or "") .. ", " .. at .. " of " .. #fams end
	end
	if compare then line = line .. ". " .. (compare:gsub("^%l", string.upper)) end
	-- (two entries can read the same, "not found yet" in both columns of the monster list: the
	-- box the cursor is on tells them apart)
	local key = line .. "#" .. sel
	if key == lay_state then lay_pending = nil return end
	-- the list fills in over a few frames: wait until it holds still
	if key ~= lay_pending then lay_pending, lay_since = key, frame return end
	if frame - lay_since < 4 then return end
	-- the same line as before the shopkeeper spoke: wait a moment in case it is the old list
	if key == lay_skip and frame - lay_rearm < 90 then return end
	lay_skip = nil
	lay_state, lay_pending = key, nil
	if frame - last_dialogue_frame < 5 then queue(line) else say(line, true) end
	local dsc = item_desc_of(text)
	if dsc then queue(dsc) end
	-- the Defeated Monster List: the monster's page on the other screen comes after its name
	if layout_string(L, 0x17) == "Defeated Monster List" and text ~= "not found yet" then
		MON_DETAIL = { name = text, until_frame = frame + 90 }
	end
end

-- A monster's page in the Defeated Monster List (the other screen) is a run of small boxes of
-- 0x14 bytes: an id (+4), the kind (+6: 0xFA01 words, 0xF802 a number), x, y, and the value or
-- the words (+0x10). 0x15 the name, 0x16 the family, 0x17 experience, 0x18 gold, 0x19 how many
-- defeated, 0x1C how many of the first item dropped, 0x20 and 0x21 where it lives. The names of
-- the items and the description sit in a block that points 0x84 bytes past itself.
mon_page = { boxes = nil }
function mon_page_boxes()
	local function ok(b)
		return inram(b, 0x14 * 20) and u16(b + 4) == 0x15 and u16(b + 6) == 0xFA01 and u16(b + 0x18) == 0x16 and u16(b + 0x2C) == 0x17 and u16(b + 0x2E) == 0xF802
	end
	if mon_page.boxes and ok(mon_page.boxes) then return mon_page.boxes end
	mon_page.boxes = nil
	if not mainmemory.read_string then return nil end
	local from, len = 0x02380000, 0x60000
	local raw = mainmemory.read_string(from - BASE, len)
	local i = 1
	while true do
		local j = raw:find("\x15\x00\x01\xFA", i, true)
		if not j then break end
		local b = from + j - 1 - 4
		if ok(b) then mon_page.boxes = b return b end
		i = j + 1
	end
	return nil
end
function mon_page_box(b, id)
	for k = -2, 22 do
		local a = b + k * 0x14
		if u16(a + 4) == id then return a end
	end
	return nil
end
function mon_page_text()
	local b = mon_page_boxes()
	if not b then return nil end
	local function num(id) local a = mon_page_box(b, id) return a and u32(a + 0x10) or nil end
	local function str(id)
		local a = mon_page_box(b, id)
		local p = a and u32(a + 0x10)
		if p and inram(p, 1) then local t = clean(cstring(p, 60)) return t ~= "" and t or nil end
		return nil
	end
	local name = str(0x15)
	if not name then return nil end
	local parts = {}
	local fam = str(0x16)
	if fam then parts[#parts + 1] = fam end
	local e, g, d = num(0x17), num(0x18), num(0x19)
	if e then parts[#parts + 1] = "experience " .. e end
	if g then parts[#parts + 1] = "gold " .. g end
	if d then parts[#parts + 1] = "defeated " .. d end
	-- the block with the item names and the description
	local item, desc
	if find_selfptr then
		for _, x in ipairs(find_selfptr(0x02380000, 0x40000, 0x84, 64)) do
			local dp = u32(x + 0x0C)
			if inram(dp, 4) then
				local t = clean(cstring(dp, 300))
				if #t > 20 and t:match("%a%a%a") then
					local ip = u32(x + 4)
					if inram(ip, 1) then item = clean(cstring(ip, 40)) end
					desc = t
					break
				end
			end
		end
	end
	if item and item ~= "" then parts[#parts + 1] = "drops " .. item .. " " .. (num(0x1C) or 0) end
	-- where it lives: the names are packed one after another, so a second one that does not
	-- follow straight on from the first is left over from another monster
	local h1a, h2a = mon_page_box(b, 0x20), mon_page_box(b, 0x21)
	local h1 = str(0x20)
	if h1 then
		local haunt = "found in " .. h1
		local p1, p2 = h1a and u32(h1a + 0x10), h2a and u32(h2a + 0x10)
		local h2 = str(0x21)
		if h2 and p1 and p2 == p1 + #cstring(p1, 60) + 1 then haunt = haunt .. " and " .. h2 end
		parts[#parts + 1] = haunt
	end
	local line = table.concat(parts, ", ") .. "."
	if desc then line = line .. " " .. desc end
	return name, line
end
function watch_mon_page()
	if not MON_DETAIL then return end
	if frame > MON_DETAIL.until_frame then MON_DETAIL = nil return end
	if frame % 4 ~= 0 then return end
	local ok, name, line = pcall(mon_page_text)
	if ok and name and name:lower() == MON_DETAIL.name:lower() then
		MON_DETAIL = nil
		queue(line)
	end
end


------------------------------------------------------------------------------ record screens -
-- Battle Records (the item list and the like) are built from small "element" objects chained
-- together in memory: text boxes (function 0x021FE708) and cursor lists (function 0x021FE80C).
-- A list keeps the ids of the text boxes it moves over (+0x20 array, +0x24 count, +0x28 cursor).
-- A text box has its text at +0x20, or the number of a string in the screen's string table at
-- +0x38. The screen's string table is pointed to from 0x02108DC0.
UI_LIST_FN, UI_TEXT_FN, UI_STRINGS = 0x021FE80C, 0x021FE708, 0x02108DC0
UI_NUM_FN = 0x021FF078      -- a number box: its value at +0x2C
ui = { lists = {}, texts = {}, table = nil, focus = nil, said = {}, checked = -1000 }
ui_cache, ui_cache_table = {}, nil
function ui_string(sid)
	local h = u32(UI_STRINGS)
	if h ~= ui_cache_table then ui_cache, ui_cache_table = {}, h end
	-- found strings are kept; a miss is only trusted for a second (the table may still be loading)
	local c = ui_cache[sid]
	if type(c) == "string" then return c end
	if type(c) == "number" and frame - c < 60 then return nil end
	local v = ui_string_raw(sid, h)
	ui_cache[sid] = v or frame
	return v
end
function ui_string_raw(sid, h)
	if not inram(h, 8) then return nil end
	local e, n = u32(h), u16(h + 4)
	if n > 500 or not inram(e, n * 8) then return nil end
	for k = 0, n - 1 do
		if u16(e + k * 8) == sid then
			local s = clean(cstring(u32(e + k * 8 + 4), 100))
			return s ~= "" and s or nil
		end
	end
	return nil
end
function ui_text(e)
	if not e or u32(e) ~= UI_TEXT_FN then return nil end
	local p = u32(e + 0x20)
	if inram(p, 1) then
		local s = clean(cstring(p, 100))
		if s:match("^%?%?%?+$") then return "not found yet" end      -- a monster or item not seen yet
		if s ~= "" then return (s:gsub("^%l", string.upper)) end
		return nil
	end
	local s = ui_string(u16(e + 0x38))
	if s and s:match("^%?%?%?+$") then return "not found yet" end
	return s
end
function ui_scan()
	ui.lists, ui.texts, ui.focus = {}, {}, nil
	local from, len = 0x02380000, 0x40000
	-- (the title screen keeps its lists lower down, such as "Load quick save data. / Cancel":
	-- with the PC version's quick search, look there too)
	if FAST_MEM and cstring(MAPCODE, 12) == "" and u32(PLAYER_PTR) == 0 then from, len = 0x02300000, 0x100000 end
	local head = nil
	if FAST_MEM then
		ui.lists = find_words(from, len, UI_LIST_FN)
	else
	for off = 0, len - 4096, 4096 do
		-- a little at a time: this runs over several frames so the game does not stutter
		if off > 0 and coroutine.isyieldable() then coroutine.yield() end
		local t = read_bytes(from + off, 4096)
		for i = 1, #t - 3, 4 do
			if t[i + 3] == 0x02 and t[i + 2] == 0x1F and t[i + 1] == 0xE8 and t[i] == 0x0C then
				ui.lists[#ui.lists + 1] = from + off + i - 1
			end
		end
	end
	end
	-- (a list left over from the last screen has had its links and count cleared)
	local live = {}
	for _, o in ipairs(ui.lists) do
		if u16(o + 0x24) > 0 and (u32(o + 0x14) ~= 0 or u32(o + 0x18) ~= 0) then live[#live + 1] = o end
	end
	ui.lists = live
	if #ui.lists == 0 then return end
	-- walk back along the chain from the first list to its first box
	local e, guard = ui.lists[1], 0
	while inram(e, 0x40) and guard < 400 do
		head = e
		local pv = u32(e + 0x14)
		if not inram(pv, 0x40) then break end
		e, guard = pv, guard + 1
	end
	ui.head = head
	-- the screen keeps a pointer to the chain's first box; 0x98 bytes further on is the id of
	-- the list that has the cursor
	if FAST_MEM then
		for _, a in ipairs(find_words(from, len, head)) do
			local f = u32(a - 0x14)          -- a box's own back link is not it
			if not (f >= 0x02000000 and f < 0x02400000 and f & 0xFFF00000 == 0x02100000) then ui.focus = a + 0x98 end
		end
		return
	end
	for off = 0, len - 4096, 4096 do
		-- a little at a time: this runs over several frames so the game does not stutter
		if off > 0 and coroutine.isyieldable() then coroutine.yield() end
		local t = read_bytes(from + off, 4096)
		local b0, b1, b2, b3 = head & 0xFF, (head >> 8) & 0xFF, (head >> 16) & 0xFF, (head >> 24) & 0xFF
		for i = 1, #t - 3, 4 do
			if t[i] == b0 and t[i + 1] == b1 and t[i + 2] == b2 and t[i + 3] == b3 then
				local a = from + off + i - 1
				local f = u32(a - 0x14)          -- a box's own back link is not it
				if not (f >= 0x02000000 and f < 0x02400000 and f & 0xFFF00000 == 0x02100000) then ui.focus = a + 0x98 end
			end
		end
	end
end
function ui_describe(o)
	local n, cur, arr = u16(o + 0x24), u16(o + 0x28), u32(o + 0x20)
	-- a list in columns (the wardrobe's Swords / Spears, Knives / Wands ...): +0x24 is the
	-- number of rows and +0x26 of columns; the names go along each row; the cursor's row is at
	-- +0x28 and its column at +0x2A
	local cols = u16(o + 0x26)
	if cols >= 2 and cols <= 6 and n > 0 and n <= 32 and cur < n and u16(o + 0x2A) < cols and inram(arr, n * cols * 2) then
		local row, col = cur, u16(o + 0x2A)
		local text = ui_text(ui.texts[u16(arr + (row * cols + col) * 2)])
		if not text then return nil end
		return text .. ", row " .. (row + 1) .. ", column " .. (col + 1)
	end
	if n == 0 or n > 64 or cur >= n or not inram(arr, n * 2) then return nil end
	local text = ui_text(ui.texts[u16(arr + cur * 2)])
	if not text then return nil end
	local pos, total = 0, 0
	for k = 0, n - 1 do
		if ui_text(ui.texts[u16(arr + k * 2)]) then
			total = total + 1
			if k == cur then pos = total end
		end
	end
	return total > 1 and (text .. ", " .. pos .. " of " .. total) or text
end
function read_ui_screen()
	-- a search for the screen's boxes that is still going on
	if ui.co then
		local ok = coroutine.resume(ui.co)
		if not ok or coroutine.status(ui.co) == "dead" then ui.co = nil end
		if ui.co then return end
	end
	if frame - ui.checked < 4 then return end
	ui.checked = frame
	if UI_SAID_RESET and UI_SAID_RESET ~= ui.reset_seen then ui.reset_seen, ui.said = UI_SAID_RESET, {} end
	local tbl = u32(UI_STRINGS)
	local hf = ui.head and u32(ui.head) or 0
	local valid = hf >= 0x021F0000 and hf < 0x02200000
	if tbl ~= ui.table or (ui.head and not valid) then
		if tbl ~= ui.table then ui.table_frame = frame end
		ui.table = tbl
		ui.said, ui.head = {}, nil
		ui.co = coroutine.create(ui_scan)
		return
	end
	if not ui.head then
		-- nothing found the last time it looked (the screen was not built yet): a message that
		-- ends in a list of choices is a reason to look again, and so is a new screen's strings
		-- having just come in (Battle Records' Wardrobe builds its list a moment after)
		if ((UI_SAID_RESET and frame - UI_SAID_RESET < 300) or frame - (ui.table_frame or -1000) < 600)
			and frame - (ui.scan_frame or -1000) > 45 then
			ui.scan_frame = frame
			ui.co = coroutine.create(ui_scan)
		end
		return
	end
	-- boxes and lists come and go as the screen changes: walk the chain every time
	ui.lists, ui.texts = {}, {}
	local order, nums = {}, {}
	local e, guard = ui.head, 0
	while inram(e, 0x40) and guard < 400 do
		local f = u32(e)
		if f == UI_TEXT_FN then ui.texts[u16(e + 6)] = e order[#order + 1] = e
		elseif f == UI_LIST_FN then ui.lists[#ui.lists + 1] = e
		elseif f == UI_NUM_FN then nums[#nums + 1] = u32(e + 0x2C) end
		e, guard = u32(e + 0x18), guard + 1
	end
	-- nothing to read in it any more (the screen was closed and its boxes cleared): look again
	local usable = false
	for _, o in ipairs(ui.lists) do if u16(o + 0x24) > 0 then usable = true break end end
	if not usable then ui.lists = {} end
	if #ui.lists == 0 then ui.head = nil return end
	-- the words at the top of a new screen ("Wardrobe Completion:" 2 %, "Number Collected:"
	-- 19): the boxes no list moves over, each "...:" taking the next number box's value
	if ui.header_for ~= ui.head then
		ui.header_for = ui.head
		local inlist = {}
		for _, o in ipairs(ui.lists) do
			local n, arr = u16(o + 0x24) * math.max(1, u16(o + 0x26)), u32(o + 0x20)
			if n > 0 and n <= 200 and inram(arr, n * 2) then for k = 0, n - 1 do inlist[u16(arr + k * 2)] = true end end
		end
		local parts, ni = {}, 1
		for _, t in ipairs(order) do
			local w = not inlist[u16(t + 6)] and ui_text(t)
			if w and w:match(":$") and nums[ni] and #parts < 2 then
				parts[#parts + 1] = w .. " " .. nums[ni] .. (w:find("Completion", 1, true) and " percent" or "")
				ni = ni + 1
			end
		end
		ui.header = #parts > 0 and table.concat(parts, ". ") or nil
	end
	-- a list that has just come back (the other page of the monster list) is news again
	local now_in = {}
	for _, o in ipairs(ui.lists) do
		now_in[o] = true
		if ui.prev_in and not ui.prev_in[o] then ui.said[o] = nil end
	end
	ui.prev_in = now_in
	local focus = ui.focus and u16(ui.focus) or nil
	local pick, changed = nil, {}
	for _, o in ipairs(ui.lists) do
		-- (the title screen's own two menus have their own reader)
		if u32(o) == UI_LIST_FN and u16(o + 6) ~= 0x12D and u16(o + 6) ~= 0x12E then
			local line = ui_describe(o)
			local id = u16(o + 6)
			if line and line ~= ui.said[o] then
				changed[#changed + 1] = o
				if id == focus then pick = o end
			end
			ui.said[o] = line
		end
	end
	if not pick and #changed == 1 then pick = changed[1] end
	if not pick and #changed > 1 then
		-- no way to tell which one has the cursor: the one that moved, else the longest list
		local best = 0
		for _, o in ipairs(changed) do if u16(o + 0x24) > best then best, pick = u16(o + 0x24), o end end
	end
	if pick and (not focus or u16(pick + 6) == focus) then
		ui.spoke_frame = frame
		local line = ui.said[pick]
		if ui.header then line = ui.header .. ". " .. line ui.header = nil end
		-- an item in the Wardrobe or the Item List: its description after it
		local nm = line:match("([^%.,]+), row %d+") or line:match("([^%.,]+), %d+ of %d+$")
		local dsc = nm and item_desc_of((nm:gsub("^%s+", "")))
		if dsc then UI_DESC = dsc end
		if frame - last_dialogue_frame < 5 then queue(line) else say(line, true) end
		if UI_DESC then queue(UI_DESC) UI_DESC = nil end
	end
end


-- Battle Records (Stella's book): big picture buttons with no text in memory. The menu keeps a
-- small block: the ids of the buttons on show (+0, one byte each), how many (+8) and the cursor
-- (+0x28), followed by pointers back into itself (+0x2C = +0x14, +0x34 = +0x24, +0x38 = +0x28).
REC_LABELS = { [0] = "Defeated Monster List", "Wardrobe", "Item List", "Alchenomicon", "Accolades Earnt", "Guest List" }
rec = { addr = nil, until_frame = -1, last = nil, next_scan = 0 }
function rec_valid(m)
	return inram(m, 0x40) and u32(m + 0x38) == m + 0x28 and u32(m + 0x2C) == m + 0x14 and u32(m + 0x34) == m + 0x24
end
function read_records_menu(pad)
	if pad.a and not rec.pad_a and last_menu_item == "Battle Records" and frame - last_menu_spoken < 1200 then
		rec.until_frame, rec.addr, rec.last, rec.active = frame + 400, nil, nil, true
	end
	rec.pad_a = pad.a
	-- the play time on show (only on this screen) also says you are in it (the mod may have been
	-- restarted inside, missing the A press)
	local clock = menu_raw_seen:match("^<PLTT=%d+><Y=%d+><XR=%d+>%d+</XR><X=%d+>:<XR=%d+>%d+</XR>$")
	if clock then rec.active, rec.until_frame = true, math.max(rec.until_frame, frame + 60) end
	-- still inside Battle Records (its lists) until the menu closes or the main menu is back
	if rec.active and not clock and (u8(0x02109DA4) == 1 or (last_menu_item ~= "Battle Records" and menu_raw_seen:find("<N=4>Battle Records</N>", 1, true))) then rec.active = false end
	if rec.active and frame > rec.until_frame then rec.until_frame = frame + 60 end
	if rec.addr and not rec_valid(rec.addr) then rec.addr, rec.last = nil, nil end
	if not rec.addr then
		if frame > rec.until_frame or frame < rec.next_scan then return end
		rec.next_scan = frame + 20
		for _, x in ipairs(find_selfptr(0x02380000, 0x40000, -0x10)) do
			local m = x - 0x38
			if rec_valid(m) then rec.addr = m break end
		end
		if not rec.addr then return end
	end
	local m = rec.addr
	-- one of the lists inside (the item list ...) is open: say the button again when you come back
	if ui.head and frame - (ui.spoke_frame or -1000) < 120 then rec.last = nil return end
	-- (how many: +8 in some builds of the block, +0x0C in others, where +8 is a pointer)
	local n, cur = u32(m + 8), u32(m + 0x28)
	if n == 0 or n > 8 then n = u32(m + 0x0C) end
	if n == 0 or n > 8 or cur >= n then return end
	local label = REC_LABELS[u8(m + cur)] or ("option " .. (cur + 1))
	local line = label .. ", " .. (cur + 1) .. " of " .. n
	if line ~= rec.last then
		-- coming in: the time played (the clock on show) and how complete the lists are (the
		-- page's <val_1>% <val_2>% <val_3>% numbers)
		if rec.summary_for ~= m then
			rec.summary_for = m
			local parts = {}
			local h, mi = menu_raw_seen:match("^<PLTT=%d+><Y=%d+><XR=%d+>(%d+)</XR><X=%d+>:<XR=%d+>(%d+)</XR>$")
			if h then parts[#parts + 1] = "Time played " .. tonumber(h) .. " hours " .. tonumber(mi) .. " minutes" end
			local v1, v2, v3 = u32(MSG_VALS + 4), u32(MSG_VALS + 8), u32(MSG_VALS + 12)
			if v1 <= 100 and v2 <= 100 and v3 <= 100 then
				parts[#parts + 1] = "Defeated Monster List " .. v1 .. " percent, Wardrobe " .. v2 .. " percent, Item List " .. v3 .. " percent complete"
			end
			if #parts > 0 then line = "Battle Records. " .. table.concat(parts, ". ") .. ". " .. line end
		end
		rec.last = label .. ", " .. (cur + 1) .. " of " .. n
		rec.spoke_frame = frame
		if frame - last_dialogue_frame < 5 then queue(line) else say(line, true) end
	end
end


-- Yes or no boxes that are neither the field's yes / no box nor a menu (Allocate Skill Points:
-- "End skill point allocation?"): a small two-choice control (the kind read_choice uses) that
-- comes up with the question. Those that were there before the question are not it.
gq = { ctl = nil, q = nil, before = nil, last = nil }
function two_choice_controls()
	local out = {}
	for _, x in ipairs(find_selfptr(0x02380000, 0x40000, -0x10)) do
		local c = x - 0x30
		if u32(c + 0x24) == c + 0x0C and u32(c + 0x2C) == c + 0x1C and u32(c + 4) == 2 and u32(c + 0x30) == c + 0x20 then out[#out + 1] = c end
	end
	return out
end
function watch_two_choice()
	if not FAST_MEM then return end
	if not QUESTION_FRAME or frame - QUESTION_FRAME > 900 then
		gq.cands, gq.q = nil, nil
		-- the boxes that are already there (left over from earlier): a question's box is a new one
		if frame % 30 == 0 then
			gq.known = {}
			for _, c in ipairs(two_choice_controls()) do gq.known[c] = true end
		end
		return
	end
	-- only a question that ends its message (the field's own yes / no has its own code)
	if gq.q ~= QUESTION_FRAME then
		gq.q, gq.cands, gq.ctl, gq.last, gq.seen = QUESTION_FRAME, nil, nil, nil, {}
		local raw = dlg_last_raw or ""
		gq.ok = not raw:find("\4\255", 1, true) and not raw:find("\10\255", 1, true)
		return
	end
	if not gq.ok then return end
	-- the other readers have it (the field's yes / no, a menu's Yes / No, a conversation's list)
	if yesno_visible or choice.items or menu_raw_seen:find("<N=0>Yes</N>", 1, true) then return end
	if not gq.cands then
		if frame - QUESTION_FRAME < 20 then return end
		-- (something else was said after the question: it was not waiting for an answer)
		if last_said ~= QUESTION_TEXT then gq.ok = false return end
		local all, fresh = two_choice_controls(), {}
		for _, c in ipairs(all) do if not (gq.known and gq.known[c]) then fresh[#fresh + 1] = c end end
		-- no new box: only a short message on its own (a screen's own question, whose box can be
		-- left from the last time) may be using one that was there; a conversation is not
		-- ("... like a headless chicken, okay?" is not asking)
		if #fresh == 0 and not (dlg_last_raw or ""):find("\13\255", 1, true) and not (dlg_last_raw or ""):find("//", 1, true) and not (dlg_last_raw or ""):find("*:", 1, true) then fresh = all end
		gq.cands = fresh
		if #gq.cands == 0 then gq.ok = false return end
		for _, c in ipairs(gq.cands) do gq.seen[c] = u32(c + 0x20) end
		gq.cur_box, gq.moved_at = gq.cands[#gq.cands], frame
		return
	end
	-- whichever box's cursor moves is the one on screen
	for _, c in ipairs(gq.cands) do
		if u32(c + 0x30) == c + 0x20 and u32(c + 4) == 2 then
			local cur = u32(c + 0x20)
			if cur <= 1 and cur ~= gq.seen[c] then gq.seen[c], gq.cur_box, gq.moved_at = cur, c, frame end
		end
	end
	local c = gq.cur_box
	if not c then return end
	local cur = u32(c + 0x20)
	if cur > 1 then return end
	local word = cur == 0 and "Yes" or "No"
	if gq.last == nil then
		-- the box sets itself up over a few frames: say it once it holds still
		if frame - gq.moved_at < 15 then return end
		gq.last = word
		queue("Yes or no? " .. word)
	elseif word ~= gq.last and frame - last_button_frame < 30 then
		-- (only when you moved it: the boxes shuffle their cursors as they are set up)
		gq.last = word
		say(word, true)
	end
end

-- Choices inside a conversation (Erinn's "Stay at the inn / Canvass for guests ..."): the message
-- that asks ends with <ADD> in the menu buffer, the choices are a "<N=0>...</N>" line among the
-- messages the game has loaded, and the cursor is copied to the player's record (+0x250), like
-- the yes or no answer.
choice = { sig = nil, items = nil, last = nil }
function find_choice_lists()
	local lists = {}
	local from, len = 0x0211C000, 0x24000
	local blob = mem_str(from, len)
	local at = 1
	while true do
		local i = blob:find("<N=0>", at, true)
		if not i then break end
		at = i + 5
		do
			do
				local a = from + i - 1
				local sraw = cstring(a, 400)
				if not sraw:find("%s", 1, true) then
					local items = {}
					for txt in sraw:gmatch("<N=%d+>(.-)</N>") do items[#items + 1] = clean(txt) end
					if #items >= 2 then lists[#lists + 1] = items end
				end
			end
		end
	end
	return lists
end
function read_choice()
	local m = menu_raw_seen
	local asking = m:sub(-5) == "<ADD>" and (m:find("<PAGE>", 1, true) or m:find("//", 1, true) or m:find("<N_TURN>", 1, true))
	if not asking then choice.sig, choice.items, choice.last = nil, nil, nil return end
	-- the same question asked again (talking to Erinn twice) is a new question
	local sig = m .. "#" .. tostring(msg_serial)
	if sig ~= choice.sig then
		choice.sig, choice.last = sig, nil
		choice.items, choice.cands, choice.retry = nil, nil, frame
		choice.since, choice.ctl = frame, nil
	end
	-- the list of choices among the messages the game has loaded: look again for a while if it
	-- is not there yet, or if there are several to choose from (the window's count decides)
	if not choice.items and frame >= (choice.retry or 0) and frame - choice.since < 300 then
		choice.retry = frame + 15
		local lists = find_choice_lists()
		if MENU_DEBUG then log_line("choice lists " .. #lists) end
		if #lists == 1 then choice.items, choice.cands = lists[1], nil
		elseif #lists > 1 then choice.cands = lists end
	end
	if not choice.items and choice.cands and not choice.ctl and frame >= (choice.next_scan or 0) and frame - choice.since < 300 then
		choice.next_scan = frame + 15
		for _, x in ipairs(find_selfptr(0x02380000, 0x40000, -0x10)) do
			local c = x - 0x30
			if u32(c + 0x24) == c + 0x0C and u32(c + 0x2C) == c + 0x1C then
				local n, match = u32(c + 4), nil
				for _, l in ipairs(choice.cands) do
					if #l == n then if match then match = false break else match = l end end
				end
				if match then choice.items, choice.ctl = match, c break end
			end
		end
	end
	if not choice.items then return end
	-- only while the question itself is on screen (not the pages before it, not the reply after)
	local q = m:gsub("<ADD>$", ""):match(".*<PAGE>(.*)$") or m:gsub("<ADD>$", "")
	local nq = clean(q):gsub("[^%a]", ""):sub(-15)
	local pg = cstring(u32(PAGE_START), 400)
	local cut = pg:find("\13\255", 1, true)
	if cut then pg = pg:sub(1, cut - 1) end
	local nd = clean(pg):gsub("[^%a]", "")
	if nq == "" or nd:sub(-#nq) ~= nq then return end
	-- wait until the question has been written out
	if frame - choice.since < 20 then return end
	-- the window's own cursor: a small block that points back into itself (+0x24 = +0x0C,
	-- +0x2C = +0x1C, +0x30 = +0x20), with the count at +4 and the cursor at +0x20
	if choice.items and not choice.ctl and frame >= (choice.next_scan or 0) and frame - choice.since < 300 then
		choice.next_scan = frame + 15
		for _, x in ipairs(find_selfptr(0x02380000, 0x40000, -0x10)) do
			local c = x - 0x30
			if u32(c + 0x24) == c + 0x0C and u32(c + 0x2C) == c + 0x1C and u32(c + 4) == #choice.items then
				choice.ctl = c break
			end
		end
	end
	if not choice.ctl and frame - choice.since < 140 then return end
	local cur
	if choice.ctl and u32(choice.ctl + 0x30) == choice.ctl + 0x20 then
		cur = u32(choice.ctl + 0x20)
	else
		local player = u32(PLAYER_PTR)
		cur = inram(player, 0x260) and u8(player + 0x250) or 0
	end
	local n = #choice.items
	if cur >= n then return end
	local line = choice.items[cur + 1] .. ", " .. (cur + 1) .. " of " .. n
	if line ~= choice.last then
		local first = choice.last == nil
		-- the window can still hold the last cursor for a moment when it opens: the first
		-- reading must hold still for a quarter of a second
		if first then
			if line ~= choice.pending then choice.pending, choice.pending_at = line, frame return end
			if frame - choice.pending_at < 15 then return end
		end
		choice.last, choice.pending = line, nil
		if first then queue(line) else say(line, true) end
	end
end


-- Create a companion (Patty's): eight steps across the top (a row of tabs) and big buttons
-- below. Both are one grid control that changes shape: columns +8, rows +0xC, cursor column
-- +0x18 and row +0x1C, with pointers back to its own rows and columns at +0x20 and +0x24.
-- Only the gender buttons have words; the others are pictures, so they are read as numbers.
CREATE_STEPS = { "Gender", "Body type", "Hairstyle", "Hair colour", "Face", "Skin colour", "Eye colour", "Name" }
create = { grid = nil, next_scan = 0, last = nil, step = 1, said_title = false }
HERO_CREATE_GRID = 0x022A517C
-- Making a companion at Patty's: her string table is not always the one loaded (it can be the
-- vocations' and attributes'), so also go by the list of steps in the menu buffer (eight lines,
-- the one being changed highlighted) and, while the name is typed, by the name being written there.
function patty_creating()
	if ui_string(5) == "Recruit a Friend" then return true end
	if cstring(MAPCODE, 12) == "" then return false end
	local m = menu_raw_seen or ""
	local n = 0
	for _ in m:gmatch("<PLTT=1[45]>") do n = n + 1 end
	if n == 8 then create.patty_seen = frame return true end
	-- (in a town the only name keyboard is hers: the hero is named before the game starts)
	if m:match("^<X=%d+>[^<]*%**$") and (frame - (create.patty_seen or -1e9) < 54000 or kb_ok(0x023107A8)) then return true end
	return false
end
function create_grid_ok(g)
	return inram(g, 0x28) and u32(g + 0x20) == g + 0x0C and u32(g + 0x24) == g + 0x08
end
function read_create()
	-- Patty's screens load her own string table ("Recruit a Friend" is string 5)
	if not patty_creating() then
		-- making your own hero after "Create a new adventure log": its picture list lives here
		if cstring(MAPCODE, 12) == "" and u32(PLAYER_PTR) == 0 and create_grid_ok(HERO_CREATE_GRID) then
			create.grid = HERO_CREATE_GRID
			-- after the name: "Begin your adventure with this character?", drawn from text the
			-- game does not keep, so say it here along with the answer the cursor is on
			local yn = menu_raw_seen:find("<N=0>Yes</N>", 1, true) ~= nil
			if yn and create.step == 8 and not create.asked then
				create.asked = true
				local c = tonumber(menu_raw_seen:match("<CURSOR=(%d+)>") or "0") or 0
				say("Begin your adventure with this character? " .. (c == 0 and "Yes, 1 of 2" or "No, 2 of 2"), true)
				-- the menu reader need not say the answer again
				menu_raw_done, menu_sig, menu_cursor = menu_raw_seen, (menu_raw_seen:gsub("<CURSOR=%d+>", "")), c
				return
			elseif not yn and menu_raw_seen:match("^<X=%d+>[^<]*%*") then create.asked = false end   -- back at the keyboard
			local g = create.grid
			local cols, rows, cx, cy = u32(g + 8), u32(g + 0xC), u32(g + 0x18), u32(g + 0x1C)
			if cols == 0 or rows == 0 or cols > 12 or rows > 12 or cx >= cols or cy >= rows then return end
			-- Male or Female: the list at the top only shows the choice for a moment, so say it here
			if not (cols == 1 and rows == 2) then create.last = nil return end
			local line = "Gender: " .. (cy == 0 and "Male" or "Female") .. ", " .. (cy + 1) .. " of 2"
			if line ~= create.last then
				create.last = line
				creation_last = "Gender: " .. (cy == 0 and "Male" or "Female")
				say(line, true)
			end
			return
		end
		create.grid, create.last, create.said_title = nil, nil, false
		return
	end
	if create.grid and not create_grid_ok(create.grid) then create.grid = nil end
	if not create.grid and create_grid_ok(0x023107A8) then create.grid = 0x023107A8 end   -- where it usually is
	if not create.grid then
		if frame < create.next_scan then return end
		create.next_scan = frame + 150
		for _, x in ipairs(find_selfptr(0x02300000, 0x40000, -0x14)) do
			if u32(x + 4) == x - 0x18 then create.grid = x - 0x20 break end
		end
		if not create.grid then return end
	end
	local g = create.grid
	-- the last question ("Add this character to your character list?") is drawn from text the
	-- game does not keep, so say it here when the yes or no box comes up after the name
	local yn = menu_raw_seen:find("<N=0>Yes</N>", 1, true) ~= nil
	if yn and create.step == 8 and not create.asked then
		create.asked = true
		queue("Add this character to your character list?")
	elseif not yn then create.asked = false end
	-- which step: the highlighted line of the list at the top (palette 14)
	if menu_raw_seen:match("^<X=%d+>[^<]*%*+$") then create.step = 8 end   -- the name being typed
	if menu_raw_seen:match("^<PLTT=1[45]>") then
		local i = 0
		for pltt in menu_raw_seen:gmatch("<PLTT=(%d+)>") do
			i = i + 1
			if pltt == "14" then create.step = i end
		end
	end
	local cols, rows, cx, cy = u32(g + 8), u32(g + 0xC), u32(g + 0x18), u32(g + 0x1C)
	if cols == 0 or rows == 0 or cols > 12 or rows > 12 or cx >= cols or cy >= rows then return end
	local line
	if cols == 8 and rows == 1 then
		create.step = cx + 1
		line = CREATE_STEPS[cx + 1] .. ", step " .. (cx + 1) .. " of 8"
		if not create.said_title then line = "Create a companion. " .. line create.said_title = true end
	else
		local idx, n = cy * cols + cx, cols * rows
		-- the other steps are said by the list at the top, which shows each picture's name
		if not (create.step == 1 and n == 2) then create.last = nil return end
		line = (idx == 0 and "Male" or "Female") .. ", " .. (idx + 1) .. " of " .. n
	end
	if line ~= create.last then
		create.last = line
		say(line, true)
	end
end

function equip_shaped(b)
	local p1, p2 = u32(b + 0x20), u32(b + 0x24)
	return p1 ~= p2 and (p1 == b + 8 or p1 == b + 0xC) and (p2 == b + 8 or p2 == b + 0xC)
end
equip_grid, equip_next_scan = nil, 0

-- The top screen's box of numbers ("Attack 25 -> 34"). It is a small tree of parts:
-- a table of nodes (0x18 bytes: key, parent, first child, previous, next, shown flag)
-- followed by a list of part ids and then the parts (0x14 bytes: id, type, x, y, value).
-- Parts: 8-11 names of the numbers; 12,14,15,16 the number now (for what is worn);
-- 38-41 the number now, 42-45 the number with the highlighted thing; 35 "Cannot Equip".
function stat_panel_ok(s)
	local nodes, parts, n = u32(s), u32(s + 4), u16(s + 0xC)
	if n ~= 57 or u16(s + 0xE) ~= 42 then return false end
	if parts ~= nodes + n * 0x1C or not inram(parts, 42 * 0x14) then return false end
	return u16(parts + 0x14 * 27) == 38 and u16(parts + 0x14 * 27 + 4) == 122
end
stat_panel, stat_panel_pos = nil, 0
-- looked for a little at a time (64 KB a frame) so the game does not stutter
function find_stat_panel()
	if stat_panel and stat_panel_ok(stat_panel) then return stat_panel end
	stat_panel = nil
	local from, len = 0x02300000, 0x100000
	local base = from + stat_panel_pos
	stat_panel_pos = (stat_panel_pos + 0x10000) % len
	-- 57 nodes, 42 parts
	for _, a in ipairs(find_words(base, 0x10000, 57 | (42 << 16))) do
		local s = a - 0xC
		if stat_panel_ok(s) then stat_panel = s return s end
	end
	return nil
end
function stat_panel_read()
	local s = find_stat_panel()
	if not s then return nil end
	local nodes, n = u32(s), 57
	local ids = nodes + n * 0x18
	local parts = ids + n * 4
	local node_of, by_key, part_of = {}, {}, {}
	for k = 0, n - 1 do
		local nd = nodes + k * 0x18
		by_key[u16(nd)] = nd
		local p = u32(nd + 4)
		if inram(p, 2) and u16(nd + 2) == 1 then node_of[u16(p)] = nd end
	end
	for k = 0, 41 do local a = parts + k * 0x14 part_of[u16(a)] = a end
	local function shown(id)
		local nd, guard = node_of[id], 0
		if not nd then return false end
		while nd and guard < 20 do
			-- the box itself (key 0x0B) is shown whatever its flag says
			if u16(nd) == 0x0B then return true end
			if (u8(nd + 0x16) & 1) == 0 then return false end
			-- the parent is kept on the first child only
			local g2 = 0
			while u16(nd + 0x10) ~= 0 and g2 < 20 do nd, g2 = by_key[u16(nd + 0x10)], g2 + 1 if not nd then return true end end
			local up = u16(nd + 0xC)
			if up == 0 then return true end
			nd, guard = by_key[up], guard + 1
		end
		return true
	end
	local function value(id)
		local a = part_of[id]
		if not a then return nil end
		local kind, v = u8(a + 3), u32(a + 0xC)
		if (kind & 0xF) == 8 and u8(a + 2) == 2 then return tostring(v), kind >> 4 end
		if inram(v, 1) then
			local t = clean(cstring(v, 40))
			if t ~= "" and not t:match("^<") then return t, kind >> 4 end
		end
		return nil
	end
	if shown(35) then return "cannot equip" end
	local out = {}
	local worn = false
	for r = 0, 3 do
		local name = shown(8 + r) and value(8 + r)
		if name then
			local now_id = ({ 12, 14, 15, 16 })[r + 1]
			if shown(38 + r) and shown(42 + r) then
				local a, b = value(38 + r), value(42 + r)
				local na, nb = tonumber(a), tonumber(b)
				if na and nb then
					local d = nb - na
					local how = d > 0 and ("up " .. d) or d < 0 and ("down " .. -d) or "no change"
					out[#out + 1] = name .. " " .. how .. ", " .. a .. " to " .. b
				elseif a and b then
					out[#out + 1] = name .. " " .. a .. " to " .. b
				end
			elseif shown(now_id) then
				local a = value(now_id)
				if a then out[#out + 1] = name .. " " .. a worn = true end
			end
		end
	end
	if #out == 0 then return nil end
	return (worn and "equipped, " or "") .. table.concat(out, ", ")
end

local function read_equip_screen()
	-- straight from "Equip" in the menu, or from the list of who to equip (a party of more than one)
	local it = menu_items[menu_cursor]
	local popup_left = menu_items[0] and menu_items[0].text == "Equip" and menu_items[2] and menu_items[2].text == "Discard"
	local came_from_menu = equip_popup_open or popup_left or (it and (it.text == "Equip" or menu_title == "Equip"))
	if menu_title == "Equip" and it and not equip_popup_open then equip_who_name = it.text end
	if it and it.text == "Equip" and menu_title ~= "Equip" and not popup_left then equip_who_name = nil end
	if not came_from_menu then equip_cursor, equip_state, equip_due = nil, nil, nil return end
	-- the control is not always at the same place (it moves with the size of the party)
	local b = equip_grid
	if not (b and equip_shaped(b)) then
		b = nil
		if equip_shaped(EQUIP_LIST) then b = EQUIP_LIST
		elseif frame >= equip_next_scan then
			equip_next_scan = frame + 60
			local cands = find_selfptr(0x02300000, 0x80000, -0x18)
			for _, x in ipairs(find_selfptr(0x02300000, 0x80000, -0x14)) do cands[#cands + 1] = x end
			table.sort(cands)
			for _, x in ipairs(cands) do
				local c = x - 0x20
				if equip_shaped(c) then
					local cols, rows = u32(c + 8), u32(c + 12)
					if (cols == 1 and rows == 8) or (cols == 8 and rows == 1) or (cols >= 1 and cols <= 8 and rows >= 1 and rows <= 8) then b = c break end
				end
			end
		end
		equip_grid = b
	end
	if not b then equip_cursor, equip_state, equip_due = nil, nil, nil return end
	local shown = b - 0x40                 -- number of the item the top screen is showing
	-- the control is a grid: columns, rows, then the cursor's column and row
	local cols, rows, cx, cy = u32(b + 8), u32(b + 12), u32(b + 0x18), u32(b + 0x1C)
	local mode = (cols == 1 and rows == 8) and "slots" or (cols == 8 and rows == 1) and "tabs" or "grid"
	local state = mode .. cx .. "," .. cy
	-- what the highlighted thing does to the numbers, said once the top screen has caught up
	-- (the box empties a few frames after the cursor moves and is filled again after about ten)
	if equip_stats_due then
		if state ~= equip_stats_state or frame > equip_stats_due + 60 then
			equip_stats_due = nil
		elseif frame >= equip_stats_due then
			local st = stat_panel_read()
			if not st then equip_stats_blank = true
			elseif equip_stats_blank or frame >= equip_stats_due + 12 then
				say(st, false)
				equip_stats_due = nil
			end
		end
	end
	if state ~= equip_state then
		-- back out of the list of things to put on: the top screen takes a moment to show the slot again
		local wait = (equip_state and equip_state:sub(1, 4) == "grid" and mode ~= "grid") and 14 or 3
		equip_state, equip_due = state, frame + wait
		return
	end
	if not equip_due or frame < equip_due then return end
	equip_due = nil
	local who = party_records()[1]
	if equip_who_name then
		for _, r in ipairs(party_records()) do if r.name == equip_who_name then who = r end end
	end
	if mode == "grid" then
		local nm = item_name(u16(shown))
		say((nm or "empty space") .. ", row " .. (cy + 1) .. ", column " .. (cx + 1), true)
		local dsc = nm and item_desc_of(nm)
		if dsc then queue(dsc) end
		if nm then equip_stats_due, equip_stats_state, equip_stats_blank = frame, state, false else equip_stats_due = nil end
		return
	end
	local c = (mode == "slots") and cy or cx
	if c > 7 then return end
	local first = equip_cursor == nil
	equip_cursor = c
	local slot = EQUIP_SCREEN_SLOTS[c + 1]
	local item = item_name(u16(shown))
	if not item and who and slot[1] then
		local n = clean(cstring(who.addr + 0x534 + slot[1] * 0x30, 0x30))
		if n ~= "" and printable(n) then item = n end
	end
	item = item or "nothing equipped"
	local text = slot[2] .. ": " .. item .. ", " .. (c + 1) .. " of 8"
	if mode == "tabs" then text = text .. ". Down for things you can put on" end
	if first then say("Equipment" .. (who and (" for " .. who.name) or "") .. ". " .. text, true) else say(text, true) end
	local dsc = item_desc_of(item)
	if dsc then queue(dsc) end
end

-- The attributes: kept in the character's record as three words of three 10-bit numbers each.
local function attributes_of(r)
	local n = r.addr
	local w1, w2, w3 = u32(n + 0x8E0), u32(n + 0x8E4), u32(n + 0x8E8)
	local f = function(w, k) return (w >> (10 * k)) & 0x3FF end
	local voc = VOCATIONS[r.voc] or ""
	local parts = { r.name .. (voc ~= "" and (", " .. voc) or "") .. (r.level and (", level " .. r.level) or "") }
	parts[#parts + 1] = "Experience " .. u32(n + 0x114)
	parts[#parts + 1] = "Strength " .. f(w1, 0)
	parts[#parts + 1] = "Agility " .. f(w1, 1)
	parts[#parts + 1] = "Resilience " .. f(w1, 2)
	parts[#parts + 1] = "Deftness " .. f(w2, 0)
	parts[#parts + 1] = "Charm " .. f(w2, 1)
	parts[#parts + 1] = "Magical mending " .. f(w2, 2)
	parts[#parts + 1] = "Magical might " .. f(w3, 0)
	parts[#parts + 1] = "Max HP " .. r.maxhp
	parts[#parts + 1] = "Max MP " .. r.maxmp
	parts[#parts + 1] = "Attack " .. u16(n + 0x34)
	parts[#parts + 1] = "Defence " .. u16(n + 0x36)
	return parts
end
-- one at a time with L (Shift+L goes back): the first is who it is, then each attribute; after the
-- last one it goes on to the next person in the party
attr_step = { who = 1, item = 0 }
function step_attributes(delta)
	local recs = party_records()
	if #recs == 0 then say("No party information.", true) return end
	local st = attr_step
	if st.who > #recs then st.who, st.item = 1, 0 end
	local list = attributes_of(recs[st.who])
	st.item = st.item + delta
	if st.item > #list then
		st.who, st.item = st.who % #recs + 1, 1
		list = attributes_of(recs[st.who])
	elseif st.item < 1 then
		st.who = (st.who - 2) % #recs + 1
		list = attributes_of(recs[st.who])
		st.item = #list
	end
	say(list[st.item] .. (SAY_POSITION_IN_MENUS and (", " .. st.item .. " of " .. #list) or ""), true)
end
local function say_attributes(only)
	local out = {}
	for _, r in ipairs(party_records()) do
		if not only or r.name == only then out[#out + 1] = table.concat(attributes_of(r), ". ") end
	end
	say(#out > 0 and table.concat(out, ". Next, ") or "No party information.", true)
end

-- Picking someone in the Attributes menu opens a picture of their attributes: read it out.
local attr_due, attr_who, pad_prev_a = nil, nil, false
pad_prev_a2 = false
local function watch_attributes(pad)
	-- (the menu's text stays in memory after it closes: it must be on screen now, with nothing said
	-- since but its options, and you must not be free to walk)
	if pad.a and not pad_prev_a and menu_title == "Attributes" and menu_items[menu_cursor]
		and last_menu_spoken > last_dialogue_frame and u8(0x02109DA4) ~= 1
		and cstring(MENU, 200):find("Attributes</TITLE>", 1, true) and cstring(MENU, 200):find("<CURSOR=", 1, true) then
		local who = menu_items[menu_cursor].text
		attr_due, attr_who = frame + 50, (who ~= "Whole Party") and who or nil
	end
	pad_prev_a = pad.a
	if attr_due and frame >= attr_due then
		attr_due = nil
		say_attributes(attr_who)
		if attr_who then
			for i, r in ipairs(party_records()) do if r.name == attr_who then attr_step.who, attr_step.item = i, 1 end end
		end
	end
end

local function say_gold()
	local g = u32(0x020F6D48)
	if g > 9999999 then say("Gold unknown.") return end
	say(g .. " gold", true)
end

local function say_where()
	local code = map_code()
	local px, py, pz = player_pos()
	local s = (settled and map_key(settled.code) == map_key(code) and settled.label) or map_name() or "Unknown place"
	if room_name() and map_name() and room_name() ~= map_name() then s = map_name() .. ", " .. room_name() end
	if px then
		local ex, sz = math.floor(px + 0.5), math.floor(pz + 0.5)
		s = s .. ". " .. (ex < 0 and ("west " .. -ex) or ("east " .. ex)) .. ", " ..
			(sz < 0 and ("north " .. -sz) or ("south " .. sz))
	end
	say(s)
end

------------------------------------------------------------------------------ debug ---------
local function hexdump(s)
	return (s:gsub(".", function(c)
		local b = c:byte()
		if b >= 32 and b < 127 then return c end
		return string.format("\\x%02X", b)
	end))
end
local function capture()
	local f = io.open(LOG_FILE, "a")
	if not f then say("Could not write the log.") return end
	f:write("==== frame " .. frame .. " " .. os.date() .. "\n")
	f:write("map " .. tostring(map_code()) .. " / " .. tostring(map_name()) .. "\n")
	local px, py, pz = player_pos()
	f:write(string.format("pos %s %s %s  battle %s\n", tostring(px), tostring(py), tostring(pz), tostring(in_battle())))
	f:write("dialogue " .. hexdump(cstring(DLG, 1200)) .. "\n")
	f:write(string.format("page %08X %08X\n", u32(PAGE_START), u32(PAGE_END)))
	-- the doors and exits here: where each one leads (map id), and what it is called
	pcall(function()
		local ds = {}
		for _, d in ipairs(doors_raw()) do ds[#ds + 1] = d end
		for _, d in ipairs(town_doors()) do ds[#ds + 1] = d end
		for _, d in ipairs(ds) do
			f:write(string.format("door kind %d id %d at %.1f %.1f label %s\n", d.kind or -1, d.id or -1, d.x or 0, d.z or 0, tostring(d.label)))
		end
	end)
	-- with a file called dq9-access-dump-ram.txt saying "on" in the access folder: all of main RAM to ram.bin (for working out the game)
	do local df = io.open(DIR .. "dq9-access-dump-ram.txt", "r")
	   local on = df and (df:read("a") or ""):find("on", 1, true)
	   if df then df:close() end
	   if on then
	       local out = io.open(DIR .. "ram.bin", "wb")
	       if out then
	           for base = 0x02000000, 0x023F0000, 0x10000 do
	               local t = read_bytes(base, 0x10000)
	               local parts = {}
	               for i = 1, #t, 4096 do parts[#parts + 1] = string.char(table.unpack(t, i, math.min(i + 4095, #t))) end
	               out:write(table.concat(parts))
	           end
	           out:close()
	       end
	   end end
	if MENU_DEBUG then
		for base = 0x02000000, 0x023F0000, 0x10000 do
			local t = read_bytes(base, 0x10000)
			for i = 1, #t - 3, 4 do
				if t[i] == 0x28 and t[i + 1] == 0xE6 and t[i + 2] == 0x14 and t[i + 3] == 0x02 then
					local a = base + i - 1
					f:write(string.format("yesno vtable at %08X: +28=%d\n", a, u8(a + 0x28)))
				end
			end
		end
	end
	f:write("menu " .. hexdump(cstring(MENU, 2400)) .. "\n")
	f:write(string.format("yesno %08X %d choice %d event %d %d\n", u32(yesno_obj), u8(yesno_obj + 0x28), u8(u32(PLAYER_PTR) + 0x250), u32(EVENT_CHOICE_COUNT), u32(EVENT_CHOICE_CURSOR)))
	for _, c in ipairs(characters()) do f:write(string.format("obj %08X %.2f %.2f\n", c.obj, c.x, c.z)) end
	-- the screen's boxes of words and numbers, when the screen is built from them
	pcall(function()
		local lp = u32(LAYOUT_PTR)
		if lp ~= 0 and inram(lp, 0x40) then
			local L = lp - 4
			local W, count, sel = u32(L + 4), u16(L + 8), u16(L + 0x36)
			f:write(string.format("layout %08X widgets %08X count %d selected %d\n", L, W, count, sel))
			for i = 0, math.min(count, 600) - 1 do
				local a = W + 0x30 * i
				local t = layout_box(L, W, i)
				if t then f:write(string.format("  %d x%d y%d w%d fl%04X %s\n", i, u16(a + 6), u16(a + 8), u16(a + 0x0A), u16(a + 0x12), t)) end
			end
		end
	end)
	f:write(string.format("equip %d %d %d %d shown %d\n", u32(EQUIP_LIST), u32(EQUIP_LIST + 8), u32(EQUIP_LIST + 0x18), u32(EQUIP_LIST + 0x1C), u16(EQUIP_SHOWN)))
	f:write("last said: " .. last_said .. "\n\n")
	f:close()
	say("Snapshot saved.")
end

------------------------------------------------------------------------------ keys ----------
local keys_prev = {}
local controller_pressed = false      -- a button on a game controller went down this frame
-- Names of controller buttons as EmuHawk reports them (X1 = first Xbox controller; J1 = other pads)
local function pad_name(k, names)
	if type(k) ~= "string" or not (k:match("^X%d ") or k:match("^J%d ")) then return false end
	local rest = k:gsub("^%u%d ", ""):lower()
	for _, n in ipairs(names) do if rest == n then return true end end
	return false
end
LT_NAMES = { "lefttrigger", "triggerleft", "lt", "z+" }
L3_NAMES = { "leftthumb", "leftstick", "ls", "l3", "b9" }
R3_NAMES = { "rightthumb", "rightstick", "rs", "r3", "b10" }
DPAD = {
	up = { "dpadup", "dpup", "pov1u" }, down = { "dpaddown", "dpdown", "pov1d" },
	left = { "dpadleft", "dpleft", "pov1l" }, right = { "dpadright", "dpright", "pov1r" },
}
local lt_held = false
local seen_pad_names = {}
-- keys on the keyboard that are bound to the game's buttons (they take over from auto walk)
GAME_KEYS = { Z = true, X = true, A = true, S = true, Q = true, E = true, Enter = true,
	Up = true, Down = true, Left = true, Right = true }
kb_ctrl_prev, kb_ctrl_alone = false, false
local function key_edges()
	local ok, now = pcall(function() return input.get() end)
	if not ok or type(now) ~= "table" then return {} end
	local pressed = {}
	controller_pressed = false
	lt_held = false
	kb_ctrl, kb_shift = false, false
	for k, v in pairs(now) do
		if v and pad_name(k, LT_NAMES) then lt_held = true end
		if v and type(k) == "string" then
			local l = k:lower()
			if l:find("ctrl", 1, true) or l:find("control", 1, true) then kb_ctrl = true end
			if l:find("shift", 1, true) then kb_shift = true end
		end
	end
	for k, v in pairs(now) do
		if v and not keys_prev[k] then
			pressed[k] = true
			USER_INPUT_FRAME = frame
			if GAME_KEYS[k] then controller_pressed = true end
			if type(k) == "string" and (k:match("^X%d ") or k:match("^J%d ")) then
				-- the left trigger and the combinations made with it do not take over from auto walk
				if not lt_held and not pad_name(k, LT_NAMES) and not pad_name(k, R3_NAMES) and not pad_name(k, L3_NAMES) then controller_pressed = true end
				if not seen_pad_names[k] then seen_pad_names[k] = true log_line("controller button: " .. k) end
			elseif type(k) == "string" and #k > 1 and not seen_pad_names[k] then
				seen_pad_names[k] = true
				log_line("key: " .. k)
			end
		end
	end
	keys_prev = now
	return pressed
end
local function pad_edge(pressed, names)
	for k in pairs(pressed) do if pad_name(k, names) then return true end end
	return false
end

-- The controller:
--   pressing in the left stick: everyone's HP and MP (in a battle too)
--   pressing in the right stick: gold (in a shop too)
-- Left trigger combinations:
--   LT + right / left on the D-pad: next / previous category of nearby things
--   LT + down / up on the D-pad: next / previous thing in that category
--   LT + pressing in the left stick: walk to the thing you picked
--   LT + pressing in the right stick: the 3D beacon to it
--   LT + the top face button (Y): the route to it, step by step (how far to go while the beacon is on)
Y_NAMES = { "y", "b4" }
BACK_NAMES = { "back", "select", "view", "b7" }
--   LT + Back (Select / View): the story guide, where to go next
local function handle_pad_combos(k)
	if not lt_held then
		if pad_edge(k, L3_NAMES) then say_party(true) end
		if pad_edge(k, R3_NAMES) then say_gold() end
		return
	end
	-- keep the D-pad and that face button away from the game while the trigger is held
	pcall(function() joypad.set({ Up = false, Down = false, Left = false, Right = false, X = false, Select = false }) end)
	if pad_edge(k, DPAD.right) then step_category(1) end
	if pad_edge(k, DPAD.left) then step_category(-1) end
	if pad_edge(k, DPAD.down) then step_nearby(1) end
	if pad_edge(k, DPAD.up) then step_nearby(-1) end
	if pad_edge(k, L3_NAMES) then if walk then stop_walk("Stopped.") else start_walk() end end
	if pad_edge(k, R3_NAMES) then
		if BEACON or (sel_item and sel_item.code == map_code()) then beacon_toggle()
		else say("Pick something on the list first.") end
	end
	if pad_edge(k, Y_NAMES) then
		if BEACON then beacon_status() else route_request() end
	end
	if pad_edge(k, BACK_NAMES) then say_guide() end
end

------------------------------------------------------------------------------ route ---------
-- Spoken directions along the planned route to the thing picked on the list: the same planner
-- as walking there, but you walk it yourself. "Up" and "left" are as on screen right now.
route = nil
counter_route = false
function route_request(beacon)
	local it = sel_item
	if not it then say("Pick something on the list first.") return end
	if it.code and it.code ~= map_code() then say("Pick something here first.") return end
	local px, py, pz = player_pos()
	if not px then say("Cannot plan a route right now.") return end
	local nv = nav_for()
	if not nv then say(it.label .. ", " .. directions_to(it.x, it.z) .. ". There is no map of the walls here to plan a route.", true) return end
	if reach_mark then reach_mark({ it }) end
	if it.unreachable then say(unreachable_msg(it), true) return end
	nv.bb = {}
	local gx, gz = it.x, it.z
	if it.nx then
		-- a door: go to just in front of it, on your side
		local sgn = ((px - it.x) * it.nx + (pz - it.z) * it.nz) >= 0 and 1 or -1
		if it.facing then sgn = 1 end
		gx, gz = it.x + it.nx * sgn * 1.2, it.z + it.nz * sgn * 1.2
	elseif it.rot and it.thing and not it.item and sign_front(nv, it) then
		-- a sign: the route goes to the side it can be read from
		local fr = sign_front(nv, it)
		gx, gz, counter_route = fr.x, fr.z, "sign"
	elseif it.obj then
		-- someone behind a counter: the route goes to the front of it
		local ap = counter_approach(nv, it.x, it.z, it.y0 or py or 0, it.obj)
		if ap then gx, gz, counter_route = ap.x, ap.z, true else counter_route = false end
	end
	if math.sqrt((gx - px) ^ 2 + (gz - pz) ^ 2) < 1.2 then
		if beacon then beacon_stop() end
		say(it.label .. " is " .. directions_to(it.x, it.z) .. ".", true)
		return
	end
	local avoid = avoid_list(it.x, it.z, px, pz)
	nv.py = select(2, player_pos())
	if beacon then
		local ok = sound and select(1, pcall(sound.ready)) and sound.ready()
		if not ok then
			say(sound and "No 3D sound: the file openal_soft.dll is missing from the DQ9 access folder." or
				"The beacon needs the new game part of the mod: run Install DQ9 Access.bat once.", true)
			return
		end
		beacon_start(it, gx, gz, nv, avoid, (it.obj or it.rot) and counter_route or nil)
		return
	end
	route = { it = it, sx = px, sz = pz, gx = gx, gz = gz, start = frame, counter = (it.obj or it.rot) and counter_route or nil,
		co = coroutine.create(function()
			local p, rem = plan_path(nv, px, py, pz, gx, gz, it.y0 and (it.y0 + 1) or nil, 0.45, true, 20000, avoid)
			for _, cl in ipairs({ 0.3, 0.2 }) do
				if rem > 1.0 and (gx - px) ^ 2 + (gz - pz) ^ 2 < 400 then
					local p2, rem2 = plan_path(nv, px, py, pz, gx, gz, it.y0 and (it.y0 + 1) or nil, cl, true, 20000, avoid)
					if rem2 < rem - 0.4 then p, rem = p2, rem2 end
				end
			end
			if rem > 1.5 then
				local p2, rem2 = find_path(nv, px, pz, gx, gz, 0.3, false, 20000, avoid)
				if rem2 < rem - 1 then p, rem = p2, rem2 end
			end
			return p, rem
		end) }
end
local function dirs_between(fx, fz, tx, tz)
	local ux, uz, rx, rz = screen_axes()
	local dx, dz = tx - fx, tz - fz
	local f, r = dx * ux + dz * uz, dx * rx + dz * rz
	local a = steps(f, f >= 0 and "up" or "down")
	local b = steps(r, r >= 0 and "right" or "left")
	if a and b then return math.abs(f) >= math.abs(r) and (a .. ", " .. b) or (b .. ", " .. a) end
	return a or b
end
function route_step()
	if not route then return end
	local ok, p, rem = plan_resume(route.co)
	if not ok then route = nil say("Could not plan a route.") return end
	if coroutine.status(route.co) ~= "dead" then
		if frame - route.start > 1800 then route = nil say("Could not plan a route.") end
		if frame - route.start == 90 then queue("Working out the route.") end
		return
	end
	local r = route
	route = nil
	local ux, uz, rx, rz = screen_axes()
	local pts = { { r.sx, r.sz } }
	for _, q in ipairs(p or {}) do pts[#pts + 1] = q end
	-- each leg: straight up, down, left or right, or a diagonal
	local legs = {}
	local function add(kind, n, n2)
		local last = legs[#legs]
		if last and last.kind == kind then last.n, last.n2 = last.n + n, (last.n2 or 0) + (n2 or 0)
		else legs[#legs + 1] = { kind = kind, n = n, n2 = n2 } end
	end
	for i = 2, #pts do
		local dx, dz = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
		local f, s = dx * ux + dz * uz, dx * rx + dz * rz
		local af, as = math.abs(f), math.abs(s)
		local v, h = f >= 0 and "up" or "down", s >= 0 and "right" or "left"
		if af >= 0.2 or as >= 0.2 then
			if as < 0.4 * af then add(v, af)
			elseif af < 0.4 * as then add(h, as)
			elseif math.abs(af - as) < 0.35 * math.max(af, as) then add(v .. " and " .. h, math.max(af, as))
			elseif af > as then add(v, af) add(h, as)
			else add(h, as) add(v, af) end
		end
	end
	local words = {}
	for _, l in ipairs(legs) do
		local n = math.floor(l.n + 0.5)
		if n >= 1 then
			if l.kind:find(" and ") then
				words[#words + 1] = n .. (n == 1 and " step " or " steps ") .. "diagonally " .. l.kind
			else
				words[#words + 1] = steps(l.n, l.kind)
			end
		end
	end
	local label = r.it.label
	local tail, here
	local last = pts[#pts]
	local rest = dirs_between(last[1], last[2], r.it.x, r.it.z)
	if (rem or 0) > 1.5 then
		local person = r.it.obj and not r.it.thing and not r.it.item and not r.it.monster
		local counter = person and rest and (rem or 0) < 3.3 and not rest:find(",") and ", most likely across a counter; face it and press A to talk" or ""
		tail = "that is as close as the way goes" .. (rest and ("; it is then " .. rest .. counter) or "")
		here = "you are as close as the way goes" .. (rest and (". It is " .. rest .. counter) or "")
	elseif r.counter == "sign" then
		tail = rest and ("then it is " .. rest .. "; face it and press A to read it") or "then face it and press A to read it"
		here = rest and ("it is " .. rest .. "; face it and press A to read it") or "face it and press A to read it"
	elseif r.counter then
		tail = rest and ("then it is " .. rest .. " across the counter; face it and press A to talk") or "then talk across the counter"
		here = rest and ("it is " .. rest .. " across the counter; face it and press A to talk") or "talk across the counter"
	elseif r.it.nx or r.it.kind == 1 then
		tail = r.it.kind == 1 and "then walk into the door" or "then walk on through"
	else
		tail = "then you are there"
	end
	if #words == 0 then say(label:gsub("^%l", string.upper) .. ": " .. (here or tail) .. ".", true) return end
	local more = ""
	if #words > 8 then
		for i = #words, 9, -1 do table.remove(words, i) end
		more = ", and after that press again for the rest"
		tail = nil
	end
	say("Route to " .. label .. ": " .. table.concat(words, ", then ") .. (tail and (", " .. tail) or more) .. ".", true)
end

------------------------------------------------------------------------------ beacon --------
-- The 3D beacon (left trigger + right stick, or F): walk there yourself, following a knock placed
-- all round you on headphones where the next turn of the way is. Faster the nearer that turn is;
-- lower when it is behind you; a second, higher knock with it when you are heading straight for
-- it; a chime at each turn and on arriving. "Ahead" is up on the screen, the way the D-pad walks
-- you. The way is worked out again when you wander off it.
BEACON = nil
function beacon_stop(msg)
	BEACON = nil
	if msg then say(msg, true) end
end
function beacon_plan(b, nv, px, py, pz)
	local gx, gz, gy, avoid = b.gx, b.gz, b.gy, b.avoid
	b.co = coroutine.create(function()
		local p, rem = plan_path(nv, px, py, pz, gx, gz, gy, 0.45, true, 20000, avoid)
		for _, cl in ipairs({ 0.3, 0.2 }) do
			if rem > 1.0 and (gx - px) ^ 2 + (gz - pz) ^ 2 < 400 then
				local p2, rem2 = plan_path(nv, px, py, pz, gx, gz, gy, cl, true, 20000, avoid)
				if rem2 < rem - 0.4 then p, rem = p2, rem2 end
			end
		end
		if rem > 1.5 then
			local p2, rem2 = find_path(nv, px, pz, gx, gz, 0.3, false, 20000, avoid)
			if rem2 < rem - 1 then p, rem = p2, rem2 end
		end
		return p, rem
	end)
	b.plan_start = frame
end
function beacon_start(it, gx, gz, nv, avoid, counter)
	local px, py, pz = player_pos()
	walk = nil                 -- the beacon takes over from an auto walk: you walk yourself now
	BEACON = { it = it, label = it.label, gx = gx, gz = gz, gy = it.y0 and (it.y0 + 1) or nil, avoid = avoid, counter = counter,
	           code = map_code(), path = nil, pi = 1, next_knock = frame, best = 1e9, progress = frame,
	           obj = (not counter) and it.obj or nil, posoff = it.posoff or 0x24, moved = frame }
	beacon_plan(BEACON, nv, px, py, pz)
	say("Beacon to " .. it.label .. ".", true)
end
function beacon_step()
	local b = BEACON
	if not b then return end
	if map_code() ~= b.code then beacon_stop() return end
	local px, py, pz = player_pos()
	if not px then return end
	-- quiet while someone talks, a menu is open, a scene plays or a battle is on; on again after
	if u8(0x02109DA4) ~= 1 or in_battle() or frame - last_dialogue_frame < 20 then
		b.next_knock = math.max(b.next_knock, frame + 20)
		b.progress = frame
		b.lock_at = nil
		return
	end
	-- someone who walks about: follow them, working the way out again when they have moved
	if b.obj and inram(b.obj, 0x80) then
		local ox, oz = s32(b.obj + b.posoff) / 4096, s32(b.obj + b.posoff + 8) / 4096
		if (ox - b.gx) ^ 2 + (oz - b.gz) ^ 2 > 2.25 and frame - b.moved > 90 and not b.co then
			b.gx, b.gz, b.moved = ox, oz, frame
			local nv = nav_for()
			if nv then nv.py = py beacon_plan(b, nv, px, py, pz) end
		end
	end
	if b.co then
		local ok, p, rem = plan_resume(b.co)
		if not ok then b.co = nil
		elseif coroutine.status(b.co) == "dead" then
			b.co, b.path, b.pi, b.rem = nil, p or {}, 1, rem or 0
			b.best, b.progress = 1e9, frame
		end
	end
	-- arrived
	local gd = math.sqrt((b.gx - px) ^ 2 + (b.gz - pz) ^ 2)
	-- the way ends short of it (a counter, a fence) and you are at that end: stop here
	local endp = b.path and b.path[#b.path]
	if not b.co and (b.rem or 0) > 1.5 and endp and ((endp[1] - px) ^ 2 + (endp[2] - pz) ^ 2) < 0.64
		and gd >= (b.it.obj and 1.2 or 0.8) then
		pcall(sound.play, "chime", 0, 0, -0.5, 0.8)
		local ux, uz, rx, rz = screen_axes()
		local f, r = (b.gx - px) * ux + (b.gz - pz) * uz, (b.gx - px) * rx + (b.gz - pz) * rz
		local face = math.abs(f) >= math.abs(r) and (f >= 0 and "up" or "down") or (r >= 0 and "right" or "left")
		local person = b.it.obj and not b.it.thing and not b.it.item and not b.it.monster
		local msg = "As close as the way goes. " .. b.label:gsub("^%l", string.upper) .. " is " .. directions_to(b.gx, b.gz)
		if person and gd < 3.3 and math.min(math.abs(f), math.abs(r)) < 0.8 then
			msg = msg .. ", most likely across a counter. Face " .. face .. " and press A to talk"
		end
		beacon_stop(msg .. ".")
		return
	end
	if gd < (b.it.obj and 1.2 or 0.8) then
		pcall(sound.play, "chime", 0, 0, -0.5, 0.8)
		-- which way to face: up, down, left or right on the screen
		local ux, uz, rx, rz = screen_axes()
		local tx, tz = b.gx, b.gz
		if b.it.x and b.counter then tx, tz = b.it.x, b.it.z end
		local f, r = (tx - px) * ux + (tz - pz) * uz, (tx - px) * rx + (tz - pz) * rz
		local face = math.abs(f) >= math.abs(r) and (f >= 0 and "up" or "down") or (r >= 0 and "right" or "left")
		local what
		if b.counter == "sign" then what = ". Face " .. face .. " and press A to read it"
		elseif b.counter then what = ". Face " .. face .. " and press A to talk across the counter"
		elseif b.it.kind == 1 then what = ". Walk " .. face .. " into the door"
		elseif b.it.kind == 0 then what = ". Walk " .. face .. " to go through"
		elseif b.it.monster then what = ". It is " .. face .. " from you; walk into it to fight"
		elseif b.it.obj and not b.it.thing then what = ". Face " .. face .. " and press A to talk"
		else what = ". It is " .. face .. " from you; face it and press A" end
		beacon_stop("Arrived at " .. b.label .. what .. ".")
		return
	end
	-- the next turn of the way: passed ones are left behind
	local path = b.path or {}
	local wp = path[b.pi]
	while wp and ((wp[1] - px) ^ 2 + (wp[2] - pz) ^ 2) < 0.64 do
		b.pi = b.pi + 1
		wp = path[b.pi]
		b.best, b.progress = 1e9, frame
		if wp and TURN_CHIME_ON then pcall(sound.play, "chime", 0, 0, -0.5, 0.45 * BEACON_VOL / 10) end
		if wp and TURN_SPEECH_ON then say("Then " .. beacon_leg(px, pz, wp[1], wp[2]) .. ".", true) end
	end
	local tx, tz = b.gx, b.gz
	if wp then tx, tz = wp[1], wp[2] end
	local dx, dz = tx - px, tz - pz
	local d = math.sqrt(dx * dx + dz * dz)
	-- wandered off the way, or getting no nearer: work it out again from here
	if not b.co then
		if d < b.best - 0.3 then b.best, b.progress = d, frame end
		local off = false
		if wp and b.pi > 1 then
			local a = path[b.pi - 1]
			off = seg_dist2(px, pz, a[1], a[2], wp[1], wp[2]) > 2.5 * 2.5
		end
		if off or frame - b.progress > 360 then
			local nv = nav_for()
			if nv then nv.py = py beacon_plan(b, nv, px, py, pz) end
		end
	end
	-- the knock
	if frame >= b.next_knock then
		local ux, uz, rx, rz = screen_axes()
		local f, r = dx * ux + dz * uz, dx * rx + dz * rz
		local ang = (math.atan2 or math.atan)(r, f)          -- 0 straight ahead (up), more than 0 to the right
		local hd = math.max(0.6, math.min(d, 12))
		local sx, sz = math.sin(ang) * hd, -math.cos(ang) * hd
		local behind = math.abs(ang) > 1.75
		pcall(sound.play, "knock", sx, 0, sz, 1.25 * BEACON_VOL / 10, behind and 0.7 or 1.0)
		if math.abs(ang) < 0.25 then b.lock_at, b.lock_pos = frame + 4, { sx, sz } end
		b.next_knock = frame + math.floor(60 * math.max(0.18, math.min(1.1, 0.12 + d * 0.09)) + 0.5)
	end
	if b.lock_at and frame >= b.lock_at then
		pcall(sound.play, "lock", b.lock_pos[1], 0, b.lock_pos[2], 0.9 * BEACON_VOL / 10)
		b.lock_at = nil
	end
end
-- one leg of the way, as you would walk it on the D-pad: "5 steps left" (and "2 steps up" when it
-- is slanted)
function beacon_leg(x0, z0, x1, z1)
	local ux, uz, rx, rz = screen_axes()
	local dx, dz = x1 - x0, z1 - z0
	local f, r = dx * ux + dz * uz, dx * rx + dz * rz
	local a = steps(f, f >= 0 and "up" or "down")
	local c = steps(r, r >= 0 and "right" or "left")
	if a and c then
		if math.abs(f) >= math.abs(r) then
			return math.abs(r) < 0.35 * math.abs(f) and a or (a .. " and " .. c)
		end
		return math.abs(f) < 0.35 * math.abs(r) and c or (c .. " and " .. a)
	end
	return a or c or "a step"
end
-- where the beacon is taking you, said when you ask (the route key while the beacon is on)
function beacon_status()
	local b = BEACON
	local px, _, pz = player_pos()
	if not b or not px then return end
	if b.co then say("Working out the way to " .. b.label .. ".", true) return end
	local path = b.path or {}
	local x, z, left = px, pz, 0
	for i = b.pi, #path do
		left = left + math.sqrt((path[i][1] - x) ^ 2 + (path[i][2] - z) ^ 2)
		x, z = path[i][1], path[i][2]
	end
	left = left + math.sqrt((b.gx - x) ^ 2 + (b.gz - z) ^ 2)
	local n = math.max(1, math.floor(left + 0.5))
	local t = b.label .. ", " .. n .. (n == 1 and " step" or " steps") .. " to go. "
	local wp = path[b.pi]
	if wp then
		t = t .. "Next: " .. beacon_leg(px, pz, wp[1], wp[2])
		local nx = path[b.pi + 1] or { b.gx, b.gz }
		if (nx[1] - wp[1]) ^ 2 + (nx[2] - wp[2]) ^ 2 > 0.8 then
			t = t .. ", then " .. beacon_leg(wp[1], wp[2], nx[1], nx[2])
		end
		t = t .. "."
	else
		t = t .. beacon_leg(px, pz, b.gx, b.gz) .. "."
	end
	say(t, true)
end
function beacon_toggle()
	if BEACON then beacon_stop("Beacon off.") return end
	route_request(true)
end

-- The auto walk beep: faster the nearer you are to where you are going (along the way, not as the
-- crow flies), and quiet once you are there.
WALK_BEEP_NEXT = 0
-- The auto walk beep, louder than a sound can be played at once: the same beep on two or three
-- sounds together adds up (volume 10 is a little over twice the old loudest)
function walk_beep_sound()
	local g = 2.2 * WALK_BEEP_VOL / 10
	local copies = math.max(1, math.ceil(g))
	for _ = 1, copies do pcall(sound.play, "beep", 0, 0, -1, g / copies) end
end
function walk_beep()
	if not walk or not sound or not WALK_BEEP_ON then WALK_BEEP_NEXT = 0 return end
	local px, _, pz = player_pos()
	if not px or frame < WALK_BEEP_NEXT then return end
	local left
	if walk.path and walk.pi then
		local x, z = px, pz
		left = 0
		for i = walk.pi, #walk.path do
			local q = walk.path[i]
			left = left + math.sqrt((q[1] - x) ^ 2 + (q[2] - z) ^ 2)
			x, z = q[1], q[2]
		end
		left = left + math.sqrt(((walk.tx0 or walk.x) - x) ^ 2 + ((walk.tz0 or walk.z) - z) ^ 2)
	else
		left = math.sqrt(((walk.tx0 or walk.x) - px) ^ 2 + ((walk.tz0 or walk.z) - pz) ^ 2)
	end
	if WALK_BEEP_ON and WALK_BEEP_VOL > 0 then walk_beep_sound() end
	-- (quick from the start: half a second apart at 20 steps or more, down to a tenth of a second)
	WALK_BEEP_NEXT = frame + math.floor(60 * math.max(0.1, math.min(0.5, 0.08 + left * 0.021)) + 0.5)
end

------------------------------------------------------------------------------ mod settings --
-- An extra item at the end of the game's Misc. menu: "Mod settings". Down from the last item
-- (Quick Save) or up from the first (Heal All) gets to it, as the menu wraps round; A opens the
-- mod's settings. While you are on it, or in the settings, the game does not get the D-pad, A
-- or B (the buttons are read as you press them: joypad.getraw).
SETTINGS_FILE = DIR .. "dq9-access-settings.txt"
SETTINGS = {
	{ name = "Auto walk beep", get = function() return WALK_BEEP_ON end, set = function(v) WALK_BEEP_ON = v end, key = "walk_beep" },
	{ name = "Auto walk beep volume", level = true, get = function() return WALK_BEEP_VOL end, set = function(v) WALK_BEEP_VOL = v end, key = "walk_beep_volume" },
	{ name = "Beacon volume", level = true, get = function() return BEACON_VOL end, set = function(v) BEACON_VOL = v end, key = "beacon_volume" },
	{ name = "Beacon chime at each turn", get = function() return TURN_CHIME_ON end, set = function(v) TURN_CHIME_ON = v end, key = "turn_chime" },
	{ name = "Beacon says each turn of the way", get = function() return TURN_SPEECH_ON end, set = function(v) TURN_SPEECH_ON = v end, key = "turn_speech" },
	{ name = "Test the beacon on headphones", action = "test" },
	{ name = "Bump sound when you walk into something", get = function() return BUMP_SOUND_ON end, set = function(v) BUMP_SOUND_ON = v end, key = "bump_sound" },
	{ name = "Blocked alert, when you walk into something", get = function() return ALERTS_ON end, set = function(v) ALERTS_ON = v end, key = "blocked_alert" },
	{ name = "Say the position in menus, such as 2 of 6", get = function() return SAY_POSITION_IN_MENUS end, set = function(v) SAY_POSITION_IN_MENUS = v end, key = "menu_position" },
	{ name = "Say people and monsters coming close", get = function() return NEARBY_ALERTS end, set = function(v) NEARBY_ALERTS = v end, key = "nearby_alerts" },
	{ name = "Close", action = "close" },
}
function settings_load()
	local f = io.open(SETTINGS_FILE, "r")
	if not f then return end
	for line in f:lines() do
		local k, v = line:match("^%s*([%w_]+)%s*=%s*(%S+)")
		for _, s in ipairs(SETTINGS) do
			if s.key and s.key == k then
				if s.level then local n = tonumber(v) if n then s.set(math.max(0, math.min(10, math.floor(n)))) end
				else s.set(v == "on" or v == "true") end
			end
		end
	end
	f:close()
end
function settings_save()
	local f = io.open(SETTINGS_FILE, "w")
	if not f then return end
	f:write("# DQ9 Access settings (Mod settings, at the end of the game's Misc. menu)\n")
	for _, s in ipairs(SETTINGS) do
		if s.key then
			local v = s.get()
			f:write(s.key .. " = " .. (s.level and tostring(v) or (v and "on" or "off")) .. "\n")
		end
	end
	f:close()
end
function setting_text(s, i)
	local t = s.name
	if s.get then
		local v = s.get()
		t = t .. ", " .. (s.level and tostring(v) or (v and "on" or "off"))
	end
	return t .. ", " .. i .. " of " .. #SETTINGS
end
MS = { on_item = false, open = false, sel = 1, prev = {}, inject = nil, test = nil }
MS_BUTTONS = { "Up", "Down", "Left", "Right", "A", "B" }
function misc_menu_now()
	if u8(0x02109DA4) == 1 then return nil end
	local m = cstring(MENU, 700)
	if not m:find("^<CURSOR=%d+>Misc%.") then return nil end
	local cursor = tonumber(m:match("^<CURSOR=(%d+)>"))
	local count = 0
	for _ in m:gmatch("<N=%d+>") do count = count + 1 end
	if count == 0 then return nil end
	return cursor, count
end
function misc_say_item(cursor, count)
	local m = cstring(MENU, 700)
	local name = m:match("<N=" .. cursor .. ">(.-)</N>")
	name = name and clean(name) or "item"
	say(name .. (SAY_POSITION_IN_MENUS and (", " .. (cursor + 1) .. " of " .. (count + 1)) or ""), true)
end
function ms_say_item(count)
	say("Mod settings" .. (SAY_POSITION_IN_MENUS and (", " .. (count + 1) .. " of " .. (count + 1)) or ""), true)
end
-- the beacon test: a knock in front, to the right, behind and to the left, each said first
function ms_test_step()
	local t = MS.test
	if not t or frame < t.next then return end
	local spots = { { "In front.", 0, -2 }, { "To the right.", 2, 0 }, { "Behind.", 0, 2 }, { "To the left.", -2, 0 } }
	local spot = spots[t.spot]
	if not spot then MS.test = nil say("Done.") return end
	if t.knock == 0 then say(spot[1], true) t.knock, t.next = 1, frame + 50 return end
	pcall(sound.play, "knock", spot[2], 0, spot[3], 1.25 * BEACON_VOL / 10, spot[3] > 0.5 and 0.7 or 1.0)
	t.knock = t.knock + 1
	t.next = frame + 26
	if t.knock > 3 then t.spot, t.knock, t.next = t.spot + 1, 0, frame + 40 end
end
function misc_step()
	if not joypad.getraw then return end
	ms_test_step()
	local cursor, count = misc_menu_now()
	if not cursor then
		if MS.open or MS.on_item then MS.open, MS.on_item = false, false end
		MS.inject = nil
		return
	end
	local ok, raw = pcall(joypad.getraw)
	if not ok or type(raw) ~= "table" then return end
	local edge = {}
	for _, b in ipairs(MS_BUTTONS) do edge[b] = raw[b] and not MS.prev[b] MS.prev[b] = raw[b] end
	-- a button pressed for the mod stays away from the game until you let go of it
	MS.held = MS.held or {}
	local keep = {}
	for b in pairs(MS.held) do if raw[b] then keep[b] = false else MS.held[b] = nil end end
	if next(keep) then pcall(joypad.set, keep) end
	local function used(b) MS.held[b] = true end
	-- a press made for you (moving the game's cursor round the end of the list)
	if MS.inject then
		local i = MS.inject
		pcall(joypad.set, { [i.button] = true })
		i.frames = i.frames - 1
		if i.frames <= 0 then MS.inject = nil end
		return
	end
	local last = count - 1
	if MS.open then
		pcall(joypad.set, { Up = false, Down = false, Left = false, Right = false, A = false, B = false })
		for _, b in ipairs(MS_BUTTONS) do if edge[b] then used(b) end end
		local s = SETTINGS[MS.sel]
		if edge.Down then MS.sel = MS.sel % #SETTINGS + 1 say(setting_text(SETTINGS[MS.sel], MS.sel), true)
		elseif edge.Up then MS.sel = (MS.sel - 2) % #SETTINGS + 1 say(setting_text(SETTINGS[MS.sel], MS.sel), true)
		elseif (edge.Left or edge.Right) and s.get then
			if s.level then s.set(math.max(0, math.min(10, s.get() + (edge.Right and 1 or -1))))
			else s.set(not s.get()) end
			settings_save()
			say(s.level and tostring(s.get()) or (s.get() and "on" or "off"), true)
			if s.level and sound then
				if s.key == "beacon_volume" then pcall(sound.play, "knock", 0, 0, -2, 1.25 * BEACON_VOL / 10)
				else walk_beep_sound() end
			end
		elseif edge.A then
			if s.action == "close" then MS.open = false ms_say_item(count)
			elseif s.action == "test" then
				if sound and select(2, pcall(sound.ready)) then MS.test = { spot = 1, knock = 0, next = frame }
				else say("No 3D sound: openal_soft.dll is missing, or the game part of the mod needs installing.", true) end
			elseif s.get then
				if s.level then s.set(s.get() >= 10 and 0 or s.get() + 1) else s.set(not s.get()) end
				settings_save()
				say(s.level and tostring(s.get()) or (s.get() and "on" or "off"), true)
			end
		elseif edge.B then MS.open = false ms_say_item(count) end
		return
	end
	if MS.on_item then
		pcall(joypad.set, { Up = false, Down = false, A = false })
		if edge.A then used("A") end
		if edge.Down then
			MS.on_item = false
			used("Down")
			if cursor == last then MS.inject = { button = "Down", frames = 4 } else misc_say_item(cursor, count) end
		elseif edge.Up then
			MS.on_item = false
			used("Up")
			if cursor == 0 then MS.inject = { button = "Up", frames = 4 } else misc_say_item(cursor, count) end
		elseif edge.A then
			MS.open = true
			say("Mod settings. Up and down choose, left and right or A change, B goes back. " .. setting_text(SETTINGS[MS.sel], MS.sel), true)
		end
		return
	end
	-- on the last item: down goes to Mod settings; on the first: up does
	local hold = {}
	if cursor == last then hold.Down = false end
	if cursor == 0 then hold.Up = false end
	if next(hold) then pcall(joypad.set, hold) end
	if (cursor == last and edge.Down) or (cursor == 0 and edge.Up) then
		used(edge.Down and "Down" or "Up")
		MS.on_item = true
		ms_say_item(count)
	end
end

HELP = "R repeat. Control stops speech. W where am I. H health. M magic. L next attribute, one at a time, Shift L previous. U equipment. G gold. I last information. O all menu options. " ..
	"Page Down and Page Up, next and previous nearby thing. Control with Page Down and Page Up, next and previous category. " ..
	"Control Home, route there. Control End, walk there. " ..
	"N and B also go through the nearby things, V next category. D directions again. P route there. J walk there. F beacon there, to walk yourself, F again stops it. Shift M mark this spot. " ..
	"Y story guide: where to go next, and what opens the locked doors here. T alerts on or off. C save a debug snapshot. K keys. " ..
	"On the controller, hold the left trigger: D-pad right and left change category, down and up go through the things in it, " ..
	"pressing in the left stick walks there, pressing in the right stick starts the 3D beacon to it, to walk there yourself on headphones, again to stop it, " ..
	"the top face button gives the route to it, step by step, and the Back button gives the story guide. " ..
	"Without the trigger: pressing in the left stick gives everyone's HP and MP, pressing in the right stick gives your gold."

-- the nearby list on the keyboard: Page Up / Page Down go through the things in a category,
-- with Ctrl through the categories; Ctrl+Home gives the route, Ctrl+End walks there
PAGE_UP, PAGE_DOWN = { "PageUp", "Prior" }, { "PageDown", "Next" }
function any_key(k, names)
	for _, n in ipairs(names) do if k[n] then return true end end
	return false
end
local function handle_keys()
	local k = key_edges()
	handle_pad_combos(k)
	-- Ctrl pressed and let go on its own stops speech (as with a screen reader)
	if kb_ctrl and not kb_ctrl_prev then kb_ctrl_alone = true end
	for key in pairs(k) do
		local l = type(key) == "string" and key:lower() or ""
		if not (l:find("ctrl", 1, true) or l:find("control", 1, true)) then kb_ctrl_alone = false end
	end
	if kb_ctrl_prev and not kb_ctrl and kb_ctrl_alone then kb_ctrl_alone = false stop_speech() end
	kb_ctrl_prev = kb_ctrl
	if any_key(k, PAGE_UP) then if kb_ctrl then step_category(-1) else step_nearby(-1) end end
	if any_key(k, PAGE_DOWN) then if kb_ctrl then step_category(1) else step_nearby(1) end end
	if kb_ctrl then
		if k["Home"] then route_request() end
		if k["End"] then if walk then stop_walk("Stopped.") else start_walk() end end
		return                          -- Ctrl with a letter is left to the emulator
	end
	if k[KEYS.repeat_last] then say(last_said) end
	if k[KEYS.stop] then stop_speech() end
	if k[KEYS.where] then say_where() end
	if k[KEYS.party] then say_hp_mp("hp") end
	if k[KEYS.mp] and not kb_shift then say_hp_mp("mp") end
	if k[KEYS.gold] then say_gold() end
	if k[KEYS.equipment] then say_equipment() end
	if k[KEYS.stats] then step_attributes(kb_shift and -1 or 1) end
	if k[KEYS.info] then say(last_info ~= "" and last_info or "No information yet.") end
	if k[KEYS.options] then read_all_options() end
	if k[KEYS.next_thing] then step_nearby(1) end
	if k[KEYS.category] then step_category(1) end
	if k[KEYS.prev_thing] then step_nearby(-1) end
	if k[KEYS.directions] then
		if nearby[selected] then
			local it = nearby[selected]
			say(it.label .. ", " .. directions_to(it.x, it.z))
		else say("Pick something on the list first.") end
	end
	if k[KEYS.mark] and kb_shift then
		local code = map_code()
		local x, _, z = player_pos()
		if code and x then
			local n = 1
			for _, p in ipairs(places) do if p.code == place_key() and p.kind == "mark" then n = n + 1 end end
			add_place(place_key(), "mark", x, z, "mark " .. n)
			say("Marked, mark " .. n)
		else say("Cannot mark here.") end
	end
	if k[KEYS.walk] then if walk then stop_walk("Stopped.") else start_walk() end end
	if k[KEYS.route] then if BEACON then beacon_status() else route_request() end end
	if k[KEYS.beacon] then beacon_toggle() end
	if k[KEYS.alerts] then
		ALERTS_ON = not ALERTS_ON
		say(ALERTS_ON and "Alerts on" or "Alerts off")
	end
	if k[KEYS.capture] then capture() end
	if k[KEYS.help] then say(HELP) end
	if k[KEYS.guide] then say_guide() end
end

------------------------------------------------------------------------------ start ---------
local function game_ok()
	local ok, code = pcall(function()
		local c = {}
		for i = 0, 3 do c[#c + 1] = string.char(memory.read_u8(0x0C + i, "ROM")) end
		return table.concat(c)
	end)
	if ok and code == "YDQE" then return true end
	local ok2, name = pcall(function() return gameinfo.getromname() end)
	return ok2 and type(name) == "string" and name:lower():find("dragon quest ix", 1, true) ~= nil
end

if not game_ok() then
	say("This script is for Dragon Quest 9, US version. Load that game first, then open the script again.")
	return
end

load_places()
pcall(settings_load)
menu_raw_done = cstring(MENU, 2400)     -- do not read out a menu left over from before the script started
menu_raw_seen, menu_seen_count = menu_raw_done, 2
-- the message buffer keeps the last message after its box closes, so do not read it out at start
do
	local raw = cstring(DLG, 1200)
	dlg_last_raw = raw
	local offset = u32(PAGE_START) - DLG
	dlg_last_page = 1
	if raw ~= "" and offset > 0 and offset < #raw then
		for k, pg in ipairs(split_pages(raw)) do if offset + 1 >= pg[1] then dlg_last_page = k end end
	end
	dlg_sig = mem_str(DLG, 48) .. ":" .. u32(PAGE_START) .. ":" .. u32(PAGE_END)
end
say("Dragon Quest 9 access " .. MOD_VERSION .. (DQIX_PC and " for the PC version" or "") .. " is running. Press K for keys.")
pcall(function() event.onexit(function() stop_speech() end) end)
local last_error = nil

-- Timing of each part of a frame (a file called dq9-access-profile.txt saying "on"): frames that
-- take longer than 4 ms are written to the speech log with the slowest parts.
PROFILE_ON = false
do local f = io.open(DIR .. "dq9-access-profile.txt", "r") if f then PROFILE_ON = (f:read("a") or ""):find("on", 1, true) ~= nil f:close() end end
prof = { t0 = nil, name = nil, parts = {}, start = nil }
function PT(name)
	if not PROFILE_ON then return end
	local now = os.clock()
	if prof.name then prof.parts[prof.name] = (prof.parts[prof.name] or 0) + (now - prof.t0) end
	if not prof.start then prof.start = now end
	prof.name, prof.t0 = name, now
	if not name then
		local total = now - prof.start
		if total > 0.004 then
			local list = {}
			for k, v in pairs(prof.parts) do if v > 0.0005 then list[#list + 1] = { k, v } end end
			table.sort(list, function(a, b) return a[2] > b[2] end)
			local t = {}
			for i = 1, math.min(5, #list) do t[#t + 1] = string.format("%s %.1f", list[i][1], list[i][2] * 1000) end
			log_line(string.format("slow frame %.1f ms: %s", total * 1000, table.concat(t, ", ")))
		end
		prof.parts, prof.start = {}, nil
	end
end
while true do
	frame = frame + 1
	local pad = pad_state()
	for _, n in ipairs({ "a", "b", "x", "y", "start", "select", "up", "down", "left", "right", "l", "r" }) do
		if pad[n] and not pad_prev[n] then last_button_frame, last_button_name = frame, n USER_INPUT_FRAME = frame end
	end
	-- A on something in the equipment list opens its little Equip / Move / Discard list; A or B there closes it
	if last_button_frame == frame and (last_button_name == "a" or last_button_name == "b") then
		if equip_popup_open then equip_popup_open, equip_popup_arm = false, nil
		elseif last_button_name == "a" and equip_state and equip_state:sub(1, 4) == "grid" then equip_popup_arm = frame end
	end
	pad_prev = pad

	local ok, err = pcall(function()
		-- remember experience only out in the world with no message up (the reward is added
		-- while the battle's closing messages are still showing)
		if battle_phase() ~= round_phase then
			if battle_phase() == 3 then battle_round = battle_round + 1 end
			round_phase = battle_phase()
		end
		if not in_battle() then mon_reset() end
		if in_battle() then
			battle_seen_frame, exp_frozen = frame, true
		elseif exp_frozen then
			-- after a battle, wait until you are walking again (or the reward has been read)
			local px, _, pz = player_pos()
			if px and not exp_freeze_pos then exp_freeze_pos = { px, pz } end
			if px and exp_freeze_pos and math.abs(px - exp_freeze_pos[1]) + math.abs(pz - exp_freeze_pos[2]) > 0.5 then
				exp_frozen, exp_freeze_pos = false, nil
			end
		elseif frame % 30 == 0 and frame - last_dialogue_frame > 90 and frame - battle_seen_frame > 120 then snapshot_experience() end
		PT("read_dialogue") read_dialogue()
		PT("spell_cost_tick") spell_cost_tick()
		PT("read_menu") read_menu()
		pcall(watch_target_sub, menu_items, menu_cursor, menu_raw_seen)
		PT("watch_spinner") watch_spinner()
		PT("read_greeting_entry") read_greeting_entry()
		PT("read_yesno") read_yesno()
		PT("read_battle_phase") read_battle_phase()
		PT("watch_battle_actor") watch_battle_actor()
		PT("read_title") read_title()
		PT("read_equip_screen") read_equip_screen()
		PT("read_layout") read_layout()
		PT("watch_mon_page") watch_mon_page()
		PT("read_ui_screen") read_ui_screen()
		PT("read_records_menu") read_records_menu(pad)
		PT("read_choice") read_choice()
		PT("watch_two_choice") watch_two_choice()
		PT("read_create") read_create()
		PT("watch_attributes") watch_attributes(pad)
		PT("watch_events") if frame % 15 == 0 then watch_events() end
		PT("mark_searched")
		if pad.a and not pad_prev_a2 and not in_battle() and frame - last_menu_frame > 30 then pcall(mark_searched) end
		pad_prev_a2 = pad.a
		PT("read_name_entry") read_name_entry()
		PT("track_map") track_map()
		PT("guide_tick") guide_tick()
		PT("alerts") if not walk then alerts(pad) end
		PT("handle_keys") handle_keys()
		PT("walk_step") walk_step(controller_pressed)
		walk_resume_step()
		PT("route_step") route_step()
		beacon_step()
		pcall(reach_big_step)
		walk_beep()
		misc_step()
		PT("nav_prefetch") nav_prefetch()

		PT(nil)	end)
	if not ok and tostring(err) ~= last_error then
		last_error = tostring(err)
		console.log("dq9-access error: " .. last_error)
		log_line("ERROR " .. last_error)
	end
	emu.frameadvance()
end
