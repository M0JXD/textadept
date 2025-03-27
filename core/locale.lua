-- Copyright 2007-2025 Mitchell. See LICENSE.

--- Map of all messages used by Textadept to their localized forms.
-- If the localized form of a given message does not exist, the non-localized message is
-- returned. Use Lua's `rawget()` to check if a localization exists.
--
-- Terminal version note: any "_" or "&" mnemonics the GUI version would use are ignored.
-- @module _L
local M = {}

local locale_file = _USERHOME .. '/locale.conf'
if not lfs.attributes(locale_file) then
	local lang = (os.getenv('LANG') or ''):match('^[^_.@]+') -- TODO: LC_MESSAGES?
	if lang then locale_file = string.format('%s/core/locales/locale.%s.conf', _HOME, lang) end
end
if not lfs.attributes(locale_file) then locale_file = _HOME .. '/core/locale.conf' end
local f<close> = assert(io.open(locale_file, 'rb'), '"core/locale.conf" not found')
for line in f:lines() do
	-- Any line that starts with a non-word character except '[' is considered a comment.
	if not line:find('^%s*[%w_%[]') then goto continue end
	local id, str = line:match('^(.-)%s*=%s*(.-)\r?$')
	if id and str and assert(not M[id], 'duplicate locale key "%s"', id) then
		M[id] = GTK and str or str:gsub('_', QT and '&' or '')
	end
	::continue::
end

setmetatable(M, {__index = function(_, k) return k end})
if QT then getmetatable(M).__newindex = function(t, k, v) rawset(t, k, v:gsub('_', '&')) end end
return M
