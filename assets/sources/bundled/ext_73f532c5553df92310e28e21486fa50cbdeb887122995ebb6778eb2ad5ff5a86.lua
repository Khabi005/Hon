-- Bundled from https://gitlab.com/shosetsuorg/extensions/-/raw/dev/; original sources retained in third_party/shosetsu.
local __modules, __loaded, __loading = {}, {}, {}
local __builtin = Require
local function Require(name)
  if __loaded[name] ~= nil then return __loaded[name] end
  if not __modules[name] then return __builtin(name) end
  if __loading[name] then error("Circular library dependency: " .. name) end
  __loading[name] = true
  local value = __modules[name]()
  if value == nil then value = true end
  __loaded[name], __loading[name] = value, nil
  return value
end
__modules["dkjson"] = function()
-- {"ver":"1.0.1","author":"David Kolf"}

-- Module options:
local always_try_using_lpeg = false

--[==[

David Kolf's JSON module for Lua 5.1/5.2

Version 2.5


For the documentation see the corresponding readme.txt or visit
<http://dkolf.de/src/dkjson-lua.fsl/>.

You can contact the author by sending an e-mail to 'david' at the
domain 'dkolf.de'.


Copyright (C) 2010-2013 David Heiko Kolf

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]==]

-- global dependencies:
local pairs, type, tostring, tonumber, getmetatable, setmetatable = pairs, type, tostring, tonumber, getmetatable, setmetatable
local error, require, pcall, select = error, require, pcall, select
local floor, huge = math.floor, math.huge
local strrep, gsub, strsub, strbyte, strchar, strfind, strlen, strformat = string.rep, string.gsub, string.sub, string.byte, string.char,
string.find, string.len, string.format
local strmatch = string.match
local concat = table.concat

local json = { version = "dkjson 2.5" }

pcall(function()
	-- Enable access to blocked metatables.
	-- Don't worry, this module doesn't change anything in them.
	local debmeta = require "debug".getmetatable
	if debmeta then
		getmetatable = debmeta
	end
end)

json.null = setmetatable({}, {
	__tojson = function()
		return "null"
	end
})

local function isarray (tbl)
	local max, n, arraylen = 0, 0, 0
	for k, v in pairs(tbl) do
		if k == 'n' and type(v) == 'number' then
			arraylen = v
			if v > max then
				max = v
			end
		else
			if type(k) ~= 'number' or k < 1 or floor(k) ~= k then
				return false
			end
			if k > max then
				max = k
			end
			n = n + 1
		end
	end
	if max > 10 and max > arraylen and max > n * 2 then
		return false -- don't create an array with too many holes
	end
	return true, max
end

local escapecodes = {
	["\""] = "\\\"",["\\"] = "\\\\",["\b"] = "\\b",["\f"] = "\\f",
	["\n"] = "\\n",["\r"] = "\\r",["\t"] = "\\t"
}

local function escapeutf8 (uchar)
	local value = escapecodes[uchar]
	if value then
		return value
	end
	local a, b, c, d = strbyte(uchar, 1, 4)
	a, b, c, d = a or 0, b or 0, c or 0, d or 0
	if a <= 0x7f then
		value = a
	elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
		value = (a - 0xc0) * 0x40 + b - 0x80
	elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
		value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
	elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
		value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
	else
		return ""
	end
	if value <= 0xffff then
		return strformat("\\u%.4x", value)
	elseif value <= 0x10ffff then
		-- encode as UTF-16 surrogate pair
		value = value - 0x10000
		local highsur, lowsur = 0xD800 + floor(value / 0x400), 0xDC00 + (value % 0x400)
		return strformat("\\u%.4x\\u%.4x", highsur, lowsur)
	else
		return ""
	end
end

local function fsub (str, pattern, repl)
	-- gsub always builds a new string in a buffer, even when no match
	-- exists. First using find should be more efficient when most strings
	-- don't contain the pattern.
	if strfind(str, pattern) then
		return gsub(str, pattern, repl)
	else
		return str
	end
end

local function quotestring (value)
	-- based on the regexp "escapable" in https://github.com/douglascrockford/JSON-js
	value = fsub(value, "[%z\1-\31\"\\\127]", escapeutf8)
	if strfind(value, "[\194\216\220\225\226\239]") then
		value = fsub(value, "\194[\128-\159\173]", escapeutf8)
		value = fsub(value, "\216[\128-\132]", escapeutf8)
		value = fsub(value, "\220\143", escapeutf8)
		value = fsub(value, "\225\158[\180\181]", escapeutf8)
		value = fsub(value, "\226\128[\140-\143\168-\175]", escapeutf8)
		value = fsub(value, "\226\129[\160-\175]", escapeutf8)
		value = fsub(value, "\239\187\191", escapeutf8)
		value = fsub(value, "\239\191[\176-\191]", escapeutf8)
	end
	return "\"" .. value .. "\""
end
json.quotestring = quotestring

local function replace(str, o, n)
	local i, j = strfind(str, o, 1, true)
	if i then
		return strsub(str, 1, i - 1) .. n .. strsub(str, j + 1, -1)
	else
		return str
	end
end

-- locale independent num2str and str2num functions
local decpoint, numfilter

local function updatedecpoint ()
	decpoint = strmatch(tostring(0.5), "([^05+])")
	-- build a filter that can be used to remove group separators
	numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

local function num2str (num)
	return replace(fsub(tostring(num), numfilter, ""), decpoint, ".")
end

local function str2num (str)
	local num = tonumber(replace(str, ".", decpoint))
	if not num then
		updatedecpoint()
		num = tonumber(replace(str, ".", decpoint))
	end
	return num
end

local function addnewline2 (level, buffer, buflen)
	buffer[buflen + 1] = "\n"
	buffer[buflen + 2] = strrep("  ", level)
	buflen = buflen + 2
	return buflen
end

function json.addnewline (state)
	if state.indent then
		state.bufferlen = addnewline2(state.level or 0,
				state.buffer, state.bufferlen or #(state.buffer))
	end
end

local encode2 -- forward declaration

local function addpair (key, value, prev, indent, level, buffer, buflen, tables, globalorder, state)
	local kt = type(key)
	if kt ~= 'string' and kt ~= 'number' then
		return nil, "type '" .. kt .. "' is not supported as a key by JSON."
	end
	if prev then
		buflen = buflen + 1
		buffer[buflen] = ","
	end
	if indent then
		buflen = addnewline2(level, buffer, buflen)
	end
	buffer[buflen + 1] = quotestring(key)
	buffer[buflen + 2] = ":"
	return encode2(value, indent, level, buffer, buflen + 2, tables, globalorder, state)
end

local function appendcustom(res, buffer, state)
	local buflen = state.bufferlen
	if type(res) == 'string' then
		buflen = buflen + 1
		buffer[buflen] = res
	end
	return buflen
end

local function exception(reason, value, state, buffer, buflen, defaultmessage)
	defaultmessage = defaultmessage or reason
	local handler = state.exception
	if not handler then
		return nil, defaultmessage
	else
		state.bufferlen = buflen
		local ret, msg = handler(reason, value, state, defaultmessage)
		if not ret then
			return nil, msg or defaultmessage
		end
		return appendcustom(ret, buffer, state)
	end
end

function json.encodeexception(reason, value, state, defaultmessage)
	return quotestring("<" .. defaultmessage .. ">")
end

encode2 = function(value, indent, level, buffer, buflen, tables, globalorder, state)
	local valtype = type(value)
	local valmeta = getmetatable(value)
	valmeta = type(valmeta) == 'table' and valmeta -- only tables
	local valtojson = valmeta and valmeta.__tojson
	if valtojson then
		if tables[value] then
			return exception('reference cycle', value, state, buffer, buflen)
		end
		tables[value] = true
		state.bufferlen = buflen
		local ret, msg = valtojson(value, state)
		if not ret then
			return exception('custom encoder failed', value, state, buffer, buflen, msg)
		end
		tables[value] = nil
		buflen = appendcustom(ret, buffer, state)
	elseif value == nil then
		buflen = buflen + 1
		buffer[buflen] = "null"
	elseif valtype == 'number' then
		local s
		if value ~= value or value >= huge or -value >= huge then
			-- This is the behaviour of the original JSON implementation.
			s = "null"
		else
			s = num2str(value)
		end
		buflen = buflen + 1
		buffer[buflen] = s
	elseif valtype == 'boolean' then
		buflen = buflen + 1
		buffer[buflen] = value and "true" or "false"
	elseif valtype == 'string' then
		buflen = buflen + 1
		buffer[buflen] = quotestring(value)
	elseif valtype == 'table' then
		if tables[value] then
			return exception('reference cycle', value, state, buffer, buflen)
		end
		tables[value] = true
		level = level + 1
		local isa, n = isarray(value)
		if n == 0 and valmeta and valmeta.__jsontype == 'object' then
			isa = false
		end
		local msg
		if isa then
			-- JSON array
			buflen = buflen + 1
			buffer[buflen] = "["
			for i = 1, n do
				buflen, msg = encode2(value[i], indent, level, buffer, buflen, tables, globalorder, state)
				if not buflen then
					return nil, msg
				end
				if i < n then
					buflen = buflen + 1
					buffer[buflen] = ","
				end
			end
			buflen = buflen + 1
			buffer[buflen] = "]"
		else
			-- JSON object
			local prev = false
			buflen = buflen + 1
			buffer[buflen] = "{"
			local order = valmeta and valmeta.__jsonorder or globalorder
			if order then
				local used = {}
				n = #order
				for i = 1, n do
					local k = order[i]
					local v = value[k]
					if v then
						used[k] = true
						buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
						prev = true -- add a seperator before the next element
					end
				end
				for k, v in pairs(value) do
					if not used[k] then
						buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
						if not buflen then
							return nil, msg
						end
						prev = true -- add a seperator before the next element
					end
				end
			else
				-- unordered
				for k, v in pairs(value) do
					buflen, msg = addpair(k, v, prev, indent, level, buffer, buflen, tables, globalorder, state)
					if not buflen then
						return nil, msg
					end
					prev = true -- add a seperator before the next element
				end
			end
			if indent then
				buflen = addnewline2(level - 1, buffer, buflen)
			end
			buflen = buflen + 1
			buffer[buflen] = "}"
		end
		tables[value] = nil
	else
		return exception('unsupported type', value, state, buffer, buflen,
				"type '" .. valtype .. "' is not supported by JSON.")
	end
	return buflen
end

function json.encode (value, state)
	state = state or {}
	local oldbuffer = state.buffer
	local buffer = oldbuffer or {}
	state.buffer = buffer
	updatedecpoint()
	local ret, msg = encode2(value, state.indent, state.level or 0,
			buffer, state.bufferlen or 0, state.tables or {}, state.keyorder, state)
	if not ret then
		error(msg, 2)
	elseif oldbuffer == buffer then
		state.bufferlen = ret
		return true
	else
		state.bufferlen = nil
		state.buffer = nil
		return concat(buffer)
	end
end

local function loc (str, where)
	local line, pos, linepos = 1, 1, 0
	while true do
		pos = strfind(str, "\n", pos, true)
		if pos and pos < where then
			line = line + 1
			linepos = pos
			pos = pos + 1
		else
			break
		end
	end
	return "line " .. line .. ", column " .. (where - linepos)
end

local function unterminated (str, what, where)
	return nil, strlen(str) + 1, "unterminated " .. what .. " at " .. loc(str, where)
end

local function scanwhite (str, pos)
	while true do
		pos = strfind(str, "%S", pos)
		if not pos then
			return nil
		end
		local sub2 = strsub(str, pos, pos + 1)
		if sub2 == "\239\187" and strsub(str, pos + 2, pos + 2) == "\191" then
			-- UTF-8 Byte Order Mark
			pos = pos + 3
		elseif sub2 == "//" then
			pos = strfind(str, "[\n\r]", pos + 2)
			if not pos then
				return nil
			end
		elseif sub2 == "/*" then
			pos = strfind(str, "*/", pos + 2)
			if not pos then
				return nil
			end
			pos = pos + 2
		else
			return pos
		end
	end
end

local escapechars = {
	["\""] = "\"",["\\"] = "\\",["/"] = "/",["b"] = "\b",["f"] = "\f",
	["n"] = "\n",["r"] = "\r",["t"] = "\t"
}

local function unichar (value)
	if value < 0 then
		return nil
	elseif value <= 0x007f then
		return strchar(value)
	elseif value <= 0x07ff then
		return strchar(0xc0 + floor(value / 0x40),
				0x80 + (floor(value) % 0x40))
	elseif value <= 0xffff then
		return strchar(0xe0 + floor(value / 0x1000),
				0x80 + (floor(value / 0x40) % 0x40),
				0x80 + (floor(value) % 0x40))
	elseif value <= 0x10ffff then
		return strchar(0xf0 + floor(value / 0x40000),
				0x80 + (floor(value / 0x1000) % 0x40),
				0x80 + (floor(value / 0x40) % 0x40),
				0x80 + (floor(value) % 0x40))
	else
		return nil
	end
end

local function scanstring (str, pos)
	local lastpos = pos + 1
	local buffer, n = {}, 0
	while true do
		local nextpos = strfind(str, "[\"\\]", lastpos)
		if not nextpos then
			return unterminated(str, "string", pos)
		end
		if nextpos > lastpos then
			n = n + 1
			buffer[n] = strsub(str, lastpos, nextpos - 1)
		end
		if strsub(str, nextpos, nextpos) == "\"" then
			lastpos = nextpos + 1
			break
		else
			local escchar = strsub(str, nextpos + 1, nextpos + 1)
			local value
			if escchar == "u" then
				value = tonumber(strsub(str, nextpos + 2, nextpos + 5), 16)
				if value then
					local value2
					if 0xD800 <= value and value <= 0xDBff then
						-- we have the high surrogate of UTF-16. Check if there is a
						-- low surrogate escaped nearby to combine them.
						if strsub(str, nextpos + 6, nextpos + 7) == "\\u" then
							value2 = tonumber(strsub(str, nextpos + 8, nextpos + 11), 16)
							if value2 and 0xDC00 <= value2 and value2 <= 0xDFFF then
								value = (value - 0xD800) * 0x400 + (value2 - 0xDC00) + 0x10000
							else
								value2 = nil -- in case it was out of range for a low surrogate
							end
						end
					end
					value = value and unichar(value)
					if value then
						if value2 then
							lastpos = nextpos + 12
						else
							lastpos = nextpos + 6
						end
					end
				end
			end
			if not value then
				value = escapechars[escchar] or escchar
				lastpos = nextpos + 2
			end
			n = n + 1
			buffer[n] = value
		end
	end
	if n == 1 then
		return buffer[1], lastpos
	elseif n > 1 then
		return concat(buffer), lastpos
	else
		return "", lastpos
	end
end

local scanvalue -- forward declaration

local function scantable (what, closechar, str, startpos, nullval, objectmeta, arraymeta)
	local tbl, n = {}, 0
	local pos = startpos + 1
	if what == 'object' then
		setmetatable(tbl, objectmeta)
	else
		setmetatable(tbl, arraymeta)
	end
	while true do
		pos = scanwhite(str, pos)
		if not pos then
			return unterminated(str, what, startpos)
		end
		local char = strsub(str, pos, pos)
		if char == closechar then
			return tbl, pos + 1
		end
		local val1, err
		val1, pos, err = scanvalue(str, pos, nullval, objectmeta, arraymeta)
		if err then
			return nil, pos, err
		end
		pos = scanwhite(str, pos)
		if not pos then
			return unterminated(str, what, startpos)
		end
		char = strsub(str, pos, pos)
		if char == ":" then
			if val1 == nil then
				return nil, pos, "cannot use nil as table index (at " .. loc(str, pos) .. ")"
			end
			pos = scanwhite(str, pos + 1)
			if not pos then
				return unterminated(str, what, startpos)
			end
			local val2
			val2, pos, err = scanvalue(str, pos, nullval, objectmeta, arraymeta)
			if err then
				return nil, pos, err
			end
			tbl[val1] = val2
			pos = scanwhite(str, pos)
			if not pos then
				return unterminated(str, what, startpos)
			end
			char = strsub(str, pos, pos)
		else
			n = n + 1
			tbl[n] = val1
		end
		if char == "," then
			pos = pos + 1
		end
	end
end

scanvalue = function(str, pos, nullval, objectmeta, arraymeta)
	pos = pos or 1
	pos = scanwhite(str, pos)
	if not pos then
		return nil, strlen(str) + 1, "no valid JSON value (reached the end)"
	end
	local char = strsub(str, pos, pos)
	if char == "{" then
		return scantable('object', "}", str, pos, nullval, objectmeta, arraymeta)
	elseif char == "[" then
		return scantable('array', "]", str, pos, nullval, objectmeta, arraymeta)
	elseif char == "\"" then
		return scanstring(str, pos)
	else
		local pstart, pend = strfind(str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
		if pstart then
			local number = str2num(strsub(str, pstart, pend))
			if number then
				return number, pend + 1
			end
		end
		pstart, pend = strfind(str, "^%a%w*", pos)
		if pstart then
			local name = strsub(str, pstart, pend)
			if name == "true" then
				return true, pend + 1
			elseif name == "false" then
				return false, pend + 1
			elseif name == "null" then
				return nullval, pend + 1
			end
		end
		return nil, pos, "no valid JSON value at " .. loc(str, pos)
	end
end

local function optionalmetatables(...)
	if select("#", ...) > 0 then
		return ...
	else
		return { __jsontype = 'object' }, { __jsontype = 'array' }
	end
end

function json.decode (str, pos, nullval, ...)
	local objectmeta, arraymeta = optionalmetatables(...)
	return scanvalue(str, pos, nullval, objectmeta, arraymeta)
end

function json.use_lpeg ()
	local g = require("lpeg")

	if g.version() == "0.11" then
		error "due to a bug in LPeg 0.11, it cannot be used for JSON matching"
	end

	local pegmatch = g.match
	local P, S, R = g.P, g.S, g.R

	local function ErrorCall (str, pos, msg, state)
		if not state.msg then
			state.msg = msg .. " at " .. loc(str, pos)
			state.pos = pos
		end
		return false
	end

	local function Err (msg)
		return g.Cmt(g.Cc(msg) * g.Carg(2), ErrorCall)
	end

	local SingleLineComment = P "//" * (1 - S "\n\r") ^ 0
	local MultiLineComment = P "/*" * (1 - P "*/") ^ 0 * P "*/"
	local Space = (S " \n\r\t" + P "\239\187\191" + SingleLineComment + MultiLineComment) ^ 0

	local PlainChar = 1 - S "\"\\\n\r"
	local EscapeSequence = (P "\\" * g.C(S "\"\\/bfnrt" + Err "unsupported escape sequence")) / escapechars
	local HexDigit = R("09", "af", "AF")
	local function UTF16Surrogate (match, pos, high, low)
		high, low = tonumber(high, 16), tonumber(low, 16)
		if 0xD800 <= high and high <= 0xDBff and 0xDC00 <= low and low <= 0xDFFF then
			return true, unichar((high - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000)
		else
			return false
		end
	end
	local function UTF16BMP (hex)
		return unichar(tonumber(hex, 16))
	end
	local U16Sequence = (P "\\u" * g.C(HexDigit * HexDigit * HexDigit * HexDigit))
	local UnicodeEscape = g.Cmt(U16Sequence * U16Sequence, UTF16Surrogate) + U16Sequence / UTF16BMP
	local Char = UnicodeEscape + EscapeSequence + PlainChar
	local String = P "\"" * g.Cs(Char ^ 0) * (P "\"" + Err "unterminated string")
	local Integer = P "-" ^ (-1) * (P "0" + (R "19" * R "09" ^ 0))
	local Fractal = P "." * R "09" ^ 0
	local Exponent = (S "eE") * (S "+-") ^ (-1) * R "09" ^ 1
	local Number = (Integer * Fractal ^ (-1) * Exponent ^ (-1)) / str2num
	local Constant = P "true" * g.Cc(true) + P "false" * g.Cc(false) + P "null" * g.Carg(1)
	local SimpleValue = Number + String + Constant
	local ArrayContent, ObjectContent

	-- The functions parsearray and parseobject parse only a single value/pair
	-- at a time and store them directly to avoid hitting the LPeg limits.
	local function parsearray (str, pos, nullval, state)
		local obj, cont
		local npos
		local t, nt = {}, 0
		repeat
			obj, cont, npos = pegmatch(ArrayContent, str, pos, nullval, state)
			if not npos then
				break
			end
			pos = npos
			nt = nt + 1
			t[nt] = obj
		until cont == 'last'
		return pos, setmetatable(t, state.arraymeta)
	end

	local function parseobject (str, pos, nullval, state)
		local obj, key, cont
		local npos
		local t = {}
		repeat
			key, obj, cont, npos = pegmatch(ObjectContent, str, pos, nullval, state)
			if not npos then
				break
			end
			pos = npos
			t[key] = obj
		until cont == 'last'
		return pos, setmetatable(t, state.objectmeta)
	end

	local Array = P "[" * g.Cmt(g.Carg(1) * g.Carg(2), parsearray) * Space * (P "]" + Err "']' expected")
	local Object = P "{" * g.Cmt(g.Carg(1) * g.Carg(2), parseobject) * Space * (P "}" + Err "'}' expected")
	local Value = Space * (Array + Object + SimpleValue)
	local ExpectedValue = Value + Space * Err "value expected"
	ArrayContent = Value * Space * (P "," * g.Cc 'cont' + g.Cc 'last') * g.Cp()
	local Pair = g.Cg(Space * String * Space * (P ":" + Err "colon expected") * ExpectedValue)
	ObjectContent = Pair * Space * (P "," * g.Cc 'cont' + g.Cc 'last') * g.Cp()
	local DecodeValue = ExpectedValue * g.Cp()

	function json.decode (str, pos, nullval, ...)
		local state = {}
		state.objectmeta, state.arraymeta = optionalmetatables(...)
		local obj, retpos = pegmatch(DecodeValue, str, pos, nullval, state)
		if state.msg then
			return nil, state.pos, state.msg
		else
			return obj, retpos
		end
	end

	-- use this function only once:
	json.use_lpeg = function()
		return json
	end

	json.using_lpeg = true

	return json -- so you can get the module using json = require "dkjson".use_lpeg()
end

if always_try_using_lpeg then
	pcall(json.use_lpeg)
end


-- START -- SHOSETSU ADDITIONS --
local json_mediatype = MediaType("application/json; charset=utf-8")

function json.GET(url, ...)
	local res = Request(GET(url, ...))
	if res:headers():get("Content-Type"):sub(1, 16) == "application/json" then
		return json.decode(res:body():string())
	end
	return res:body():string()
end

function json.POST(url, body, ...)
	local headers, cctl = ...
	if type(body) == "table" then
		body = json.encode(body)
	end
	if type(body) ~= "string" then
		error("Invalid json.POST()")
	end
	body = RequestBody(body, json_mediatype)
	local res = Request(POST(url, headers, body, cctl))
	if res:headers():get("Content-Type"):sub(1, 16) == "application/json" then
		return json.decode(res:body():string())
	end
	return res:body():string()
end
--  END  -- SHOSETSU ADDITIONS --

return json

end
__modules["url"] = function()
-- {"ver":"1.0.0","author":"TechnoJo4"}

local gsub, format, byte, char = string.gsub, string.format, string.byte, string.char

---@return string
---@param str string
local function urlDecode(str)
	if str == nil or str == "" then
		return ""
	end
	str = gsub(str, '+', ' ')
	str = gsub(str, '%%(%x%x)', function(h)
		return char(tonumber(h, 16))
	end)
	str = gsub(str, '\r\n', '\n')
	return str
end

local encode_tbl = {["_"] = true, ["-"] = true, ["~"] = true, ["."] = true}
for b=byte('a'),byte('z') do encode_tbl[char(b)] = true end
for b=byte('A'),byte('Z') do encode_tbl[char(b)] = true end
for b=byte('0'),byte('9') do encode_tbl[char(b)] = true end

---@return string
---@param str string
local function urlEncode(str)
	if str == nil or str == "" then
		return ""
	end
	if str then
		str = gsub(str, '\n', '\r\n')
		str = gsub(str, '(.)', function(c)
			if encode_tbl[c] then
				return c
			else
				return format('%%%02X', byte(c))
			end
		end)
	end
	return str
end

--- Makes a query string from a table.
---@return string
---@param tbl table<string, any|any[]>
---@param url string | nil
local function querystring(tbl, url)
	local fields = {}
	for key, value in pairs(tbl) do
		local keyString = urlEncode(tostring(key)) .. "="
		if type(value) == "table" then
			for _, v in ipairs(value) do
				table.insert(fields, keyString .. urlEncode(tostring(v)))
			end
		else
			table.insert(fields, keyString .. urlEncode(tostring(value)))
		end
	end
	return (url and url .. "?" or "") .. table.concat(fields, "&")
end

return {
	decode = urlDecode,
	encode = urlEncode,
	querystring = querystring,
}
end
return (function()
-- {"id":95556,"ver":"1.0.7","libVer":"1.0.0","author":"Confident-hate"}
local json = Require("dkjson")
local baseURL = "https://www.wattpad.com"

---@param v Element
local text = function(v)
    return v:text()
end


---@param url string
---@param type int
local function shrinkURL(url)
    return url:gsub("https://www.wattpad.com", "")
end

---@param url string
---@param type int
local function expandURL(url)
    return baseURL .. url
end

local ORDER_BY_FILTER = 3
local ORDER_BY_VALUES = { "Hot", "New"}
local GENRE_FILTER = 2
local GENRE_VALUES = { 
  "Adventure",
  "Contemporarylit",
  "Diverselit",
  "Fanfiction",
  "Fantasy",
  "Historicalfiction",
  "Horror",
  "Humor",
  "Lgbt",
  "Mystery",
  "Newadult",
  "Nonfiction",
  "Paranormal",
  "Poetry",
  "Romance",
  "Sciencefiction",
  "Shortstory",
  "Teenfiction",
  "Thriller",
  "Werewolf"
}

local STATUS_FILTER_KEY = 4
local STATUS_VALUES = { "All", "Completed"}
local STATUS_PARAMS = {"", "&filter=complete"}

local searchFilters = {
    DropdownFilter(GENRE_FILTER, "Genre", GENRE_VALUES),
    DropdownFilter(ORDER_BY_FILTER, "Order by", ORDER_BY_VALUES),
    DropdownFilter(STATUS_FILTER_KEY, "Status (only works with search)", STATUS_VALUES)
}

local encode = Require("url").encode


--- @param chapterURL string @url of the chapter
--- @return string @of chapter
local function getPassage(chapterURL)
    local url = baseURL .. chapterURL
    local htmlElement = GETDocument(url)
    local title = htmlElement:selectFirst("header h1"):text()
    local chapterPages = string.match(htmlElement:html(), ".*pages.:([0-9]*).*")
    local ht = "<h1>" .. title .. "</h1>"
    for i = 1,chapterPages,1 do
        local pTagList = ""
        htmlElement = GETDocument(url .. "/page/" .. i)
        htmlElement = htmlElement:selectFirst(".row.part-content .panel.panel-reading")
        htmlElement:select("button"):remove()
        htmlElement:select("br"):remove()
        local toRemove = {}
        htmlElement:traverse(NodeVisitor(function(v)
            if v:tagName() == "p" and v:text() == "" then
                toRemove[#toRemove+1] = v
            end
        end, nil, true))
        for _,v in pairs(toRemove) do
            v:remove()
        end
        pTagList = map(htmlElement:select("p"), text)
        ht = ht .. "-----------------"
        for k,v in pairs(pTagList) do ht = ht .. "<br><br>" .. v end
        ht = ht .. "<br><br>-----------------"
    end
    return pageOfElem(Document(ht), true)
end

--- @param data table
local function search(data)
    local queryContent = data[QUERY]
    local page = data[PAGE] - 1
    local status = data[STATUS_FILTER_KEY]
    local statusValue = ""
    if status ~= nil then
        statusValue = STATUS_PARAMS[status+1]
    end
    local query = baseURL .. "/v4/search/stories?query=" .. queryContent .. statusValue .. "&free=1&fields=stories(title,cover,url),nexturl&limit=20&mature=true&offset=" .. page*20
    local response = RequestDocument(GET(query, nil, nil))
    response = json.decode(response:text())
    return map(response["stories"], function(v)
        return Novel {
            title = v.title,
            link = shrinkURL(v.url),
            imageURL = v.cover
        }
    end)
end

--- @param novelURL string @URL of novel
--- @return NovelInfo
local function parseNovel(novelURL)
    local url = baseURL .. novelURL
    local document = RequestDocument(
            RequestBuilder()
                    :get()
                    :url(url)
                    :addHeader("Referer", "https://www.wattpad.com/")
                    :build()
    )
    local description = ""
    local isPaid = document:selectFirst("[data-testid=block-part-icon]")
    local description = ""
    if isPaid ~= nil then 
        description = "!! 💰 Contains Paid Chapters !! \n" .. document:selectFirst(".glL-c"):text()
    else
        description = document:selectFirst(".glL-c"):text()
    end

    local status = NovelStatus.UNKNOWN
    if     document:selectFirst(".typography-label-small-semi"):text() == "Complete" then
        status = NovelStatus.COMPLETED
    elseif document:selectFirst(".typography-label-small-semi"):text() == "Ongoing" then
        status = NovelStatus.PUBLISHING
    end

    local novel = NovelInfo {
        title = document:selectFirst(".gF-N5"):text(),
        description = description,
        imageURL = document:select(".cover__BlyZa"):attr("src"),
        authors = { document:selectFirst(".af6dp"):text() },
        genres = map(document:select(".AMIOO a"), text ),
        status = status,
        chapters = AsList(
                map(document:select(".pPt69 .Y26Ib ul li"), function(v)
                    local title = v:selectFirst("a div div"):text()
                    if v:selectFirst("[data-testid=block-part-icon]") then
                        title = "🔒 ".. title
                    end
                    return NovelChapter {
                        order = v,
                        title = title,
                        link = shrinkURL(v:selectFirst("a"):attr("href"))
                    }
                end)
        )
    }
    return novel
end

local function parseListing(listingURL)
    local response = RequestDocument(
            RequestBuilder()
                    :get()
                    :url(listingURL)
                    :addHeader("Authorization", "IwKhVmNM7VXhnsVb0BabhS")
                    :build()
    )
    response = json.decode(response:text())
    return map(response["stories"], function(v)
        return Novel {
            title = v.title,
            link = shrinkURL(v.url),
            imageURL = v.cover
        }
    end)
end


local function getListing(data)
    local genre = data[GENRE_FILTER]
    local orderBy = data[ORDER_BY_FILTER]
    local page = data[PAGE] - 1
    local genreValue = ""
    local orderByValue = ""
    if genre ~= nil then
        genreValue = GENRE_VALUES[genre+1]:lower()
    end
    if orderBy ~= nil then
        orderByValue = ORDER_BY_VALUES[orderBy + 1]:lower()
    end
    local url = ""
    if orderByValue == "hot" then
        url = "https://api.wattpad.com/v5/hotlist?tags=" .. genreValue .. "&language=1&limit=20&offset=" .. page*20
    else
        url = "https://www.wattpad.com/v4/stories?fields=stories%28id%2Cuser%28name%2Cavatar%2Cfullname%29%2Ctitle%2Ccover%2Cdescription%2Cmature%2Ccompleted%2CvoteCount%2CreadCount%2Ccategories%2Curl%2CnumParts%2Crankings%2CfirstPartId%2Ctags%2CisPaywalled%29%2CnextUrl%2Ctotal&filter=new&language=1&mature=0&query=%23" .. genreValue .. "&limit=20&offset=" .. page*20
    end
    return parseListing(url)
end



return {
    id = 95556,
    name = "Wattpad",
    baseURL = baseURL,
    imageURL = "https://cdn-icons-png.flaticon.com/512/2111/2111715.png",
    hasSearch = true,
    listings = {
        Listing("Default", true, getListing)
    },

    parseNovel = parseNovel,
    getPassage = getPassage,
    chapterType = ChapterType.HTML,
    search = search,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
    searchFilters = searchFilters
}   
end)()