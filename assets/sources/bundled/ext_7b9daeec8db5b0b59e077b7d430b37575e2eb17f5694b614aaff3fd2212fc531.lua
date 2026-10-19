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
return (function()
-- {"id":701,"ver":"1.0.1","libVer":"1.0.0","author":"Rider21","dep":["dkjson>=1.0.1"]}

local baseURL = "https://renovels.org"

local json = Require("dkjson")

local ORDER_BY_FILTER = 3
local ORDER_BY_VALUES = { "Рейтинг", "Просмотры", "Лайкам", "Дате добавления", "Дате обновления", "Количество глав" }
local ORDER_BY_TERMS = { "rating", "views", "votes", "id", "chapter_date", "count_chapters" }

local function shrinkURL(url)
	return url:gsub(baseURL .. "/", "")
end

local function expandURL(url, key)
	if key == KEY_NOVEL_URL then
		return baseURL .. "/novel/" .. url
	end
	return baseURL .. "/" .. url
end

local function getSearch(data)
	local url = "api/search?query=" .. data[QUERY] .. "&count=30&field=titles&page=" .. data[PAGE]
	local response = json.GET(expandURL(url))
	return map(response["content"], function(v)
		return Novel {
			title = v.main_name or v.secondary_name,
			link = v.dir,
			imageURL = baseURL .. (v.img.high or v.img.mid or v.img.low)
		}
	end)
end

local function getPassage(chapterURL)
	local doc = json.GET(expandURL("api/titles/chapters" .. chapterURL))
	local chap = Document(doc.content.content)
	chap:child(0):before("<h1>" .. "Том " .. doc.content.tome .. " Глава " .. doc.content.chapter .. ": " .. doc.content.name .. "</h1>");

	return pageOfElem(chap)
end

local function parseNovel(novelURL, loadChapters)
	local response = json.GET(expandURL("api/titles/" .. novelURL))

	local novel = NovelInfo {
		title = response.content.main_name or response.content.secondary_name,
		genres = map(response.content.genres, function(v) return v.name end),
		tags = map(response.content.categories, function(v) return v.name or v.name end),
		imageURL = baseURL .. (response.content.img.high or response.content.img.mid or response.content.img.low),
		description = Document(response.content.description):text(),
		status = NovelStatus(
			response.content.status.name == "Закончен" and 1 or
			response.content.status.name == "Заморожен" and 2 or
			response.content.status.name == "Продолжается" and 0 or 3
		)
	}

	if loadChapters then
		local all = response.content.branches[1].count_chapters / 100
		local chapterList = {}
		for i = 0, all do
			local chapterJson = json.GET(expandURL("api/titles/chapters?branch_id=" .. response.content.branches[1].id .. "&count=100&page=" .. (i + 1)))
			for k, v in pairs(chapterJson.content) do
				if not v.is_paid or v.is_bought then
					table.insert(chapterList, NovelChapter {
						title = "Том " .. v.tome .. " Глава " .. v.chapter .. ": " .. v.name,
						link = "/" .. v.id .. "/",
						release = v.upload_date,
						order = response.content.branches[1].count_chapters - k - i * 100
					});
				end
			end
		end
		novel:setChapters(AsList(chapterList))
	end
	return novel
end

return {
	id = 701,
	name = "Renovels",
	baseURL = baseURL,
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/Renovels.png",
	chapterType = ChapterType.HTML,

	listings = {
		Listing("Novel List", true, function(data)
			local url = "api/search/catalog?count=30&ordering=-" .. ORDER_BY_TERMS[data[ORDER_BY_FILTER] + 1]

			for k, v in pairs(data) do
				if v then
					if (k > 10 and k < 17) then
						url = url .. "&types=" .. k - 10
					elseif (k > 20 and k < 26) then
						url = url .. "&status=" .. k - 20
					elseif (k > 30 and k < 33) then
						url = url .. "&age_limit=" .. k - 30
					elseif (k > 100 and k < 199) then
						url = url .. "&genres=" .. k - 10
					elseif (k > 200 and k < 901) then
						url = url .. "&categories=" .. k - 100
					end
				end
			end

			local response = json.GET(expandURL(url .. "&page=" .. data[PAGE]))
			return map(response["content"], function(v)
				return Novel {
					title = v.main_name or v.secondary_name,
					link = v.dir,
					imageURL = baseURL .. (v.img.high or v.img.mid or v.img.low)
				}
			end)
		end)
	},

	getPassage = getPassage,
	parseNovel = parseNovel,

	hasSearch = true,
	isSearchIncrementing = true,
	search = getSearch,
	searchFilters = {
		DropdownFilter(ORDER_BY_FILTER, "Сортировка", ORDER_BY_VALUES),
		FilterGroup("Жанры", { --offset: 10
			CheckboxFilter(122, "Боевик"), --ID: 112
			CheckboxFilter(133, "Война"), --ID: 123
			CheckboxFilter(124, "Детектив"), --ID: 114
			CheckboxFilter(135, "Драма"), --ID: 125
			CheckboxFilter(125, "Историческая проза"), --ID: 115
			CheckboxFilter(119, "ЛитРПГ"), --ID: 109
			CheckboxFilter(126, "Любовные романы"), --ID: 116
			CheckboxFilter(113, "Мистика"), --ID: 103
			CheckboxFilter(131, "Научная фантастика"), --ID: 121
			CheckboxFilter(138, "Повседневность"), --ID: 128
			CheckboxFilter(123, "Подростковая проза"), --ID: 113
			CheckboxFilter(129, "Политический роман"), --ID: 119
			CheckboxFilter(118, "Попаданцы"), --ID: 108
			CheckboxFilter(115, "Поэзия"), --ID: 105
			CheckboxFilter(121, "Разное"), --ID: 111
			CheckboxFilter(127, "РеалРПГ"), --ID: 117
			CheckboxFilter(136, "Романтика"), --ID: 126
			CheckboxFilter(112, "Современная проза"), --ID: 102
			CheckboxFilter(137, "Современная фантастика"), --ID: 127
			CheckboxFilter(132, "Спорт"), --ID: 122
			CheckboxFilter(139, "Трагедия"), --ID: 129
			CheckboxFilter(120, "Триллер"), --ID: 110
			CheckboxFilter(134, "Триллер и саспенс"), --ID: 124
			CheckboxFilter(116, "Ужасы"), --ID: 106
			CheckboxFilter(111, "Фантастика"), --ID: 101
			CheckboxFilter(117, "Фанфик"), --ID: 107
			CheckboxFilter(130, "Фьюжн роман"), --ID: 120
			CheckboxFilter(110, "Фэнтези"), --ID: 100
			CheckboxFilter(128, "Эротика"), --ID: 118
			CheckboxFilter(114, "Юмор"), --ID: 104
		}),
		FilterGroup("Теги", { --offset: 100
			CheckboxFilter(763, "Абьюзеры"), --ID: 663
			CheckboxFilter(536, "Авантюристы"), --ID: 436
			CheckboxFilter(693, "Автоматоны"), --ID: 593
			CheckboxFilter(602, "Агрессивные персонажи"), --ID: 502
			CheckboxFilter(669, "Ад"), --ID: 569
			CheckboxFilter(681, "Адаптация в радиопостановку"), --ID: 581
			CheckboxFilter(253, "Академия"), --ID: 153
			CheckboxFilter(727, "Актеры озвучки"), --ID: 627
			CheckboxFilter(351, "Активный главный герой"), --ID: 251
			CheckboxFilter(333, "Алхимия"), --ID: 233
			CheckboxFilter(247, "Альтернативная история"), --ID: 147
			CheckboxFilter(256, "Альтернативный мир"), --ID: 156
			CheckboxFilter(444, "Амнезия/Потеря памяти"), --ID: 344
			CheckboxFilter(785, "Анабиоз"), --ID: 685
			CheckboxFilter(283, "Ангелы"), --ID: 183
			CheckboxFilter(421, "Андрогинные персонажи"), --ID: 321
			CheckboxFilter(303, "Андроиды"), --ID: 203
			CheckboxFilter(633, "Анти-магия"), --ID: 533
			CheckboxFilter(532, "Антигерой"), --ID: 432
			CheckboxFilter(723, "Антикварный магазин"), --ID: 623
			CheckboxFilter(713, "Антисоциальный главный герой"), --ID: 613
			CheckboxFilter(242, "Антиутопия"), --ID: 142
			CheckboxFilter(257, "Апатичный протагонист"), --ID: 157
			CheckboxFilter(502, "Апокалипсис"), --ID: 402
			CheckboxFilter(475, "Аранжированный брак"), --ID: 375
			CheckboxFilter(739, "Армия"), --ID: 639
			CheckboxFilter(334, "Артефакты"), --ID: 234
			CheckboxFilter(623, "Артисты"), --ID: 523
			CheckboxFilter(730, "Банды"), --ID: 630
			CheckboxFilter(799, "БДСМ"), --ID: 699
			CheckboxFilter(498, "Бедный главный герой"), --ID: 398
			CheckboxFilter(361, "Безжалостный главный герой"), --ID: 261
			CheckboxFilter(538, "Беззаботный главный герой"), --ID: 438
			CheckboxFilter(779, "Безусловная любовь"), --ID: 679
			CheckboxFilter(350, "Беременность"), --ID: 250
			CheckboxFilter(425, "Бесполый главный герой"), --ID: 325
			CheckboxFilter(468, "Бессмертные"), --ID: 368
			CheckboxFilter(756, "Бесстрашный протагонист"), --ID: 656
			CheckboxFilter(452, "Бесстыдный главный герой"), --ID: 352
			CheckboxFilter(816, "Бесчестный главный герой"), --ID: 716
			CheckboxFilter(528, "Библиотека"), --ID: 428
			CheckboxFilter(221, "Бизнес-литература"), --ID: 121
			CheckboxFilter(869, "Бизнесмен"), --ID: 769
			CheckboxFilter(338, "Биочип"), --ID: 238
			CheckboxFilter(873, "Бисексуальный главный герой"), --ID: 773
			CheckboxFilter(363, "Близнецы"), --ID: 263
			CheckboxFilter(417, "Боги"), --ID: 317
			CheckboxFilter(539, "Богини"), --ID: 439
			CheckboxFilter(550, "Боевая академия"), --ID: 450
			CheckboxFilter(249, "Боевая фантастика"), --ID: 149
			CheckboxFilter(204, "Боевое фэнтези"), --ID: 104
			CheckboxFilter(533, "Боевые духи"), --ID: 433
			CheckboxFilter(593, "Боевые соревнования"), --ID: 493
			CheckboxFilter(521, "Божественная защита"), --ID: 421
			CheckboxFilter(427, "Божественные силы"), --ID: 327
			CheckboxFilter(699, "Борьба за власть"), --ID: 599
			CheckboxFilter(546, "Брак"), --ID: 446
			CheckboxFilter(288, "Брак по расчету"), --ID: 188
			CheckboxFilter(259, "Братский комплекс"), --ID: 159
			CheckboxFilter(587, "Братство"), --ID: 487
			CheckboxFilter(677, "Братья и сестры"), --ID: 577
			CheckboxFilter(845, "Буддизм"), --ID: 745
			CheckboxFilter(466, "Быстрая культивация"), --ID: 366
			CheckboxFilter(424, "Быстрообучаемый"), --ID: 324
			CheckboxFilter(792, "Валькирии"), --ID: 692
			CheckboxFilter(460, "Вампиры"), --ID: 360
			CheckboxFilter(802, "Ваншот"), --ID: 702
			CheckboxFilter(381, "Ведьмы"), --ID: 281
			CheckboxFilter(479, "Вежливый главный герой"), --ID: 379
			CheckboxFilter(428, "Верные подчиненные"), --ID: 328
			CheckboxFilter(395, "Взрослый главный герой"), --ID: 295
			CheckboxFilter(771, "Видит то, чего не видят другие"), --ID: 671
			CheckboxFilter(501, "Виртуальная реальность"), --ID: 401
			CheckboxFilter(781, "Владелец магазина"), --ID: 681
			CheckboxFilter(555, "Внезапная сила"), --ID: 455
			CheckboxFilter(865, "Внезапное богатство"), --ID: 765
			CheckboxFilter(519, "Внешний вид отличается от факт"), --ID: 419
			CheckboxFilter(843, "Военные Летописи"), --ID: 743
			CheckboxFilter(796, "Возвращение из другого мира"), --ID: 696
			CheckboxFilter(281, "Войны"), --ID: 181
			CheckboxFilter(801, "Вокалоид"), --ID: 701
			CheckboxFilter(639, "Волшебники/Волшебницы"), --ID: 539
			CheckboxFilter(408, "Волшебные звери"), --ID: 308
			CheckboxFilter(751, "Воображаемый друг"), --ID: 651
			CheckboxFilter(514, "Воры"), --ID: 414
			CheckboxFilter(299, "Воскрешение"), --ID: 199
			CheckboxFilter(598, "Враги становятся возлюбленными"), --ID: 498
			CheckboxFilter(662, "Враги становятся союзниками"), --ID: 562
			CheckboxFilter(709, "Врата в другой мир"), --ID: 609
			CheckboxFilter(476, "Врачи"), --ID: 376
			CheckboxFilter(375, "Временной парадокс"), --ID: 275
			CheckboxFilter(269, "Всемогущий главный герой"), --ID: 169
			CheckboxFilter(298, "Вторжение на землю"), --ID: 198
			CheckboxFilter(331, "Второй шанс"), --ID: 231
			CheckboxFilter(890, "Вуайеризм"), --ID: 790
			CheckboxFilter(480, "Выживание"), --ID: 380
			CheckboxFilter(461, "Высокомерные персонажи"), --ID: 361
			CheckboxFilter(695, "Гадание"), --ID: 595
			CheckboxFilter(877, "Гарем рабов"), --ID: 777
			CheckboxFilter(286, "Гг - женщина"), --ID: 186
			CheckboxFilter(266, "Гг - мужчина"), --ID: 166
			CheckboxFilter(271, "Гг силен с самого начала"), --ID: 171
			CheckboxFilter(492, "Геймеры"), --ID: 392
			CheckboxFilter(426, "Генералы"), --ID: 326
			CheckboxFilter(757, "Генетические модификации"), --ID: 657
			CheckboxFilter(717, "Гениальный главный герой"), --ID: 617
			CheckboxFilter(385, "Герои"), --ID: 285
			CheckboxFilter(683, "Героиня — сорванец"), --ID: 583
			CheckboxFilter(240, "Героическая фантастика"), --ID: 140
			CheckboxFilter(207, "Героическое фэнтези"), --ID: 107
			CheckboxFilter(287, "Герой влюбляется первым"), --ID: 187
			CheckboxFilter(670, "Гетерохромия"), --ID: 570
			CheckboxFilter(511, "Гильдии"), --ID: 411
			CheckboxFilter(855, "Гипнотизм"), --ID: 755
			CheckboxFilter(647, "Главный герой — бог"), --ID: 547
			CheckboxFilter(736, "Главный герой — гуманоид"), --ID: 636
			CheckboxFilter(545, "Главный герой — наполовину чел"), --ID: 445
			CheckboxFilter(892, "Главный герой — отец"), --ID: 792
			CheckboxFilter(880, "Главный герой — раб"), --ID: 780
			CheckboxFilter(588, "Главный герой — ребенок"), --ID: 488
			CheckboxFilter(576, "Главный герой — рубака"), --ID: 476
			CheckboxFilter(783, "Главный герой влюбляется первы"), --ID: 683
			CheckboxFilter(572, "Главный герой играет роль"), --ID: 472
			CheckboxFilter(772, "Главный герой носит очки"), --ID: 672
			CheckboxFilter(798, "Главный герой пацифист"), --ID: 698
			CheckboxFilter(703, "Гладиаторы"), --ID: 603
			CheckboxFilter(485, "Глуповатый главный герой"), --ID: 385
			CheckboxFilter(686, "Гоблины"), --ID: 586
			CheckboxFilter(720, "Големы"), --ID: 620
			CheckboxFilter(889, "Гомункул"), --ID: 789
			CheckboxFilter(559, "Горничные"), --ID: 459
			CheckboxFilter(205, "Городское фэнтези"), --ID: 105
			CheckboxFilter(900, "Госпиталь"), --ID: 800
			CheckboxFilter(402, "Готовка"), --ID: 302
			CheckboxFilter(493, "Гриндинг"), --ID: 393
			CheckboxFilter(562, "Дао Компаньон"), --ID: 462
			CheckboxFilter(860, "Даосизм"), --ID: 760
			CheckboxFilter(423, "Дварфы"), --ID: 323
			CheckboxFilter(742, "Двойная личность"), --ID: 642
			CheckboxFilter(701, "Двойник"), --ID: 601
			CheckboxFilter(760, "Дворецкий"), --ID: 660
			CheckboxFilter(268, "Дворяне"), --ID: 168
			CheckboxFilter(537, "Дворянство/Аристократия"), --ID: 437
			CheckboxFilter(769, "Девушки-монстры"), --ID: 669
			CheckboxFilter(822, "Демоническая техника культивац"), --ID: 722
			CheckboxFilter(252, "Демоны"), --ID: 152
			CheckboxFilter(883, "Денежный долг"), --ID: 783
			CheckboxFilter(655, "Депрессия"), --ID: 555
			CheckboxFilter(216, "Детектив"), --ID: 116
			CheckboxFilter(712, "Детективы"), --ID: 612
			CheckboxFilter(223, "Детская литература"), --ID: 123
			CheckboxFilter(262, "Дискриминация"), --ID: 162
			CheckboxFilter(496, "Добыча денег в приоритете"), --ID: 396
			CheckboxFilter(222, "Документальная проза"), --ID: 122
			CheckboxFilter(407, "Долгая разлука"), --ID: 307
			CheckboxFilter(390, "Домашние дела"), --ID: 290
			CheckboxFilter(570, "Домогательство"), --ID: 470
			CheckboxFilter(403, "Драконы"), --ID: 303
			CheckboxFilter(707, "Драконьи всадники"), --ID: 607
			CheckboxFilter(321, "Древние времена"), --ID: 221
			CheckboxFilter(474, "Древний Китай"), --ID: 374
			CheckboxFilter(317, "Дружба"), --ID: 217
			CheckboxFilter(382, "Друзья детства"), --ID: 282
			CheckboxFilter(667, "Друзья становятся врагами"), --ID: 567
			CheckboxFilter(597, "Друиды"), --ID: 497
			CheckboxFilter(884, "Дух лисы"), --ID: 784
			CheckboxFilter(272, "Духи/призраки"), --ID: 172
			CheckboxFilter(535, "Духовный советник"), --ID: 435
			CheckboxFilter(733, "Душевность"), --ID: 633
			CheckboxFilter(354, "Души"), --ID: 254
			CheckboxFilter(621, "Европейская атмосфера"), --ID: 521
			CheckboxFilter(675, "Ёкаи"), --ID: 575
			CheckboxFilter(254, "Есть аниме-адаптация"), --ID: 154
			CheckboxFilter(652, "Есть видеоигра по мотивам"), --ID: 552
			CheckboxFilter(255, "Есть манга"), --ID: 155
			CheckboxFilter(617, "Есть манхва-адаптация"), --ID: 517
			CheckboxFilter(488, "Есть маньхуа-адаптация"), --ID: 388
			CheckboxFilter(592, "Есть сериал-адаптация"), --ID: 492
			CheckboxFilter(273, "Есть фильм"), --ID: 173
			CheckboxFilter(605, "Женища-наставник"), --ID: 505
			CheckboxFilter(446, "Жесткая, двуличная личность"), --ID: 346
			CheckboxFilter(603, "Жестокие персонажи"), --ID: 503
			CheckboxFilter(754, "Жестокое обращение с ребенком"), --ID: 654
			CheckboxFilter(345, "Жестокость"), --ID: 245
			CheckboxFilter(854, "Животноводство"), --ID: 754
			CheckboxFilter(628, "Животные черты"), --ID: 528
			CheckboxFilter(706, "Жизнь в квартире"), --ID: 606
			CheckboxFilter(715, "Жрицы"), --ID: 615
			CheckboxFilter(388, "Заботливый главный герой"), --ID: 288
			CheckboxFilter(728, "Забывчивый главный герой"), --ID: 628
			CheckboxFilter(389, "Заговоры"), --ID: 289
			CheckboxFilter(462, "Закалка тела"), --ID: 362
			CheckboxFilter(856, "Законники"), --ID: 756
			CheckboxFilter(689, "Замкнутый главный герой"), --ID: 589
			CheckboxFilter(530, "Запечатанная сила"), --ID: 430
			CheckboxFilter(608, "Застенчивые персонажи"), --ID: 508
			CheckboxFilter(337, "Звери"), --ID: 237
			CheckboxFilter(401, "Звери-компаньоны"), --ID: 301
			CheckboxFilter(343, "Злой протагонист"), --ID: 243
			CheckboxFilter(604, "Злые боги"), --ID: 504
			CheckboxFilter(663, "Злые организации"), --ID: 563
			CheckboxFilter(834, "Злые религии"), --ID: 734
			CheckboxFilter(573, "Знаменитости"), --ID: 473
			CheckboxFilter(631, "Знаменитый главный герой"), --ID: 531
			CheckboxFilter(397, "Знания современного мира"), --ID: 297
			CheckboxFilter(509, "Зомби"), --ID: 409
			CheckboxFilter(374, "Игра на выживание"), --ID: 274
			CheckboxFilter(817, "Игривый протагонист"), --ID: 717
			CheckboxFilter(491, "Игровая система рейтинга"), --ID: 391
			CheckboxFilter(366, "Игровые элементы"), --ID: 266
			CheckboxFilter(776, "Игрушки (18+)"), --ID: 676
			CheckboxFilter(516, "Из грязи в князи"), --ID: 416
			CheckboxFilter(809, "Из женщины в мужчину"), --ID: 709
			CheckboxFilter(815, "Из мужчины в женщину"), --ID: 715
			CheckboxFilter(867, "Из полного в худого"), --ID: 767
			CheckboxFilter(302, "Из слабого в сильного"), --ID: 202
			CheckboxFilter(534, "Извращенный главный герой"), --ID: 434
			CheckboxFilter(634, "Изгои"), --ID: 534
			CheckboxFilter(764, "Изменение расы"), --ID: 664
			CheckboxFilter(400, "Изменения внешнего вида"), --ID: 300
			CheckboxFilter(319, "Изменения личности"), --ID: 219
			CheckboxFilter(329, "Изнасилование"), --ID: 229
			CheckboxFilter(455, "Изображения жестокости"), --ID: 355
			CheckboxFilter(335, "ИИ"), --ID: 235
			CheckboxFilter(848, "Империи"), --ID: 748
			CheckboxFilter(784, "Инвалидность"), --ID: 684
			CheckboxFilter(392, "Индустриализация"), --ID: 292
			CheckboxFilter(263, "Инженер"), --ID: 163
			CheckboxFilter(625, "Инцест"), --ID: 525
			CheckboxFilter(336, "Искусственный интеллект"), --ID: 236
			CheckboxFilter(770, "Исследования"), --ID: 670
			CheckboxFilter(219, "Историческая проза"), --ID: 119
			CheckboxFilter(220, "Исторические приключения"), --ID: 120
			CheckboxFilter(217, "Исторический детектив"), --ID: 117
			CheckboxFilter(238, "Исторический любовный роман"), --ID: 138
			CheckboxFilter(210, "Историческое фэнтези"), --ID: 110
			CheckboxFilter(556, "Каннибализм"), --ID: 456
			CheckboxFilter(782, "Карточные игры"), --ID: 682
			CheckboxFilter(241, "Киберпанк"), --ID: 141
			CheckboxFilter(786, "Киберспорт"), --ID: 686
			CheckboxFilter(896, "Кланы"), --ID: 796
			CheckboxFilter(835, "Класс безработного"), --ID: 735
			CheckboxFilter(547, "Клоны"), --ID: 447
			CheckboxFilter(316, "Клубы"), --ID: 216
			CheckboxFilter(527, "Книги"), --ID: 427
			CheckboxFilter(500, "Книги навыков"), --ID: 400
			CheckboxFilter(619, "Книжный червь"), --ID: 519
			CheckboxFilter(330, "Коварство"), --ID: 230
			CheckboxFilter(804, "Коллеги"), --ID: 704
			CheckboxFilter(826, "Колледж/Университет"), --ID: 726
			CheckboxFilter(876, "Кома"), --ID: 776
			CheckboxFilter(596, "Командная работа"), --ID: 496
			CheckboxFilter(682, "Комедийный оттенок"), --ID: 582
			CheckboxFilter(650, "Комплекс неполноценности"), --ID: 550
			CheckboxFilter(323, "Комплекс семейных отношений"), --ID: 223
			CheckboxFilter(846, "Конкуренция"), --ID: 746
			CheckboxFilter(457, "Контроль разума/сознания"), --ID: 357
			CheckboxFilter(525, "Копейщик"), --ID: 425
			CheckboxFilter(897, "Королевская битва"), --ID: 797
			CheckboxFilter(278, "Королевская власть"), --ID: 178
			CheckboxFilter(359, "Королевства"), --ID: 259
			CheckboxFilter(236, "Короткий любовный роман"), --ID: 136
			CheckboxFilter(557, "Коррупция"), --ID: 457
			CheckboxFilter(246, "Космическая фантастика"), --ID: 146
			CheckboxFilter(797, "Космические войны"), --ID: 697
			CheckboxFilter(326, "Красивый герой"), --ID: 226
			CheckboxFilter(477, "Крафт"), --ID: 377
			CheckboxFilter(740, "Кризис личности"), --ID: 640
			CheckboxFilter(453, "Кругосветное путешествие"), --ID: 353
			CheckboxFilter(606, "Кудере"), --ID: 506
			CheckboxFilter(818, "Кузены"), --ID: 718
			CheckboxFilter(618, "Кузнец"), --ID: 518
			CheckboxFilter(601, "Кукловоды"), --ID: 501
			CheckboxFilter(724, "Куклы/марионетки"), --ID: 624
			CheckboxFilter(341, "Культивация"), --ID: 241
			CheckboxFilter(767, "Куннилингус"), --ID: 667
			CheckboxFilter(600, "Легенды"), --ID: 500
			CheckboxFilter(744, "Легкая жизнь"), --ID: 644
			CheckboxFilter(721, "Ленивый главный герой"), --ID: 621
			CheckboxFilter(594, "Лидерство"), --ID: 494
			CheckboxFilter(313, "Лоли"), --ID: 213
			CheckboxFilter(577, "Лотерея"), --ID: 477
			CheckboxFilter(235, "Любовное фэнтези"), --ID: 135
			CheckboxFilter(318, "Любовный треугольник"), --ID: 218
			CheckboxFilter(660, "Любовь детства"), --ID: 560
			CheckboxFilter(837, "Любовь с первого взгляда"), --ID: 737
			CheckboxFilter(553, "Магические надписи"), --ID: 453
			CheckboxFilter(469, "Магические печати"), --ID: 369
			CheckboxFilter(540, "Магические технологии"), --ID: 440
			CheckboxFilter(265, "Магия"), --ID: 165
			CheckboxFilter(518, "Магия призыва"), --ID: 418
			CheckboxFilter(788, "Мазохистские персонажи"), --ID: 688
			CheckboxFilter(349, "Манипулятивные персонажи"), --ID: 249
			CheckboxFilter(312, "Мания"), --ID: 212
			CheckboxFilter(566, "Мастер на все руки"), --ID: 466
			CheckboxFilter(888, "Мастурбация"), --ID: 788
			CheckboxFilter(656, "Махо-сёдзё"), --ID: 556
			CheckboxFilter(607, "Медицинские знания"), --ID: 507
			CheckboxFilter(332, "Медленная романтическая линия"), --ID: 232
			CheckboxFilter(794, "Медленное развитие на старте"), --ID: 694
			CheckboxFilter(504, "Межпространственные путешестви"), --ID: 404
			CheckboxFilter(394, "Менеджмент"), --ID: 294
			CheckboxFilter(861, "Мертвый главный герой"), --ID: 761
			CheckboxFilter(309, "Месть"), --ID: 209
			CheckboxFilter(435, "Метаморфы"), --ID: 335
			CheckboxFilter(280, "Меч и магия"), --ID: 180
			CheckboxFilter(747, "Мечник"), --ID: 647
			CheckboxFilter(838, "Мечты"), --ID: 738
			CheckboxFilter(825, "Милая история"), --ID: 725
			CheckboxFilter(737, "Милое дитя"), --ID: 637
			CheckboxFilter(814, "Милый главный герой"), --ID: 714
			CheckboxFilter(563, "Мировое дерево"), --ID: 463
			CheckboxFilter(251, "Мистика"), --ID: 151
			CheckboxFilter(583, "Мистический ореол вокруг семьи"), --ID: 483
			CheckboxFilter(591, "Мифические звери"), --ID: 491
			CheckboxFilter(630, "Мифология"), --ID: 530
			CheckboxFilter(885, "Младшие братья"), --ID: 785
			CheckboxFilter(627, "Младшие сестры"), --ID: 527
			CheckboxFilter(495, "ММОРПГ (ЛитРПГ)"), --ID: 395
			CheckboxFilter(649, "Множество перемещенных людей"), --ID: 549
			CheckboxFilter(470, "Множество реальностей"), --ID: 370
			CheckboxFilter(430, "Множество реинкарнированных лю"), --ID: 330
			CheckboxFilter(778, "Модели"), --ID: 678
			CheckboxFilter(821, "Молчаливый персонаж"), --ID: 721
			CheckboxFilter(292, "Монстры"), --ID: 192
			CheckboxFilter(806, "Мужская гей-пара"), --ID: 706
			CheckboxFilter(367, "Мужчина-яндере"), --ID: 267
			CheckboxFilter(735, "Музыка"), --ID: 635
			CheckboxFilter(734, "Музыкальные группы"), --ID: 634
			CheckboxFilter(793, "Мутации"), --ID: 693
			CheckboxFilter(505, "Мутированные существа"), --ID: 405
			CheckboxFilter(762, "Навык кражи"), --ID: 662
			CheckboxFilter(306, "Навязчивая любовь"), --ID: 206
			CheckboxFilter(512, "Наемники"), --ID: 412
			CheckboxFilter(661, "Назойливый возлюбленный"), --ID: 561
			CheckboxFilter(289, "Наивный главный герой"), --ID: 189
			CheckboxFilter(789, "Наркотики"), --ID: 689
			CheckboxFilter(632, "Нарциссический главный герой"), --ID: 532
			CheckboxFilter(874, "Насилие сексуального характера"), --ID: 774
			CheckboxFilter(552, "Наследование"), --ID: 452
			CheckboxFilter(244, "Научная фантастика"), --ID: 144
			CheckboxFilter(506, "Национализм"), --ID: 406
			CheckboxFilter(515, "Не блещущий внешне главный гер"), --ID: 415
			CheckboxFilter(626, "Не родные братья и сестры"), --ID: 526
			CheckboxFilter(668, "Небеса"), --ID: 568
			CheckboxFilter(467, "Небесное испытание"), --ID: 367
			CheckboxFilter(759, "Негуманоидный главный герой"), --ID: 659
			CheckboxFilter(646, "Недоверчивый главный герой"), --ID: 546
			CheckboxFilter(358, "Недооцененный главный герой"), --ID: 258
			CheckboxFilter(409, "Недоразумения"), --ID: 309
			CheckboxFilter(296, "Неизлечимая болезнь"), --ID: 196
			CheckboxFilter(497, "Некромант"), --ID: 397
			CheckboxFilter(369, "Нелинейная история"), --ID: 269
			CheckboxFilter(648, "Ненавистный главный герой"), --ID: 548
			CheckboxFilter(377, "Ненадежный рассказчик"), --ID: 277
			CheckboxFilter(872, "Нерезиденты"), --ID: 772
			CheckboxFilter(844, "Нерешительный главный герой"), --ID: 744
			CheckboxFilter(484, "Несерьезный главный герой"), --ID: 384
			CheckboxFilter(676, "Несколько временных линий"), --ID: 576
			CheckboxFilter(368, "Несколько гг"), --ID: 268
			CheckboxFilter(637, "Несколько главных героев"), --ID: 537
			CheckboxFilter(752, "Несколько идентичностей"), --ID: 652
			CheckboxFilter(636, "Несколько личностей"), --ID: 536
			CheckboxFilter(832, "Нетораре"), --ID: 732
			CheckboxFilter(614, "Нетори"), --ID: 514
			CheckboxFilter(718, "Неудачливый главный герой"), --ID: 618
			CheckboxFilter(541, "Ниндзя"), --ID: 441
			CheckboxFilter(203, "Новелла"), --ID: 103
			CheckboxFilter(842, "Обещание из детства"), --ID: 742
			CheckboxFilter(585, "Обманщик"), --ID: 485
			CheckboxFilter(314, "Обмен телами"), --ID: 214
			CheckboxFilter(590, "Обнаженка"), --ID: 490
			CheckboxFilter(831, "Обольщение"), --ID: 731
			CheckboxFilter(761, "Оборотни"), --ID: 661
			CheckboxFilter(451, "Обратный гарем"), --ID: 351
			CheckboxFilter(429, "Общество монстров"), --ID: 329
			CheckboxFilter(702, "Обязательство"), --ID: 602
			CheckboxFilter(391, "Огнестрельное оружие"), --ID: 291
			CheckboxFilter(294, "Ограниченное время жизни"), --ID: 194
			CheckboxFilter(612, "Одержимость"), --ID: 512
			CheckboxFilter(494, "Одинокий главный герой"), --ID: 394
			CheckboxFilter(406, "Одиночество"), --ID: 306
			CheckboxFilter(413, "Одиночное проживание"), --ID: 313
			CheckboxFilter(859, "Околосмертные переживания"), --ID: 759
			CheckboxFilter(697, "Оммёдзи"), --ID: 597
			CheckboxFilter(438, "Омоложение"), --ID: 338
			CheckboxFilter(640, "Организованная преступность"), --ID: 540
			CheckboxFilter(875, "Оргия"), --ID: 775
			CheckboxFilter(431, "Орки"), --ID: 331
			CheckboxFilter(436, "Освоение навыков"), --ID: 336
			CheckboxFilter(705, "Основано на аниме"), --ID: 605
			CheckboxFilter(820, "Основано на видео игре"), --ID: 720
			CheckboxFilter(893, "Основано на визуальной новелле"), --ID: 793
			CheckboxFilter(800, "Основано на песне"), --ID: 700
			CheckboxFilter(704, "Основано на фильме"), --ID: 604
			CheckboxFilter(340, "Осторожный главный герой"), --ID: 240
			CheckboxFilter(671, "Отаку"), --ID: 571
			CheckboxFilter(364, "Открытый космос"), --ID: 264
			CheckboxFilter(827, "Отношения в сети"), --ID: 727
			CheckboxFilter(411, "Отношения между людьми и нелюд"), --ID: 311
			CheckboxFilter(891, "Отношения на расстоянии"), --ID: 791
			CheckboxFilter(672, "Отношения Сенпай-Коухай"), --ID: 572
			CheckboxFilter(615, "Отношения ученика и учителя"), --ID: 515
			CheckboxFilter(529, "Отношения учитель-ученик"), --ID: 429
			CheckboxFilter(412, "Отношения хозяин-слуга"), --ID: 312
			CheckboxFilter(833, "Отомэ игра"), --ID: 733
			CheckboxFilter(745, "Отсутствие здравого смысла"), --ID: 645
			CheckboxFilter(725, "Отсутствие родителей"), --ID: 625
			CheckboxFilter(807, "Офисный роман"), --ID: 707
			CheckboxFilter(803, "Официанты"), --ID: 703
			CheckboxFilter(478, "Охотники"), --ID: 378
			CheckboxFilter(787, "Очаровательный главный герой"), --ID: 687
			CheckboxFilter(755, "Падшее дворянство"), --ID: 655
			CheckboxFilter(665, "Падшие ангелы"), --ID: 565
			CheckboxFilter(765, "Пайзури"), --ID: 665
			CheckboxFilter(691, "Паразиты"), --ID: 591
			CheckboxFilter(307, "Параллельные миры"), --ID: 207
			CheckboxFilter(365, "Парк"), --ID: 265
			CheckboxFilter(732, "Парк развлечений"), --ID: 632
			CheckboxFilter(507, "Пародия"), --ID: 407
			CheckboxFilter(839, "Певцы/Певицы"), --ID: 739
			CheckboxFilter(829, "Первая любовь"), --ID: 729
			CheckboxFilter(711, "Первоисточник новеллы — манга"), --ID: 611
			CheckboxFilter(887, "Первый раз"), --ID: 787
			CheckboxFilter(688, "Перемещение в игровой мир"), --ID: 588
			CheckboxFilter(850, "Перемещение в иной мир"), --ID: 750
			CheckboxFilter(851, "Перерождение в ином мире"), --ID: 751
			CheckboxFilter(357, "Переселение души/трансмиграция"), --ID: 257
			CheckboxFilter(766, "Персонаж использует щит"), --ID: 666
			CheckboxFilter(300, "Петля времени"), --ID: 200
			CheckboxFilter(871, "Пираты"), --ID: 771
			CheckboxFilter(582, "Писатели"), --ID: 482
			CheckboxFilter(449, "Питомцы"), --ID: 349
			CheckboxFilter(481, "Племенное общество"), --ID: 381
			CheckboxFilter(383, "Повелитель демонов"), --ID: 283
			CheckboxFilter(422, "Подземелья"), --ID: 322
			CheckboxFilter(214, "Подростковая проза"), --ID: 114
			CheckboxFilter(378, "Пожелания"), --ID: 278
			CheckboxFilter(543, "Познание Дао"), --ID: 443
			CheckboxFilter(690, "Покинутое дитя"), --ID: 590
			CheckboxFilter(486, "Полигамия"), --ID: 386
			CheckboxFilter(270, "Политика"), --ID: 170
			CheckboxFilter(233, "Политический роман"), --ID: 133
			CheckboxFilter(864, "Полиция"), --ID: 764
			CheckboxFilter(520, "Полулюди"), --ID: 420
			CheckboxFilter(442, "Популярный любовный интерес"), --ID: 342
			CheckboxFilter(245, "Постапокалипсис"), --ID: 145
			CheckboxFilter(284, "Постапокалиптика"), --ID: 184
			CheckboxFilter(849, "Потерянные цивилизации"), --ID: 749
			CheckboxFilter(823, "Похищения людей"), --ID: 723
			CheckboxFilter(211, "Поэзия"), --ID: 111
			CheckboxFilter(813, "Правонарушители"), --ID: 713
			CheckboxFilter(692, "Прагматичный главный герой"), --ID: 592
			CheckboxFilter(325, "Преданный любовный интерес"), --ID: 225
			CheckboxFilter(322, "Предательство"), --ID: 222
			CheckboxFilter(277, "Предвидение"), --ID: 177
			CheckboxFilter(258, "Прекрасная героиня"), --ID: 158
			CheckboxFilter(836, "Преступники"), --ID: 736
			CheckboxFilter(304, "Преступность"), --ID: 204
			CheckboxFilter(362, "Призванный герой"), --ID: 262
			CheckboxFilter(276, "Призраки"), --ID: 176
			CheckboxFilter(743, "Принуждение к отношениям"), --ID: 643
			CheckboxFilter(895, "Принцессы"), --ID: 795
			CheckboxFilter(741, "Притворная пара"), --ID: 641
			CheckboxFilter(487, "Причудливые персонажи"), --ID: 387
			CheckboxFilter(297, "Пришельцы/инопланетяне"), --ID: 197
			CheckboxFilter(791, "Программист"), --ID: 691
			CheckboxFilter(274, "Проклятия"), --ID: 174
			CheckboxFilter(678, "Промывание мозгов"), --ID: 578
			CheckboxFilter(356, "Пропуск времени"), --ID: 256
			CheckboxFilter(599, "Пророчества"), --ID: 499
			CheckboxFilter(886, "Проститутки"), --ID: 786
			CheckboxFilter(420, "Прошлое играет большую роль"), --ID: 320
			CheckboxFilter(841, "Прыжки между мирами"), --ID: 741
			CheckboxFilter(459, "Психические силы"), --ID: 359
			CheckboxFilter(370, "Психопаты"), --ID: 270
			CheckboxFilter(224, "Публицистика"), --ID: 124
			CheckboxFilter(301, "Путешествие во времени"), --ID: 201
			CheckboxFilter(380, "Пытка"), --ID: 280
			CheckboxFilter(878, "Рабы"), --ID: 778
			CheckboxFilter(225, "Развитие личности"), --ID: 125
			CheckboxFilter(858, "Развод"), --ID: 758
			CheckboxFilter(386, "Разумные предметы"), --ID: 286
			CheckboxFilter(508, "Расизм"), --ID: 408
			CheckboxFilter(285, "Рассказ"), --ID: 185
			CheckboxFilter(443, "Расторжения помолвки"), --ID: 343
			CheckboxFilter(415, "Расы зооморфов"), --ID: 315
			CheckboxFilter(346, "Реализм"), --ID: 246
			CheckboxFilter(830, "Ревность"), --ID: 730
			CheckboxFilter(805, "Редакторы"), --ID: 705
			CheckboxFilter(472, "Реинкарнация"), --ID: 372
			CheckboxFilter(410, "Реинкарнация в монстра"), --ID: 310
			CheckboxFilter(811, "Реинкарнация в объект"), --ID: 711
			CheckboxFilter(716, "Религии"), --ID: 616
			CheckboxFilter(881, "Репортеры"), --ID: 781
			CheckboxFilter(780, "Ресторан"), --ID: 680
			CheckboxFilter(342, "Решительный главный герой"), --ID: 242
			CheckboxFilter(863, "Робкий главный герой"), --ID: 763
			CheckboxFilter(808, "Родитель одиночка"), --ID: 708
			CheckboxFilter(687, "Родительский комплекс"), --ID: 587
			CheckboxFilter(339, "Родословная"), --ID: 239
			CheckboxFilter(232, "Романтическая эротика"), --ID: 132
			CheckboxFilter(371, "Романтический подсюжет"), --ID: 271
			CheckboxFilter(315, "Рост персонажа"), --ID: 215
			CheckboxFilter(360, "Рыцари"), --ID: 260
			CheckboxFilter(774, "Садистские персонажи"), --ID: 674
			CheckboxFilter(847, "Самоотверженный главный герой"), --ID: 747
			CheckboxFilter(777, "Самурай"), --ID: 677
			CheckboxFilter(620, "Сборник коротких историй"), --ID: 520
			CheckboxFilter(635, "Связанные сюжетные линии"), --ID: 535
			CheckboxFilter(852, "Святые"), --ID: 752
			CheckboxFilter(513, "Священники"), --ID: 413
			CheckboxFilter(862, "Сдержанный главный герой"), --ID: 762
			CheckboxFilter(517, "Секретные организации"), --ID: 417
			CheckboxFilter(726, "Секреты"), --ID: 626
			CheckboxFilter(879, "Секс рабы"), --ID: 779
			CheckboxFilter(857, "Семейный конфликт"), --ID: 757
			CheckboxFilter(434, "Семь добродетелей"), --ID: 334
			CheckboxFilter(353, "Семь смертных грехов"), --ID: 253
			CheckboxFilter(447, "Семья"), --ID: 347
			CheckboxFilter(790, "Сёнэн-ай подсюжет"), --ID: 690
			CheckboxFilter(657, "Серийные убийцы"), --ID: 557
			CheckboxFilter(658, "Сестринский комплекс"), --ID: 558
			CheckboxFilter(473, "Сила духа"), --ID: 373
			CheckboxFilter(679, "Сила, требующая платы за польз"), --ID: 579
			CheckboxFilter(328, "Сильная пара"), --ID: 228
			CheckboxFilter(542, "Сильный в сильнейшего"), --ID: 442
			CheckboxFilter(373, "Сильный любовный интерес"), --ID: 273
			CheckboxFilter(311, "Синдром восьмиклассника"), --ID: 211
			CheckboxFilter(419, "Сироты"), --ID: 319
			CheckboxFilter(405, "Система уровней"), --ID: 305
			CheckboxFilter(638, "Системный администратор"), --ID: 538
			CheckboxFilter(226, "Сказка"), --ID: 126
			CheckboxFilter(551, "Скрытие истинной личности"), --ID: 451
			CheckboxFilter(448, "Скрытие истинных способностей"), --ID: 348
			CheckboxFilter(352, "Скрытный главный герой"), --ID: 252
			CheckboxFilter(347, "Скрытые способности"), --ID: 247
			CheckboxFilter(548, "Скульпторы"), --ID: 448
			CheckboxFilter(418, "Слабо выраженная романтическая"), --ID: 318
			CheckboxFilter(398, "Слабый главный герой"), --ID: 298
			CheckboxFilter(894, "Слепой главный герой"), --ID: 794
			CheckboxFilter(433, "Слуги"), --ID: 333
			CheckboxFilter(231, "Слэш"), --ID: 131
			CheckboxFilter(275, "Смерть"), --ID: 175
			CheckboxFilter(544, "Смерть близких"), --ID: 444
			CheckboxFilter(327, "Собственнические персонажи"), --ID: 227
			CheckboxFilter(250, "Современная проза"), --ID: 150
			CheckboxFilter(267, "Современность"), --ID: 167
			CheckboxFilter(237, "Современный любовный роман"), --ID: 137
			CheckboxFilter(644, "Сожительство"), --ID: 544
			CheckboxFilter(387, "Создание армии"), --ID: 287
			CheckboxFilter(482, "Создание артефактов"), --ID: 382
			CheckboxFilter(613, "Создание клана"), --ID: 513
			CheckboxFilter(393, "Создание королевства"), --ID: 293
			CheckboxFilter(437, "Создание навыков"), --ID: 337
			CheckboxFilter(569, "Создание секты"), --ID: 469
			CheckboxFilter(293, "Солдаты/военные"), --ID: 193
			CheckboxFilter(722, "Сон"), --ID: 622
			CheckboxFilter(290, "Состоятельные персонажи"), --ID: 190
			CheckboxFilter(355, "Социальная иерархия по силе"), --ID: 255
			CheckboxFilter(248, "Социальная фантастика"), --ID: 148
			CheckboxFilter(642, "Социальные изгои"), --ID: 542
			CheckboxFilter(738, "Спасение мира"), --ID: 638
			CheckboxFilter(279, "Специальные способности"), --ID: 179
			CheckboxFilter(260, "Спокойный главный герой"), --ID: 160
			CheckboxFilter(819, "Справедливый главный герой"), --ID: 719
			CheckboxFilter(396, "Средневековье"), --ID: 296
			CheckboxFilter(483, "Ссорящаяся пара"), --ID: 383
			CheckboxFilter(810, "Сталкеры"), --ID: 710
			CheckboxFilter(399, "Старение"), --ID: 299
			CheckboxFilter(239, "Стимпанк"), --ID: 139
			CheckboxFilter(609, "Стоические персонажи"), --ID: 509
			CheckboxFilter(775, "Стокгольмский синдром"), --ID: 675
			CheckboxFilter(595, "Стратег"), --ID: 495
			CheckboxFilter(372, "Стратегические битвы"), --ID: 272
			CheckboxFilter(898, "Стратегия"), --ID: 798
			CheckboxFilter(622, "Стрелки"), --ID: 522
			CheckboxFilter(561, "Стрельба из лука"), --ID: 461
			CheckboxFilter(651, "Студенческий совет"), --ID: 551
			CheckboxFilter(464, "Судьба"), --ID: 364
			CheckboxFilter(645, "Суккубы"), --ID: 545
			CheckboxFilter(899, "Супер герои"), --ID: 799
			CheckboxFilter(456, "Суровая подготовка"), --ID: 356
			CheckboxFilter(295, "Таинственная болезнь"), --ID: 195
			CheckboxFilter(458, "Таинственное прошлое"), --ID: 358
			CheckboxFilter(499, "Тайная личность"), --ID: 399
			CheckboxFilter(868, "Тайные отношения"), --ID: 768
			CheckboxFilter(882, "Танцоры"), --ID: 782
			CheckboxFilter(616, "Телохранители"), --ID: 516
			CheckboxFilter(206, "Темное фэнтези"), --ID: 106
			CheckboxFilter(812, "Тентакли"), --ID: 712
			CheckboxFilter(674, "Террористы"), --ID: 574
			CheckboxFilter(758, "Технологический разрыв"), --ID: 658
			CheckboxFilter(700, "Тихие персонажи"), --ID: 600
			CheckboxFilter(489, "Толстый главный герой"), --ID: 389
			CheckboxFilter(589, "Торговцы"), --ID: 489
			CheckboxFilter(310, "Травля/буллинг"), --ID: 210
			CheckboxFilter(824, "Травник"), --ID: 724
			CheckboxFilter(376, "Трагическое прошлое"), --ID: 276
			CheckboxFilter(549, "Трансплантация воспоминаний"), --ID: 449
			CheckboxFilter(234, "Триллер"), --ID: 134
			CheckboxFilter(264, "Трудолюбивый главный герой"), --ID: 164
			CheckboxFilter(641, "Тюрьма"), --ID: 541
			CheckboxFilter(305, "Убийства"), --ID: 205
			CheckboxFilter(445, "Убийцы"), --ID: 345
			CheckboxFilter(746, "Убийцы драконов"), --ID: 646
			CheckboxFilter(463, "Уверенный главный герой"), --ID: 363
			CheckboxFilter(578, "Удачливый главный герой"), --ID: 478
			CheckboxFilter(212, "Ужасы"), --ID: 112
			CheckboxFilter(522, "Укротитель монстров"), --ID: 422
			CheckboxFilter(471, "Умения из прошлой жизни"), --ID: 371
			CheckboxFilter(654, "Умная пара"), --ID: 554
			CheckboxFilter(261, "Умный главный герой"), --ID: 161
			CheckboxFilter(450, "Уникальная техника Культивации"), --ID: 350
			CheckboxFilter(526, "Уникальное оружие"), --ID: 426
			CheckboxFilter(503, "Управление бизнесом"), --ID: 403
			CheckboxFilter(379, "Управление временем"), --ID: 279
			CheckboxFilter(853, "Управление кровью"), --ID: 753
			CheckboxFilter(795, "Упрямый главный герой"), --ID: 695
			CheckboxFilter(866, "Уродливый главный герой"), --ID: 766
			CheckboxFilter(490, "Ускоренный рост"), --ID: 390
			CheckboxFilter(643, "Усыновленные дети"), --ID: 543
			CheckboxFilter(586, "Усыновленный главный герой"), --ID: 486
			CheckboxFilter(574, "Уход за детьми"), --ID: 474
			CheckboxFilter(531, "Учителя"), --ID: 431
			CheckboxFilter(696, "Фамильяры"), --ID: 596
			CheckboxFilter(750, "Фанатизм"), --ID: 650
			CheckboxFilter(510, "Фантастические существа"), --ID: 410
			CheckboxFilter(215, "Фантастический детектив"), --ID: 115
			CheckboxFilter(213, "Фанфик"), --ID: 113
			CheckboxFilter(564, "Фанфикшн"), --ID: 464
			CheckboxFilter(828, "Фармацевт"), --ID: 728
			CheckboxFilter(558, "Фарминг"), --ID: 458
			CheckboxFilter(416, "Феи"), --ID: 316
			CheckboxFilter(731, "Фелляция"), --ID: 631
			CheckboxFilter(227, "Фемслэш"), --ID: 127
			CheckboxFilter(554, "Фениксы"), --ID: 454
			CheckboxFilter(659, "Фетиш груди"), --ID: 559
			CheckboxFilter(308, "Философия"), --ID: 208
			CheckboxFilter(579, "Фильмы"), --ID: 479
			CheckboxFilter(685, "Флэшбэки"), --ID: 585
			CheckboxFilter(320, "Фобии"), --ID: 220
			CheckboxFilter(629, "Фольклор"), --ID: 529
			CheckboxFilter(719, "Футанари"), --ID: 619
			CheckboxFilter(560, "Футуристический сеттинг"), --ID: 460
			CheckboxFilter(344, "Фэнтези мир"), --ID: 244
			CheckboxFilter(575, "Хакеры"), --ID: 475
			CheckboxFilter(567, "Харизматический герой"), --ID: 467
			CheckboxFilter(624, "Хикикомори/Затворники"), --ID: 524
			CheckboxFilter(324, "Хитроумный главный герой"), --ID: 224
			CheckboxFilter(708, "Хозяин подземелий"), --ID: 608
			CheckboxFilter(454, "Холодный главный герой"), --ID: 354
			CheckboxFilter(666, "Хорошие отношения с семьей"), --ID: 566
			CheckboxFilter(291, "Хранители могил"), --ID: 191
			CheckboxFilter(565, "Целители"), --ID: 465
			CheckboxFilter(840, "Цзянши"), --ID: 740
			CheckboxFilter(610, "Цундэрэ"), --ID: 510
			CheckboxFilter(729, "Чаты"), --ID: 629
			CheckboxFilter(680, "Человеческое оружие"), --ID: 580
			CheckboxFilter(441, "Честный главный герой"), --ID: 341
			CheckboxFilter(439, "Читы"), --ID: 339
			CheckboxFilter(684, "Шантаж"), --ID: 584
			CheckboxFilter(440, "Шеф-повар"), --ID: 340
			CheckboxFilter(698, "Шикигами"), --ID: 598
			CheckboxFilter(768, "Школа только для девочек"), --ID: 668
			CheckboxFilter(673, "Шота"), --ID: 573
			CheckboxFilter(581, "Шоу-бизнес"), --ID: 481
			CheckboxFilter(218, "Шпионский детектив"), --ID: 118
			CheckboxFilter(714, "Шпионы"), --ID: 614
			CheckboxFilter(404, "Эволюция"), --ID: 304
			CheckboxFilter(694, "Эгоистичный главный герой"), --ID: 594
			CheckboxFilter(568, "Эйдетическая память"), --ID: 468
			CheckboxFilter(664, "Экзорсизм"), --ID: 564
			CheckboxFilter(653, "Экономика"), --ID: 553
			CheckboxFilter(773, "Эксгибиционизм"), --ID: 673
			CheckboxFilter(348, "Эксперименты с людьми"), --ID: 248
			CheckboxFilter(571, "Элементальная магия"), --ID: 471
			CheckboxFilter(384, "Эльфы"), --ID: 284
			CheckboxFilter(870, "Эмоционально слабый гг"), --ID: 770
			CheckboxFilter(749, "Эпизодический"), --ID: 649
			CheckboxFilter(209, "Эпическое фэнтези"), --ID: 109
			CheckboxFilter(229, "Эротическая фантастика"), --ID: 129
			CheckboxFilter(228, "Эротический фанфик"), --ID: 128
			CheckboxFilter(230, "Эротическое фэнтези"), --ID: 130
			CheckboxFilter(243, "Юмористическая фантастика"), --ID: 143
			CheckboxFilter(208, "Юмористическое фэнтези"), --ID: 108
			CheckboxFilter(611, "Юный любовный интерес"), --ID: 511
			CheckboxFilter(584, "Яды"), --ID: 484
			CheckboxFilter(580, "Языкастые персонажи"), --ID: 480
			CheckboxFilter(282, "Языковой барьер"), --ID: 182
			CheckboxFilter(414, "Яндере"), --ID: 314
			CheckboxFilter(710, "Японские силы самообороны"), --ID: 610
			CheckboxFilter(465, "Ярко выраженная романтика"), --ID: 365
			CheckboxFilter(432, "R-15 Японское возрастное огр."), --ID: 332
			CheckboxFilter(524, "R-18"), --ID: 424
			CheckboxFilter(748, "[Награжденная работа]"), --ID: 648
			CheckboxFilter(523, "18+"), --ID: 423
		}),
		FilterGroup("Типы", { --offset: 10
			CheckboxFilter(11, "Авторское"), --ID: 1
			CheckboxFilter(17, "Другое"), --ID: 7
			CheckboxFilter(15, "Запад"), --ID: 5
			CheckboxFilter(14, "Китай"), --ID: 4
			CheckboxFilter(13, "Корея"), --ID: 3
			CheckboxFilter(16, "Фанфики"), --ID: 6
			CheckboxFilter(12, "Япония"), --ID: 2
		}),
		FilterGroup("Статус проекта", { --offset: 20
			CheckboxFilter(24, "Анонс"), --ID: 4
			CheckboxFilter(20, "Закончен"), --ID: 0
			CheckboxFilter(22, "Заморожен"), --ID: 2
			CheckboxFilter(25, "Лицензировано"), --ID: 5
			CheckboxFilter(23, "Нет переводчика"), --ID: 3
			CheckboxFilter(21, "Продолжается"), --ID: 1
		}),
		FilterGroup("Возрастной рейтинг", { --offset: 30
			CheckboxFilter(30, "Для всех"), --ID: 0
			CheckboxFilter(31, "16+"), --ID: 1
			CheckboxFilter(32, "18+"), --ID: 2
		}),
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,
}

end)()