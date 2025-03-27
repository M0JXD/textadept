-- Copyright 2007-2025 Mitchell. See LICENSE.

--- Extends Lua's _G table to provide extra functions and fields for Textadept.
-- @module _G

for _, arg in ipairs(arg) do if arg == '-T' or arg == '--cov' then require('luacov') end end

--- The Textadept release version string.
_RELEASE = 'Textadept 12.6'
--- Textadept's copyright information.
_COPYRIGHT = 'Copyright © 2007-2025 Mitchell. See LICENSE.\n' ..
	'https://orbitalquark.github.io/textadept'

package.path = string.format('%s/core/?.lua;%s', _HOME, package.path)

require('assert')
_SCINTILLA = require('iface')
events = require('events')
args = require('args')
_L = require('locale')
require('file_io')
lexer = require('lexer')
require('lfs_ext')
require('ui')
keys = require('keys')

--- Replacement for original `buffer:text_range()`, which has a C struct for an argument.
-- Documentation is in core/.buffer.luadoc.
local function text_range(buffer, start_pos, end_pos)
	local target_start, target_end = buffer.target_start, buffer.target_end
	buffer:set_target_range(math.max(1, assert_type(start_pos, 'number', 2)),
		math.min(assert_type(end_pos, 'number', 3), buffer.length + 1))
	local text = buffer.target_text
	buffer:set_target_range(target_start, target_end) -- restore
	return text
end

events.connect(events.BUFFER_NEW, function() buffer.text_range = text_range end, 1)

-- Implement `events.BUFFER_{BEFORE,AFTER}_REPLACE_TEXT` as a convenience in lieu of the
-- undocumented `events.MODIFIED`.
local DELETE, INSERT, UNDOREDO = _SCINTILLA.MOD_BEFOREDELETE, _SCINTILLA.MOD_INSERTTEXT,
	_SCINTILLA.MULTILINEUNDOREDO
--- Helper function for emitting `events.BUFFER_AFTER_REPLACE_TEXT` after a full-buffer undo/redo
-- operation, e.g. after reloading buffer contents and then performing an undo.
local function emit_after_replace_text()
	events.disconnect(events.UPDATE_UI, emit_after_replace_text)
	events.emit(events.BUFFER_AFTER_REPLACE_TEXT)
end
-- Emits events prior to and after replacing buffer text.
events.connect(events.MODIFIED, function(position, mod, text, length)
	if mod & (DELETE | INSERT) == 0 or length ~= buffer.length then return end
	if mod & (INSERT | UNDOREDO) == INSERT | UNDOREDO then
		-- Cannot emit BUFFER_AFTER_REPLACE_TEXT here because Scintilla will do things like update
		-- the selection afterwards, which could undo what event handlers do.
		events.connect(events.UPDATE_UI, emit_after_replace_text)
		return
	end
	events.emit(mod & DELETE > 0 and events.BUFFER_BEFORE_REPLACE_TEXT or
		events.BUFFER_AFTER_REPLACE_TEXT)
end)

--- A table of style properties that can be concatenated with other tables of properties.
local style_object = {}
style_object.__index = style_object

--- Creates a new style object.
-- @param props Table of style properties to use.
local function style_obj(props)
	local style = {}
	for k, v in pairs(props) do style[k] = v end
	return setmetatable(style, style_object)
end

--- Returns a new style object with a set of merged properties.
-- @param props Table of style properties to merge into this one.
-- @local
function style_object:__concat(props)
	local style = style_obj(self) -- copy
	for k, v in pairs(assert_type(props, 'table', 2)) do style[k] = v end
	return style
end

--- Applies a style's settings to a view.
-- @param view View to apply style settings to.
-- @param style_num Style number to set the style for.
local function set_style(view, style_num)
	local styles = buffer ~= ui.command_entry and view.styles or _G.view.styles
	local style = styles[style_num] or styles[buffer:name_of_style(style_num):gsub('%.', '_')]
	if style then for k, v in pairs(style) do view['style_' .. k][style_num] = v end end
end

-- Documentation is in core/.buffer.luadoc.
local function set_styles(view)
	if buffer == ui.command_entry then view = ui.command_entry end
	view:style_reset_default()
	set_style(view, view.STYLE_DEFAULT)
	view:style_clear_all()
	local num_styles, num_predefined = buffer.named_styles, 8 -- DEFAULT to FOLDDISPLAYTEXT
	for i = 1, math.max(num_styles - num_predefined, view.STYLE_DEFAULT - 1) do set_style(view, i) end
	for i = view.STYLE_DEFAULT + 1, view.STYLE_FOLDDISPLAYTEXT do set_style(view, i) end
	for i = view.STYLE_FOLDDISPLAYTEXT + 1, num_styles do set_style(view, i) end
end

-- Documentation is in core/.buffer.luadoc.
local function set_theme(view, name, env)
	if not name or type(name) == 'table' then name, env = _THEME, name end
	if not assert_type(name, 'string', 2):find('[/\\]') then
		name = package.searchpath(name,
			string.format('%s/themes/?.lua;%s/themes/?.lua', _USERHOME, _HOME))
	end
	if not name or not lfs.attributes(name) then return end
	if not assert_type(env, 'table/nil', 3) then env = {} end
	env.view = view
	for name in pairs(view.styles) do view.styles[name] = nil end -- reset
	assert(loadfile(name, 't', setmetatable(env, {__index = _G})))()
	view:set_styles()
end

--- Metatable for `view.styles`, whose documentation is in core/.buffer.luadoc.
local styles_mt = {
	__index = function(t, k) return type(k) == 'string' and t[k:match('^(.+)[_%.]')] or rawget(t, k) end,
	__newindex = function(t, k, v)
		rawset(t, type(k) == 'string' and k:gsub('%.', '_') or k, style_obj(assert_type(v, 'table', 3)))
	end
}

events.connect(events.VIEW_NEW, function()
	local view = buffer ~= ui.command_entry and view or ui.command_entry
	view.colors, view.styles = {}, setmetatable({}, styles_mt)
	view.set_styles, view.set_theme = set_styles, set_theme
end, 1)

--- The path to Textadept's home, or installation, directory.
-- @field _HOME

--- The filesystem's character encoding.
-- This really only matters on Windows, where there is a mismatch between the UI encoding
-- (UTF-8), and the filesystem encoding (non-UTF-8).
-- @usage local utf8_filename = buffer.filename:iconv('UTF-8', _CHARSET)
-- @usage local f = io.open(utf8_filename:iconv(_CHARSET, 'UTF-8'))
-- @see string.iconv
-- @field _CHARSET

--- Whether or not Textadept is running on Windows.
-- @field WIN32

--- Whether or not Textadept is running on macOS.
-- @field OSX

--- Whether or not Textadept is running on Linux.
-- @field LINUX

--- Whether or not Textadept is running on BSD.
-- @field BSD

--- Whether or not Textadept is running as a GTK GUI application.
-- @field GTK

--- Whether or not Textadept is running as a Qt GUI application.
-- @field QT

--- Whether or not Textadept is running in a terminal.
-- @field CURSES

--- Textadept's current UI mode, either "light" or "dark".
-- Manually changing this field has no effect. It is used internally to set a theme on startup
-- based on the current OS theme.
-- @see view.set_theme
-- @see events.MODE_CHANGED
-- @field _THEME

-- The tables below were defined in C.

--- Table of command line parameters passed to Textadept, just like in Lua.
-- @see args
-- @table arg

--- Table of all open buffers in Textadept.
-- Numeric keys have buffer values and buffer keys have their associated numeric keys as values.
-- @usage local buffer = _BUFFERS[n] -- buffer at index n
-- @usage local i = _BUFFERS[buffer] -- index of buffer in _BUFFERS
-- @see buffer
-- @table _BUFFERS

--- Table of all views in Textadept.
-- Numeric keys have view values and view keys have their associated numeric keys as values.
-- @usage local view = _VIEWS[n] -- view at index n
-- @usage local i = _VIEWS[view] -- index of view in _VIEWS
-- @see view
-- @table _VIEWS

--- The current [buffer](#the-buffer-module) in the [current view](#_G.view).
-- @table buffer

--- The current [view](#the-view-module).
-- @table view

-- The functions below are Lua C functions.

--- Moves buffers within the `_BUFFERS` table, changing their display order in the tab bar and
-- buffer browser.
-- @param from Index of the buffer to move.
-- @param to Index to move the buffer to.
-- @function move_buffer

--- Attempts to quit Textadept.
-- @param[opt=0] status Status code for Textadept to exit with.
-- @param[optchain=true] events Emit `events.QUIT`, which could prevent quitting. Passing
--	`false` could result in data loss.
-- @function quit

--- Resets Textadept's Lua State by reloading all initialization scripts.
-- This allows for testing theme and user script modifications (e.g. *~/.textadept/init.lua*)
-- without having to restart Textadept.
--
-- `arg` is `nil` during re-initialization. Scripts that need to differentiate between startup
-- and reset can test `arg`.
-- @see events.RESET_BEFORE
-- @see events.RESET_AFTER
-- @function reset

--- Calls a function after a timeout interval.
-- Terminal version note: timeout functions will not be called until an active Find & Replace
-- pane session finishes, or until an active dialog closes.
-- @param interval Interval in seconds to call *f* after.
-- @param f Function to call. If it returns `true`, it will be called again after *interval*
--	seconds.
-- @param[opt] ... Additional arguments to pass to *f*.
-- @function timeout
