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
__modules["utf8"] = function()
-- {"ver":"1.0.0","author":"Stepets"}

local config = {
  unpack = table.unpack,
  int32array = function(size)
    return {}
  end,
}

-- $Id: utf8.lua 179 2009-04-03 18:10:03Z pasta $
--
-- Provides UTF-8 aware string functions implemented in pure lua:
-- * utf8len(s)
-- * utf8sub(s, i, j)
-- * utf8reverse(s)
-- * utf8char(unicode)
-- * utf8unicode(s, i, j)
-- * utf8gensub(s, sub_len)
-- * utf8find(str, regex, init, plain)
-- * utf8match(str, regex, init)
-- * utf8gmatch(str, regex, all)
-- * utf8gsub(str, regex, repl, limit)
--
-- All functions behave as their non UTF-8 aware counterparts with the exception
-- that UTF-8 characters are used instead of bytes for all units.

--[[
Copyright (c) 2006-2007, Kyle Smith
All rights reserved.

Contributors:
  Alimov Stepan

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the author nor the names of its contributors may be
      used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

-- ABNF from RFC 3629
--
-- UTF8-octets = *( UTF8-char )
-- UTF8-char   = UTF8-1 / UTF8-2 / UTF8-3 / UTF8-4
-- UTF8-1      = %x00-7F
-- UTF8-2      = %xC2-DF UTF8-tail
-- UTF8-3      = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
--               %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
-- UTF8-4      = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
--               %xF4 %x80-8F 2( UTF8-tail )
-- UTF8-tail   = %x80-BF
--

--return function(utf8)
local utf8            = {}

local byte            = string.byte
local char            = string.char
local dump            = string.dump
local find            = string.find
local format          = string.format
local len             = string.len
local lower           = string.lower
local rep             = string.rep
local sub             = string.sub
local upper           = string.upper

local utf8charpattern = '[%z\1-\127\194-\244][\128-\191]*'

local function utf8symbollen(byte)
  return not byte and 0 or (byte < 0x80 and 1) or (byte >= 0xF0 and 4) or (byte >= 0xE0 and 3) or (byte >= 0xC0 and 2) or
      1
end

local head_table = config.int32array(256)
for i = 0, 255 do
  head_table[i] = utf8symbollen(i)
end
head_table[256] = 0

local function utf8charbytes(str, bs)
  return head_table[byte(str, bs) or 256]
end

local function utf8next(str, bs)
  return bs + utf8charbytes(str, bs)
end

-- returns the number of characters in a UTF-8 string
local function utf8len(str)
  local bs = 1
  local bytes = len(str)
  local length = 0

  while bs <= bytes do
    length = length + 1
    bs = utf8next(str, bs)
  end

  return length
end

-- functions identically to string.sub except that i and j are UTF-8 characters
-- instead of bytes
local function utf8sub(s, i, j)
  -- argument defaults
  j = j or -1

  local bs = 1
  local bytes = len(s)
  local length = 0

  local l = (i >= 0 and j >= 0) or utf8len(s)
  i = (i >= 0) and i or l + i + 1
  j = (j >= 0) and j or l + j + 1

  if i > j then
    return ""
  end

  local start, finish = 1, bytes

  while bs <= bytes do
    length = length + 1

    if length == i then
      start = bs
    end

    bs = utf8next(s, bs)

    if length == j then
      finish = bs - 1
      break
    end
  end

  if i > length then start = bytes + 1 end
  if j < 1 then finish = 0 end

  return sub(s, start, finish)
end

-- http://en.wikipedia.org/wiki/Utf8
-- http://developer.coronalabs.com/code/utf-8-conversion-utility
local function utf8char(...)
  local codes = { ... }
  local result = {}

  for _, unicode in ipairs(codes) do
    if unicode <= 0x7F then
      result[#result + 1] = unicode
    elseif unicode <= 0x7FF then
      local b0 = 0xC0 + math.floor(unicode / 0x40);
      local b1 = 0x80 + (unicode % 0x40);
      result[#result + 1] = b0
      result[#result + 1] = b1
    elseif unicode <= 0xFFFF then
      local b0 = 0xE0 + math.floor(unicode / 0x1000);
      local b1 = 0x80 + (math.floor(unicode / 0x40) % 0x40);
      local b2 = 0x80 + (unicode % 0x40);
      result[#result + 1] = b0
      result[#result + 1] = b1
      result[#result + 1] = b2
    elseif unicode <= 0x10FFFF then
      local code          = unicode
      local b3            = 0x80 + (code % 0x40);
      code                = math.floor(code / 0x40)
      local b2            = 0x80 + (code % 0x40);
      code                = math.floor(code / 0x40)
      local b1            = 0x80 + (code % 0x40);
      code                = math.floor(code / 0x40)
      local b0            = 0xF0 + code;

      result[#result + 1] = b0
      result[#result + 1] = b1
      result[#result + 1] = b2
      result[#result + 1] = b3
    else
      error 'Unicode cannot be greater than U+10FFFF!'
    end
  end

  return char(config.unpack(result))
end


local shift_6  = 2 ^ 6
local shift_12 = 2 ^ 12
local shift_18 = 2 ^ 18

local utf8unicode
utf8unicode    = function(str, ibs, jbs)
  if ibs > jbs then return end

  local ch, bytes

  bytes = utf8charbytes(str, ibs)
  if bytes == 0 then return end

  local unicode

  if bytes == 1 then unicode = byte(str, ibs, ibs) end
  if bytes == 2 then
    local byte0, byte1 = byte(str, ibs, ibs + 1)
    if byte0 and byte1 then
      local code0, code1 = byte0 - 0xC0, byte1 - 0x80
      unicode = code0 * shift_6 + code1
    else
      unicode = byte0
    end
  end
  if bytes == 3 then
    local byte0, byte1, byte2 = byte(str, ibs, ibs + 2)
    if byte0 and byte1 and byte2 then
      local code0, code1, code2 = byte0 - 0xE0, byte1 - 0x80, byte2 - 0x80
      unicode = code0 * shift_12 + code1 * shift_6 + code2
    else
      unicode = byte0
    end
  end
  if bytes == 4 then
    local byte0, byte1, byte2, byte3 = byte(str, ibs, ibs + 3)
    if byte0 and byte1 and byte2 and byte3 then
      local code0, code1, code2, code3 = byte0 - 0xF0, byte1 - 0x80, byte2 - 0x80, byte3 - 0x80
      unicode = code0 * shift_18 + code1 * shift_12 + code2 * shift_6 + code3
    else
      unicode = byte0
    end
  end

  if ibs == jbs then
    return unicode
  else
    return unicode, utf8unicode(str, ibs + bytes, jbs)
  end
end

local function utf8byte(str, i, j)
  if #str == 0 then return end

  local ibs, jbs

  if i or j then
    i = i or 1
    j = j or i

    local str_len = utf8len(str)
    i = i < 0 and str_len + i + 1 or i
    j = j < 0 and str_len + j + 1 or j
    j = j > str_len and str_len or j

    if i > j then return end

    for p = 1, i - 1 do
      ibs = utf8next(str, ibs or 1)
    end

    if i == j then
      jbs = ibs
    else
      for p = 1, j - 1 do
        jbs = utf8next(str, jbs or 1)
      end
    end

    if not ibs or not jbs then
      return nil
    end
  else
    ibs, jbs = 1, 1
  end

  return utf8unicode(str, ibs, jbs)
end

local function utf8gensub(str, sub_len)
  sub_len = sub_len or 1
  local max_len = #str
  return function(skip_ptr, bs)
    bs = (bs and bs or 1) + (skip_ptr and (skip_ptr[1] or 0) or 0)

    local nbs = bs
    if bs > max_len then return nil end
    for i = 1, sub_len do
      nbs = utf8next(str, nbs)
    end

    return nbs, sub(str, bs, nbs - 1), bs
  end
end

local function utf8reverse(s)
  local result = ''
  for _, w in utf8gensub(s) do result = w .. result end
  return result
end

local function utf8validator(str, bs)
  bs = bs or 1

  if type(str) ~= "string" then
    error("bad argument #1 to 'utf8charbytes' (string expected, got " .. type(str) .. ")")
  end
  if type(bs) ~= "number" then
    error("bad argument #2 to 'utf8charbytes' (number expected, got " .. type(bs) .. ")")
  end

  local c = byte(str, bs)
  if not c then return end

  -- determine bytes needed for character, based on RFC 3629

  -- UTF8-1
  if c >= 0 and c <= 127 then
    return bs + 1
  elseif c >= 128 and c <= 193 then
    return bs + 1, bs, 1, c
    -- UTF8-2
  elseif c >= 194 and c <= 223 then
    local c2 = byte(str, bs + 1)
    if not c2 or c2 < 128 or c2 > 191 then
      return bs + 2, bs, 2, c2
    end

    return bs + 2
    -- UTF8-3
  elseif c >= 224 and c <= 239 then
    local c2 = byte(str, bs + 1)

    if not c2 then
      return bs + 2, bs, 2, c2
    end

    -- validate byte 2
    if c == 224 and (c2 < 160 or c2 > 191) then
      return bs + 2, bs, 2, c2
    elseif c == 237 and (c2 < 128 or c2 > 159) then
      return bs + 2, bs, 2, c2
    elseif c2 < 128 or c2 > 191 then
      return bs + 2, bs, 2, c2
    end

    local c3 = byte(str, bs + 2)
    if not c3 or c3 < 128 or c3 > 191 then
      return bs + 3, bs, 3, c3
    end

    return bs + 3
    -- UTF8-4
  elseif c >= 240 and c <= 244 then
    local c2 = byte(str, bs + 1)

    if not c2 then
      return bs + 2, bs, 2, c2
    end

    -- validate byte 2
    if c == 240 and (c2 < 144 or c2 > 191) then
      return bs + 2, bs, 2, c2
    elseif c == 244 and (c2 < 128 or c2 > 143) then
      return bs + 2, bs, 2, c2
    elseif c2 < 128 or c2 > 191 then
      return bs + 2, bs, 2, c2
    end

    local c3 = byte(str, bs + 2)
    if not c3 or c3 < 128 or c3 > 191 then
      return bs + 3, bs, 3, c3
    end

    local c4 = byte(str, bs + 3)
    if not c4 or c4 < 128 or c4 > 191 then
      return bs + 4, bs, 4, c4
    end

    return bs + 4
  else -- c > 245
    return bs + 1, bs, 1, c
  end
end

local function utf8validate(str, byte_pos)
  local result = {}
  for nbs, bs, part, code in utf8validator, str, byte_pos do
    if bs then
      result[#result + 1] = { pos = bs, part = part, code = code }
    end
  end
  return #result == 0, result
end

local function utf8codes(str)
  local max_len = #str
  local bs = 1
  return function(skip_ptr)
    if bs > max_len then return nil end
    local pbs = bs
    bs = utf8next(str, pbs)

    return pbs, utf8unicode(str, pbs, pbs), pbs
  end
end


--[[--
differs from Lua 5.3 utf8.offset in accepting any byte positions (not only head byte) for all n values

h - head, c - continuation, t - tail
hhhccthccthccthcthhh
        ^ start byte pos
searching current charracter head by moving backwards
hhhccthccthccthcthhh
      ^ head

n == 0: current position
n > 0: n jumps forward
n < 0: n more scans backwards
--]]--
local function utf8offset(str, n, bs)
  local l = #str
  if not bs then
    if n < 0 then
      bs = l + 1
    else
      bs = 1
    end
  end
  if bs <= 0 or bs > l + 1 then
    error("bad argument #3 to 'offset' (position out of range)")
  end

  if n == 0 then
    if bs == l + 1 then
      return bs
    end
    while true do
      local b = byte(str, bs)
      if (0 < b and b < 127)
          or (194 < b and b < 244) then
        return bs
      end
      bs = bs - 1
      if bs < 1 then
        return
      end
    end
  elseif n < 0 then
    bs = bs - 1
    repeat
      if bs < 1 then
        return
      end

      local b = byte(str, bs)
      if (0 < b and b < 127)
          or (194 < b and b < 244) then
        n = n + 1
      end
      bs = bs - 1
    until n == 0
    return bs + 1
  else
    while true do
      if bs > l then
        return
      end

      local b = byte(str, bs)
      if (0 < b and b < 127)
          or (194 < b and b < 244) then
        n = n - 1
        for i = 1, n do
          if bs > l then
            return
          end
          bs = utf8next(str, bs)
        end
        return bs
      end
      bs = bs - 1
    end
  end
end

local function utf8replace(s, mapping)
  if type(s) ~= "string" then
    error("bad argument #1 to 'utf8replace' (string expected, got " .. type(s) .. ")")
  end
  if type(mapping) ~= "table" then
    error("bad argument #2 to 'utf8replace' (table expected, got " .. type(mapping) .. ")")
  end
  --local result = utf8.raw.gsub(s, utf8charpattern, mapping)
  local result = string.gsub(s, utf8charpattern, mapping)
  return result
end
--[[
local function utf8upper (s)
  return utf8replace(s, config.conversion.lc_uc)
end

if config.conversion.lc_uc then
  upper = utf8upper
end

local function utf8lower (s)
  return utf8replace(s, config.conversion.uc_lc)
end

if config.conversion.uc_lc then
  lower = utf8lower
end
--]]
utf8.len         = utf8len
utf8.sub         = utf8sub
utf8.reverse     = utf8reverse
utf8.char        = utf8char
utf8.unicode     = utf8unicode
utf8.byte        = utf8byte
utf8.next        = utf8next
utf8.gensub      = utf8gensub
utf8.validator   = utf8validator
utf8.validate    = utf8validate
utf8.dump        = dump
utf8.format      = format
utf8.lower       = lower
utf8.upper       = upper
utf8.rep         = rep
--utf8.raw         = {}
--for k,v in pairs(string) do
--  utf8.raw[k] = v
--end

utf8.charpattern = utf8charpattern
utf8.offset      = utf8offset
if _VERSION == 'Lua 5.3' then
  local utf8_53 = require "utf8"
  utf8.codes = utf8_53.codes
  utf8.codepoint = utf8_53.codepoint
  utf8.len53 = utf8_53.len
else
  utf8.codes = utf8codes
  utf8.codepoint = utf8unicode
end

return utf8

--end

end
return (function()
-- {"id":711,"ver":"1.0.1","libVer":"1.0.0","author":"Rider21","dep":["dkjson>=1.0.1", "utf8>=1.0.0"]}

local baseURL = "https://ruvers.ru"
local json = Require("dkjson")
local utf8 = Require("utf8")

local SORT_BY_FILTER = 3
local SORT_BY_VALUES = { "По названию", "По дате добавления", "По рейтингу" }
local SORT_BY_TERMS = { "name", "-created_at", "-rating" }

local function unescapeUnicode(escapedString)
	-- This function takes a string with escaped Unicode characters (e.g., "\u0061")
	-- and returns the unescaped string.

	-- `string.gsub` replaces all occurrences of the pattern `\\u(%x%x%x%x)` with the result of the provided function.
	-- `\\u(%x%x%x%x)` matches a Unicode escape sequence like `\u0061`.
	-- The parentheses capture the hexadecimal code (`%x%x%x%x`).

	return (string.gsub(escapedString, "\\u(%x%x%x%x)", function(hexCode)
		-- `tonumber(hexCode, 16)` converts the hexadecimal code to a decimal number.
		-- `utf8.char` converts the decimal number to a UTF-8 character.
		return utf8.char(tonumber(hexCode, 16))
	end))
end

local function shrinkURL(url)
	return url:gsub(baseURL .. "/", "")
end

local function expandURL(url)
	return baseURL .. "/" .. url
end

local function getSearch(data)
	local url = baseURL .. "/api/books?page=" .. data[PAGE] ..
		"&sort=" .. SORT_BY_TERMS[data[SORT_BY_FILTER] + 1]

	if data[0] then --search
		url = url .. "&search=" .. data[0]
	end

	local response = json.GET(url)

	return map(response.data, function(v)
		return Novel {
			title = v.name,
			link = v.slug,
			imageURL = expandURL(v.images[1])
		}
	end)
end

local function getPassage(chapterURL)
	local doc = GETDocument(expandURL(chapterURL))
	local chap = doc:select(
		".chapter_text > books-chapters-text-component, .chapter_text > mobile-books-chapters-text-component")

	local chapterNumber = doc:select(
	".info > books-chapters-select-component, mobile-books-chapters-select-component"):attr("chapter-number")

	local chapterTitle = "<h1>Глава " .. chapterNumber .. "</h1>";
	local chapterText = unescapeUnicode(chap:attr(":text"):sub(2, -2))

	return pageOfElem(Document(chapterTitle .. chapterText))
end

local function parseNovel(novelURL, loadChapters)
	local response = GETDocument(expandURL(novelURL))

	local novel = NovelInfo {
		title = response:select("div.name > h1"):text(),
		genres = map(response:select(".genres > a"), function(genres) return genres:text() end),
		imageURL = response:select(".slider_prods_single > img"):attr("src"),
		description = response:select(".book_description"):text(),
	}

	local status = response:select(".status_row > div:nth-child(1) > a"):text()
	if status == "В работе" then
		novel:setStatus(NovelStatus.PUBLISHING)
	elseif status == "Завершено" then
		novel:setStatus(NovelStatus.COMPLETED)
	end

	if loadChapters then
		local bookId = response:select("comments-list"):attr("commentable-id");
		local chapterJson = json.GET(baseURL .. "/api/books/" .. bookId .. "/chapters/all")
		local chapterList = {}
		for k, v in pairs(chapterJson.data) do
			if v.is_published and (v.is_free or v.purchased_by_user) then
				table.insert(chapterList, NovelChapter {
					title = "Глава " .. v.number .. " " .. (v.name or ""),
					link = novelURL .. "/" .. v.id,
					release = v.created_at,
					order = k
				});
			end
		end
		novel:setChapters(AsList(chapterList))
	end
	return novel
end

return {
	id = 711,
	name = "Ruvers",
	baseURL = baseURL,
	imageURL = "https://ruvers.ru/img/favicon/apple-touch-icon.png",
	chapterType = ChapterType.HTML,

	listings = {
		Listing("Novel List", true, function(data)
			return getSearch(data)
		end)
	},

	getPassage = getPassage,
	parseNovel = parseNovel,

	hasSearch = true,
	isSearchIncrementing = true,
	search = getSearch,
	searchFilters = {
		DropdownFilter(SORT_BY_FILTER, "Сортировка", SORT_BY_VALUES),
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,
}

end)()