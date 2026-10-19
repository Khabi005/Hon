-- Bundled from https://raw.githubusercontent.com/noaione/shosetsu-extensions/repo/; original sources retained in third_party/shosetsu.
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
__modules["Multipartd"] = function()
-- {"ver":"1.0.0","author":"N4O"}

-- A helper to create a multipart/form-data request

local Multipartd = {}
Multipartd.__index = Multipartd

--- Generate a random boundary for multipart form data.
--- @return string
local function generateBoundary()
	-- create custom boundary
	local boundary = ""
	for _ = 1, 30 do
		-- use number
		boundary = boundary .. string.char(math.random(48, 57))
	end
	return boundary
end


--- Create a multipart/form-data request.
--- @param data table
--- @return Multipartd
function Multipartd:new()
    local multipartd = {}
    setmetatable(multipartd, Multipartd)
    multipartd.boundary = "-----------------------------" .. generateBoundary()
    multipartd.formData = ""
    return multipartd
end

--- Add a field to the form data.
--- @param name string
--- @param value string
function Multipartd:add(name, value)
    self.formData = self.formData .. self.boundary .. "\r\n"
    self.formData = self.formData .. 'Content-Disposition: form-data; name="' .. name .. '"\r\n'
    self.formData = self.formData .. "\r\n"
    self.formData = self.formData .. value .. "\r\n"
end

--- Build the form data.
--- @return string
function Multipartd:build()
    return self.formData .. self.boundary .. "--\r\n"
end

function Multipartd:reset()
    self.boundary = "-----------------------------" .. generateBoundary()
    self.formData = ""
end

function Multipartd:getHeader()
    local boundarySub = self.boundary:sub(3)
    return "multipart/form-data; boundary=" .. boundarySub
end

return Multipartd

end
__modules["WPCommon"] = function()
-- {"ver":"1.0.3","author":"N4O"}

-- A common function collection for WordPress based websites.

local WPCommon = {}

--- @param str string
--- @param pattern string
local function contains(str, pattern)
    return str:find(pattern, 0, true) and true or false
end

WPCommon.contains = contains

--- @param testString string
--- @return boolean
function WPCommon.isTocRelated(testString)
    local upperText = testString:upper()
    -- ToC
    if contains(upperText, "TOC") or contains(upperText, "TABLE OF CONTENT") or contains(upperText, "TABLE OF CONTENTS") then
        return true
    end
    -- Index/Main
    if contains(upperText, "MAIN PAGE") or contains(upperText, "INDEX") then
        return true
    end
    -- Previous
    if contains(upperText, "PREVIOUS CHAPTER") or contains(upperText, "PREVIOUS") then
        return true
    end
    -- Next
    if contains(upperText, "NEXT CHAPTER") or contains(upperText, "NEXT") then
        return true
    end
    return false
end

--- @param element Element
--- @return boolean isRemoved
function WPCommon.cleanupElement(element)
    local jpFlair = element:selectFirst("#jp-post-flair")
    if jpFlair then jpFlair:remove() end
    local darkSwitch = element:selectFirst(".wp-dark-mode-switcher")
    if darkSwitch then darkSwitch:remove() end
    local shareFlair = contains(element:id(), "jp-post-flair")
    if shareFlair then
        shareFlair:remove()
        return true
    end
    local ataTags = contains(element:id(), "atatags")
    if ataTags then
        element:remove()
        return true
    end
    local className = element:attr("class")
    local patreonBtn = contains(className, "patreon")
    local postNav = contains(className, "wp-post-nav")
    local wpuLikeBtn = contains(className, "wpulike")
    local shareDaddy = contains(className, "sharedaddy")
    if patreonBtn or postNav or wpuLikeBtn or shareDaddy then
        element:remove()
        return true
    end
    return false
end

--- @param elements Elements
--- @param tocCenter boolean
function WPCommon.cleanupPassages(elements, tocCenter)
    map(elements, function (v)
        local isRemoved = WPCommon.cleanupElement(v)
        if isRemoved then return end
        local style = v:attr("style")
        local isAlignCenter = style and style:find("text-align", 0, true) and style:find("center", 0, true) and true or false
        local isValidTocData = WPCommon.isTocRelated(v:text())
        if tocCenter and isAlignCenter and isValidTocData then
            return v:remove()
        elseif not tocCenter and isValidTocData then
            return v:remove()
        end
    end)
end

--- Split a string by a separator into a table.
--- https://stackoverflow.com/a/7615129
--- @param inputStr string
--- @param sep string
--- @return table
local function splitString(inputStr, sep)
    if sep == nil then
            sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputStr, "([^"..sep.."]+)") do
            table.insert(t, str)
    end
    return t
end


--- @param styleData string
--- @return table
function WPCommon.createStyleMap(styleData)
    if styleData:len() == 0 then return {} end
    -- replace "; " with ";"
    styleData = styleData:gsub("; ", ";")
    -- split by ";"
    local styleDataSplit = splitString(styleData, ";")
    local styleDataMap = {}
    for _, v in ipairs(styleDataSplit) do
        -- manual split, find ":" first occurence
        local firstColon = v:find(":", 0, true)
        local key = v:sub(0, firstColon - 1)
        local value = v:sub(firstColon + 1)
        -- strip leading and trailing spaces
        key = key:gsub("^%s*(.-)%s*$", "%1")
        value = value:gsub("^%s*(.-)%s*$", "%1")
        styleDataMap[key] = value
    end
    return styleDataMap
end

--- @param styleData string
--- @param key string
--- @return string|nil
function WPCommon.getSpecificStyleAttribute(styleData, key)
    local styleDataMap = WPCommon.createStyleMap(styleData)
    return styleDataMap[key]
end


return WPCommon;

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
-- {"id":4302,"ver":"2.1.8","libVer":"1.0.0","author":"N4O","dep":["dkjson>=1.0.1","Multipartd>=1.0.0","WPCommon>=1.0.3"]}

local json = Require("dkjson");
local Multipartd = Require("Multipartd");
local WPCommon = Require("WPCommon");

local baseURL = "https://storyseedling.com"

local globalState = {}

-- Filter Keys & Values
local STATUS_FILTER = 2
local STATUS_VALUES = { "All", "Ongoing", "Completed" }
local ORDER_BY_FILTER = 3
local ORDER_BY_VALUES = { "Recently Added", "Latest Update", "Random" }
local ORDER_BY_TERMS = { "recent", "latest", "random" }
local GENRE_FILTER = 50
-- To update, paste the following code in Firefox's console while on the search page:
--
-- term_items = temp0.querySelectorAll(".term_item")
-- merged_data = []
-- for (let i = 0; i < temp0.children.length; i++) {
-- 	let child = temp0.children[i];
-- 	let clickState = child.getAttribute("@click").replace("genreState(", "").replace(")", "")
-- 	let genreName = child.querySelector("span").textContent
-- 	merged_data.push(`${genreName}: ${clickState}`)
-- }
-- '"' + merged_data.join(`\",\n\"`) + '"'
--
-- The temp0 can be fetched by right-clicking `flex flex-wrap mt-2` part of the Genre wrapper
-- and Selecting "Show in Console"
-- This is just a quick and dirty way to quickly update the genres.
local GENRE_VALUES = { 
    "Action: 111",
    "Adult: 183",
    "Adventure: 112",
    "BL: 207",
    "Comedy: 153",
    "Drama: 115",
    "Ecchi: 170",
    "Fantasy: 114",
    "Harem: 956",
    "Historical: 178",
    "Horror: 254",
    "Josei: 472",
    "Martial Arts: 1329",
    "Mature: 427",
    "Mecha: 1481",
    "Mystery: 645",
    "Psychological: 515",
    "Reincarnation: 1031",
    "Romance: 108",
    "School Life: 545",
    "Sci-Fi: 113",
    "Seinen: 708",
    "Shoujo: 228",
    "Shoujo Ai: 1403",
    "Shounen: 246",
    "Shounen Ai: 718",
    "Slice of Life: 157",
    "Smut: 736",
    "Sports: 966",
    "Supernatural: 995",
    "Tragedy: 985",
    "Xianxia: 245",
    "Xuanhuan: 428",
    "Yaoi: 184",
    "Yuri: 182",
}


local searchFilters = {
    DropdownFilter(ORDER_BY_FILTER, "Order by", ORDER_BY_VALUES),
    DropdownFilter(STATUS_FILTER, "Status", STATUS_VALUES),
    FilterGroup("Genre", map(GENRE_VALUES, function(v, i) 
        local KEY_ID = GENRE_FILTER + i
        local key, _ = v:match("^(.-):%s*(.-)$")
        return TriStateFilter(KEY_ID, key)
    end))
}

local function shrinkURL(url)
    return url:gsub("^.-storyseedling%.com", "")
end

local function expandURL(url)
    return baseURL .. url
end

--- @param seriesUrl string
local function rewriteSeriesUrl(seriesUrl)
    -- rewrite from /novel/12345/series-slug
    -- into: /series/12345
    return seriesUrl:gsub("/novel/(%d+)/.*", "/series/%1")
end

--- Rewrite old chapter URLs to new ones
--- @param chapterUrl string
local function rewriteChapterUrl(chapterUrl)
    -- rewrite the following variants:
    -- - /novel/12345/series-slug/chapter-X => /series/12345/X
    -- - /novel/12345/series-slug/chapter-X-Z => /series/12345/X.Z
    -- - /novel/12345/series-slug/chapter-X (extra data) => /series/12345/X (extra data)
    -- - /novel/12345/series-slug/chapter-X-Z (extra data) => /series/12345/X.Z (extra data)
    -- - /novel/12345/series-slug/volume-X-chapter-Y => /series/12345/vX/Y
    -- - /novel/12345/series-slug/volume-X-chapter-Y-Z => /series/12345/vX/Y.Z

    local matches = {
        chapterUrl:match("/novel/(%d+)/([^/]+)/chapter-(%d+)([^/]*)$"),
        chapterUrl:match("/novel/(%d+)/([^/]+)/volume-(%d+)-chapter-(%d+)([^/]*)$")
    }

    if matches[1] then
        local novelId = matches[1]
        local chapterNum = matches[3]
        local extraData = matches[4] or ""
        return "/series/" .. novelId .. "/" .. chapterNum .. extraData
    elseif matches[4] then
        local novelId = matches[2]
        local volume = "v" .. matches[4]
        local chapterNum = matches[5]
        local extraData = matches[6] or ""
        return "/series/" .. novelId .. "/" .. volume .. "/" .. chapterNum .. extraData
    else
        -- Return original URL if no matches found
        return chapterUrl
    end   
end

--- @param webpage Document
local function getsn(webpage)
    local axLoad = webpage:selectFirst("div[ax-load]")
    local xData = axLoad:attr("x-data")
    local s, n = xData:match("loadChapter%('([^']+)', '([^']+)'%)")
    return s, n
end

--- @param chapterUrl string
--- @return Document
local function requestPassageInformation(chapterUrl)
    local chapterPage = expandURL(rewriteChapterUrl(chapterUrl))

    local mainPage = GETDocument(chapterPage)

    local s, n = getsn(mainPage)
    print("StorySeedling Random Passage Data:", s, n)

    local headers = HeadersBuilder()
    headers:add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/129.0")
    headers:add("Origin", "https://storyseedling.com")
    headers:add("Referer", chapterPage)
    headers:add("X-Nonce", n)

    -- create table of JSON data
    local jsonData = {
        captcha_response = "",
    }
    local reqData = json.encode(jsonData);

    local res = Request(POST(
        chapterPage .. "/content",
        headers:build(),
        RequestBody(reqData, MediaType("application/json"))
    ))

    local htmlData = res:body():string()

    if res:code() ~= 200 then
        error("Status code is not 200, received " .. res:code());
    end

    if res:headers():get("Content-Type"):sub(1, 16) == "application/json" then
        error("Received JSON response instead of HTML, possible Captcha");
    end

    local doc = Document(htmlData)

    return doc
end

local subLower = 12027
local subUpper = 12033

local minLower = 12124
local maxLower = 12149
local minUpper = 12098
local maxUpper = 12123

local function utf8ToCodepoint(char)
    local byte1, byte2, byte3, byte4 = string.byte(char, 1, 4)
    if not byte2 then return byte1 end
    if not byte3 then return (byte1 - 0xC0) * 0x40 + (byte2 - 0x80) end
    if not byte4 then return (byte1 - 0xE0) * 0x1000 + (byte2 - 0x80) * 0x40 + (byte3 - 0x80) end
    return (byte1 - 0xF0) * 0x40000 + (byte2 - 0x80) * 0x1000 + (byte3 - 0x80) * 0x40 + (byte4 - 0x80)
end

local function wideCharLikeUnrot(utf8str)
    -- loop through all characters in the string
    -- and apply ROT13
    local merge = ""
    for char in utf8str:gmatch("[\0-\x7F\xC2-\xF4][\x80-\xBF]*") do
        local codepoint = utf8ToCodepoint(char)
        if codepoint >= minLower and codepoint <= maxLower then
            -- subtract codepoint with subLower
            merge = merge .. string.char(codepoint - subLower)
        -- check if in upper range (minUpper and maxUpper)
        elseif codepoint >= minUpper and codepoint <= maxUpper then
            -- subtract codepoint with subUpper
            merge = merge .. string.char(codepoint - subUpper)
        else
            merge = merge .. char
        end
    end
    return merge
end

local function isFuckingGarbage(text)
    -- "Copyrighted sentence owned by Story Seedling", lol lmao even, kys.
    if WPCommon.contains(text:lower(), "storyseedling") then
        return true
    end
    if WPCommon.contains(text:lower(), "story seedling") then
        return true
    end
    if WPCommon.contains(text:lower(), "storyseedling.com") then
        return true
    end
    if WPCommon.contains(text:lower(), "travis translation") then
        return true
    end
    return false
end

local function getPassage(chapterURL)
    local chap = requestPassageInformation(chapterURL)

    -- remove styles
    local style = chap:selectFirst("style")
    if style then
        style:remove()
    end

    -- unrot all <p> instance
    local body = chap:body()
    map(body:select("p"), function (p)
        local toBeRemoved = {}
        local firstOccurence = false
        for i = 0, p:childNodeSize() - 1 do
            local child = p:childNode(i)
            if child:nodeName() == "#comment" then
                goto continue
            end
            local text = child:text()

            if WPCommon.contains(text, "⽔⽯⽪⽭⽴ ⽔⽠⽠⽟⽧⽤⽩⽢") or WPCommon.contains(text, "⽮⽯⽪⽭⽴⽮⽠⽠⽟⽧⽤⽩⽢") then
                -- useless
                toBeRemoved[#toBeRemoved + 1] = child
                -- continue loop
                goto continue
            end

            -- check if starts with cls and 21 characters
            if text:sub(1, 3) == "cls" and text:len() == 21 then
                toBeRemoved[#toBeRemoved + 1] = child
                goto continue
            end

            local unrotted = wideCharLikeUnrot(text)
            -- strip whitespace
            unrotted = unrotted:gsub("^%s*(.-)%s*$", "%1")

            if not firstOccurence then
                firstOccurence = true
                child:text(unrotted)
            else
                child:text(" " .. unrotted)
            end

            ::continue::
        end
        for i = #toBeRemoved, 1, -1 do
            toBeRemoved[i]:remove()
        end
    end)

    return pageOfElem(chap, true)
end

--- @param description Element
local function formatDescription(description)
    local synopsis = ""
    local totalNodes = description:childNodeSize()
    for i = 0, totalNodes - 1 do
        local node = description:childNode(i)
        -- jsoup node, get node type
        if node == nil then
            break
        end
        if node:nodeName() == "#comment" then
            -- continue
            goto continue
        end
        local textData = node:text():gsub("^%s*(.-)%s*$", "%1")
        synopsis = synopsis .. textData .. "\n"
        ::continue::
    end
    return synopsis:gsub("\n+$", ""):gsub("%s+$", "")
end


--- @param webpage Document
local function getPostId(webpage)
    local axLoad = webpage:selectFirst("div[ax-load]")
    local xData = axLoad:attr("x-data")
    -- toc('PostID', 'randomData'), get the post ID and random data
    local postId, randomData = xData:match("toc%('([^']+)', '([^']+)'%)")
    return postId, randomData
end


--- @param novelId string
--- @param randomData string
--- @return table
local function getChapterList(novelId, randomData)
    -- build form
    local formBuilder = Multipartd:new()
    formBuilder:add("post", randomData)
    formBuilder:add("id", novelId)
    formBuilder:add("action", "series_toc")

    -- for media type, cut off the first two dashes
    local headers = HeadersBuilder()
    headers:add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/129.0")
    headers:add("Origin", "https://storyseedling.com")
    headers:add("Referer", "https://storyseedling.com/series" .. novelId .. "/")
    
    local build = formBuilder:build()
    headers:add("Content-Type", formBuilder:getHeader())

    local resp = Request(POST(
        expandURL("/ajax"),
        headers:build(),
        RequestBody(build, MediaType(formBuilder:getHeader()))
    ))

    -- json response
    local body = resp:body():string()
    local jsonData = json.decode(body)
    return jsonData.data
end

local function getStatusFromText(text)
    if WPCommon.contains(text, "Ongoing") then
        return NovelStatus.PUBLISHING
    elseif WPCommon.contains(text, "Completed") then
        return NovelStatus.COMPLETED
    elseif WPCommon.contains(text, "Dropped") then
        return NovelStatus.PAUSED
    elseif WPCommon.contains(text, "Hiatus") then
        return NovelStatus.PAUSED
    elseif WPCommon.contains(text, "Cancelled") then
        return NovelStatus.PAUSED
    end
    return NovelStatus(-1)
end

local function parseNovel(novelURL, loadChapters)
    local doc = GETDocument(expandURL(rewriteSeriesUrl(novelURL)))
    local content = doc:selectFirst("main")

    local chapterSelector = content:selectFirst("section[x-data]")
    local gridInInfo = chapterSelector:selectFirst(".lg\\:grid-in-info")
    local gridInContent = chapterSelector:selectFirst(".lg\\:grid-in-content")
    
    local info = NovelInfo {
        title = content:selectFirst("h1.text-2xl"):text(),
        imageURL = content:selectFirst("div.bg-blur"):selectFirst("img"):attr("src"),
        description = formatDescription(gridInContent:selectFirst(".order-2")),
        artists = { "Translator: Story Seedling" },
        genres = map(gridInInfo:select("a[up-deprecated]"), function(v) return v:text() end),
    }

    -- <div class="flex items-center gap-2">
    local firstGridInInfo = content:selectFirst(".lg\\:grid-in-info")
    if firstGridInInfo then
        local status = firstGridInInfo:selectFirst("div.items-center")
        if status then
            local statusDetail = status:selectFirst(".text-sm")
            if statusDetail then
                local statusText = statusDetail:text()
                info:setStatus(getStatusFromText(statusText))
            end
        end
    end

    if loadChapters then
        local novelId, randomData = getPostId(doc)
        print("StorySeedling Random Series Data:", novelId, randomData)
        local chaptersList = getChapterList(novelId, randomData)
        local _chapters = {}
        --- Chapter is ascending order 1 to N
        for i = 1, #chaptersList do
            local v = chaptersList[i]
            if not v.is_locked then
                _chapters[#_chapters + 1] = NovelChapter {
                    order = i,
                    title = v.title,
                    link = shrinkURL(v.url),
                    release = v.date
                }
            end
        end

        info:setChapters(AsList(_chapters))
    end
    return info
end

--- @param listing table
local function parseListing(listing)
    return map(listing.data.posts, function(v)
        return Novel {
            title = v.title,
            link = shrinkURL(v.permalink),
            imageURL = v.thumbnail,
        }
    end)
end

local function getPostData()
    if globalState.postData then
        return globalState.postData
    end

    local webpage = GETDocument(expandURL("/browse/"))

    local axLoad = webpage:selectFirst("div[ax-load]")
    local xData = axLoad:attr("x-data")
    -- browse('RANDOMDATAHERE'), get the random data
    local randomData = xData:match("browse%('([^']+)'%)")

    globalState.postData = randomData

    return randomData
end

local function getSearch(data)
    local query = data[QUERY]
    local page = data[PAGE]
    local orderBy = data[ORDER_BY_FILTER]

    -- get the random data
    local randomData = getPostData()
    print("StorySeedling Random Data:", randomData)

    -- build form
    local formBuilder = Multipartd:new()
    formBuilder:add("search", query or "")

    map(GENRE_VALUES, function(v, i)
        local KEY_ID = GENRE_FILTER + i
        local _, value = v:match("^(.-):%s*(.-)$")
        if data[KEY_ID] == 1 then
            formBuilder:add("includeGenres[]", value)
        elseif data[KEY_ID] == 2 then
            formBuilder:add("excludeGenres[]", value)
        end
    end)

    if orderBy ~= nil then
        formBuilder:add("orderBy", ORDER_BY_TERMS[orderBy + 1])
    else
        formBuilder:add("orderBy", "recent")
    end

    if page > 1 then
        formBuilder:add("curpage", tostring(page))
    end

    formBuilder:add("post", randomData)
    formBuilder:add("action", "fetch_browse")

    -- for media type, cut off the first two dashes
    local headers = HeadersBuilder()
    headers:add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/129.0")
    headers:add("Origin", "https://storyseedling.com")
    headers:add("Referer", "https://storyseedling.com/browse")

    local resp = Request(POST(
        expandURL("/ajax"),
        headers:build(),
        RequestBody(formBuilder:build(), MediaType(formBuilder:getHeader()))
    ))

    -- json response
    local body = resp:body():string()
    local jsonData = json.decode(body)
    return parseListing(jsonData)
end

local function getListing(data)
    return getSearch(data)
end

return {
    id = 4302,
    name = "Story Seedling",
    baseURL = baseURL,
    imageURL = "https://github.com/shosetsuorg/extensions/raw/dev/icons/TravisTranslations.png",
    chapterType = ChapterType.HTML,

    listings = {
        Listing("Latest", true, getListing)
    },
    getPassage = getPassage,
    parseNovel = parseNovel,

    hasSearch = true,
    isSearchIncrementing = true,
    search = getSearch,
    searchFilters = searchFilters,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()