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
__modules["MDLua"] = function()
-- {"ver":"1.0.0","author":"Calvin Rose"}

--[[
Copyright (c) 2016 Calvin Rose <calsrose@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local concat = table.concat
local sub = string.sub
local match = string.match
local format = string.format
local gmatch = string.gmatch
local byte = string.byte
local find = string.find
local lower = string.lower
local tonumber = tonumber -- luacheck: no unused
local type = type
local pcall = pcall

--------------------------------------------------------------------------------
-- Stream Utils
--------------------------------------------------------------------------------

local function stringLineStream(str)
    return gmatch(str, "([^\n\r]*)\r?\n?")
end

local function tableLineStream(t)
    local index = 0
    return function()
        index = index + 1
        return t[index]
    end
end

local function bufferStream(linestream)
    local bufferedLine = linestream()
    return function()
        bufferedLine = linestream()
        return bufferedLine
    end, function()
        return bufferedLine
    end
end

--------------------------------------------------------------------------------
-- Line Level Operations
--------------------------------------------------------------------------------

local lineDelimiters = {'`', '__', '**', '_', '*', '~~'}
local function findDelim(str, start, max)
    local delim = nil
    local min = 1/0
    local finish = 1/0
    max = max or #str
    for i = 1, #lineDelimiters do
        local pos, fin = find(str, lineDelimiters[i], start, true)
        if pos and pos < min and pos <= max then
            min = pos
            finish = fin
            delim = lineDelimiters[i]
        end
    end
    return delim, min, finish
end

local function externalLinkEscape(str, t)
    local nomatches = true
    for m1, m2, m3 in gmatch(str, '(.*)%[(.*)%](.*)') do
        if nomatches then t[#t + 1] = match(m1, '^(.-)!?$'); nomatches = false end
        if byte(m1, #m1) == byte '!' then
            t[#t + 1] = {type = 'img', attributes = {alt = m2}}
        else
            t[#t + 1] = {m2, type = 'a'}
        end
        t[#t + 1] = m3
    end
    if nomatches then t[#t + 1] = str end
end

local function linkEscape(str, t)
    local nomatches = true
    for m1, m2, m3, m4 in gmatch(str, '(.*)%[(.*)%]%((.*)%)(.*)') do
        if nomatches then externalLinkEscape(match(m1, '^(.-)!?$'), t); nomatches = false end
        if byte(m1, #m1) == byte '!' then
            t[#t + 1] = {type = 'img', attributes = {
                src = m3,
                alt = m2
            }, noclose = true}
        else
            t[#t + 1] = {m2, type = 'a', attributes = {href = m3}}
        end
        externalLinkEscape(m4, t)
    end
    if nomatches then externalLinkEscape(str, t) end
end

local lineDeimiterNames = {['`'] = 'code', ['__'] = 'strong', ['**'] = 'strong', ['_'] = 'em', ['*'] = 'em', ['~~'] = 'strike' }
local function lineRead(str, start, finish)
    start, finish = start or 1, finish or #str
    local searchIndex = start
    local tree = {}
    while true do
        local delim, dstart, dfinish = findDelim(str, searchIndex, finish)
        if not delim then
            linkEscape(sub(str, searchIndex, finish), tree)
            break
        end
        if dstart > searchIndex then
            linkEscape(sub(str, searchIndex, dstart - 1), tree)
        end
        local nextdstart, nextdfinish = find(str, delim, dfinish + 1, true)
        if nextdstart then
            if delim == '`' then
                tree[#tree + 1]  = {
                    sub(str, dfinish + 1, nextdstart - 1),
                    type = 'code'
                }
            else
                local subtree = lineRead(str, dfinish + 1, nextdstart - 1)
                subtree.type = lineDeimiterNames[delim]
                tree[#tree + 1] = subtree
            end
            searchIndex = nextdfinish + 1
        else
            tree[#tree + 1]  = {
                delim,
            }
            searchIndex = dfinish + 1
        end
    end
    return tree
end

local function getIndentLevel(line)
    local level = 0
    for i = 1, #line do
        local b = byte(line, i)
        if b == byte(' ') or b == byte('>') then
            level = level + 1
        elseif b == byte('\t') then
            level = level + 4
        else
            break
        end
    end
    return level
end

local function stripIndent(line, level, ignorepattern) -- luacheck: no unused args
    local currentLevel = -1
    for i = 1, #line do
        if byte(line, i) == byte("\t") then
            currentLevel = currentLevel + 4
        elseif byte(line, i) == byte(" ") or byte(line, i) == byte(">") then
            currentLevel = currentLevel + 1
        else
            return sub(line, i, -1)
        end
        if currentLevel == level then
            return sub(line, i, -1)
        elseif currentLevel > level then
            local front = ""
            for j = 1, currentLevel - level do front = front .. " " end -- luacheck: no unused args
            return front .. sub(line, i, -1)
        end
    end
end

--------------------------------------------------------------------------------
-- Useful variables
--------------------------------------------------------------------------------
local NEWLINE = '\n'

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

local PATTERN_EMPTY = "^%s*$"
local PATTERN_COMMENT = "^%s*<>"
local PATTERN_HEADER = "^%s*(%#+)%s*(.*)%#*$"
local PATTERN_RULE1 = "^%s?%s?%s?(-%s*-%s*-[%s-]*)$"
local PATTERN_RULE2 = "^%s?%s?%s?(*%s**%s**[%s*]*)$"
local PATTERN_RULE3 = "^%s?%s?%s?(_%s*_%s*_[%s_]*)$"
local PATTERN_CODEBLOCK = "^%s*%`%`%`(.*)"
local PATTERN_BLOCKQUOTE = "^%s*> (.*)$"
local PATTERN_ULIST = "^%s*[%*%-] (.+)$"
local PATTERN_OLIST = "^%s*%d+%. (.+)$"
local PATTERN_LINKDEF = "^%s*%[(.*)%]%s*%:%s*(.*)"

-- List of patterns
local PATTERNS = {
    PATTERN_EMPTY,
    PATTERN_COMMENT,
    PATTERN_HEADER,
    PATTERN_RULE1,
    PATTERN_RULE2,
    PATTERN_RULE3,
    PATTERN_CODEBLOCK,
    PATTERN_BLOCKQUOTE,
    PATTERN_ULIST,
    PATTERN_OLIST,
    PATTERN_LINKDEF
}

local function isSpecialLine(line)
    for i = 1, #PATTERNS do
        if match(line, PATTERNS[i]) then return PATTERNS[i] end
    end
end

--------------------------------------------------------------------------------
-- Simple Reading - Non Recursive
--------------------------------------------------------------------------------

local function readSimple(pop, peek, tree, links)

    local line = peek()
    if not line then return end

    -- Test for Empty or Comment
    if match(line, PATTERN_EMPTY) or match(line, PATTERN_COMMENT) then
        return pop()
    end

    -- Test for Header
    local m, rest = match(line, PATTERN_HEADER)
    if m then
        tree[#tree + 1] = {
            lineRead(rest),
            type = "h" .. #m
        }
        tree[#tree + 1] = NEWLINE
        return pop()
    end

    -- Test for Horizontal Rule
    if match(line, PATTERN_RULE1) or
       match(line, PATTERN_RULE2) or
       match(line, PATTERN_RULE3) then
        tree[#tree + 1] = { type = "hr", noclose = true }
        tree[#tree + 1] = NEWLINE
        return pop()
    end

    -- Test for Code Block
    local syntax = match(line, PATTERN_CODEBLOCK)
    if syntax then
        local indent = getIndentLevel(line)
        local code = {
            type = "code"
        }
        if #syntax > 0 then
            code.attributes = {
                class = format('language-%s', lower(syntax))
            }
        end
        local pre = {
            type = "pre",
            [1] = code
        }
        tree[#tree + 1] = pre
        while not (match(pop(), PATTERN_CODEBLOCK) and getIndentLevel(peek()) == indent) do
            code[#code + 1] = peek()
            code[#code + 1] = '\r\n'
        end
        return pop()
    end

    -- Test for link definition
    local linkname, location = match(line, PATTERN_LINKDEF)
    if linkname then
        links[lower(linkname)] = location
        return pop()
    end

    -- Test for header type two
    local nextLine = pop()
    if nextLine and match(nextLine, "^%s*%=+$") then
        tree[#tree + 1] = { lineRead(line), type = "h1" }
        return pop()
    elseif nextLine and match(nextLine, "^%s*%-+$") then
        tree[#tree + 1] = { lineRead(line), type = "h2" }
        return pop()
    end

    -- Do Paragraph
    local p = {
        lineRead(line), NEWLINE,
        type = "p"
    }
    tree[#tree + 1] = p
    while nextLine and not isSpecialLine(nextLine) do
        p[#p + 1] = lineRead(nextLine)
        p[#p + 1] = NEWLINE
        nextLine = pop()
    end
    p[#p] = nil
    tree[#tree + 1] = NEWLINE
    return peek()

end

--------------------------------------------------------------------------------
-- Main Reading - Potentially Recursive
--------------------------------------------------------------------------------

local readLineStream

local function readFragment(pop, peek, links, stop, ...)
    local accum2 = {}
    local line = peek()
    local indent = getIndentLevel(line)
    while true do
        accum2[#accum2 + 1] = stripIndent(line, indent)
        line = pop()
        if not line then break end
        if stop(line, ...) then break end
    end
    local tree = {}
    readLineStream(tableLineStream(accum2), tree, links)
    return tree
end

local function readBlockQuote(pop, peek, tree, links)
    local line = peek()
    if match(line, PATTERN_BLOCKQUOTE) then
        local bq = readFragment(pop, peek, links, function(l)
            local tp = isSpecialLine(l)
            return tp and tp ~= PATTERN_BLOCKQUOTE
        end)
        bq.type = 'blockquote'
        tree[#tree + 1] = bq
        return peek()
    end
end

local function readList(pop, peek, tree, links, expectedIndent)
    if not peek() then return end
    if expectedIndent and getIndentLevel(peek()) ~= expectedIndent then return end
    local listPattern = (match(peek(), PATTERN_ULIST) and PATTERN_ULIST) or
                        (match(peek(), PATTERN_OLIST) and PATTERN_OLIST)
    if not listPattern then return end
    local lineType = listPattern
    local line = peek()
    local indent = getIndentLevel(line)
    local list = {
        type = (listPattern == PATTERN_ULIST and "ul" or "ol")
    }
    tree[#tree + 1] = list
    list[1] = NEWLINE
    while lineType == listPattern do
        list[#list + 1] = {
            lineRead(match(line, lineType)),
            type = "li"
        }
        line = pop()
        if not line then break end
        lineType = isSpecialLine(line)
        if lineType ~= PATTERN_EMPTY then
            list[#list + 1] = NEWLINE
            local i = getIndentLevel(line)
            if i < indent then break end
            if i > indent then
                local subtree = readFragment(pop, peek, links, function(l)
                    if not l then return true end
                    local tp = isSpecialLine(l)
                    return tp ~= PATTERN_EMPTY and getIndentLevel(l) < i
                end)
                list[#list + 1] = subtree
                line = peek()
                if not line then break end
                lineType = isSpecialLine(line)
            end
        end
    end
    list[#list + 1] = NEWLINE
    tree[#tree + 1] = NEWLINE
    return peek()
end

function readLineStream(stream, tree, links)
    local pop, peek = bufferStream(stream)
    tree = tree or {}
    links = links or {}
    while peek() do
        if not readBlockQuote(pop, peek, tree, links) then
            if not readList(pop, peek, tree, links) then
                readSimple(pop, peek, tree, links)
            end
        end
    end
    return tree, links
end

local function read(str) -- luacheck: no unused
    return readLineStream(stringLineStream(str))
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function renderAttributes(attributes)
    local accum = {}
    for k, v in pairs(attributes) do
        accum[#accum + 1] = format("%s=\"%s\"", k, v)
    end
    return concat(accum, ' ')
end

local function renderTree(tree, links, accum)
    if tree.type then
        local attribs = tree.attributes or {}
        if tree.type == 'a' and not attribs.href then attribs.href = links[lower(tree[1] or '')] or '' end
        if tree.type == 'img' and not attribs.src then attribs.src = links[lower(attribs.alt or '')] or '' end
        local attribstr = renderAttributes(attribs)
        if #attribstr > 0 then
            accum[#accum + 1] = format("<%s %s>", tree.type, attribstr)
        else
            accum[#accum + 1] = format("<%s>", tree.type)
        end
    end
    for i = 1, #tree do
        local line = tree[i]
        if type(line) == "string" then
            accum[#accum + 1] = line
        elseif type(line) == "table" then
            renderTree(line, links, accum)
        else
            error "Unexpected node while rendering tree."
        end
    end
    if not tree.noclose and tree.type then
        accum[#accum + 1] = format("</%s>", tree.type)
    end
end

local function renderLinesRaw(stream, options)
    local tree, links = readLineStream(stream)
    local accum = {}
    local head, tail, insertHead, insertTail, prependHead, appendTail = nil, nil, nil, nil, nil, nil
    if options then
        assert(type(options) == 'table', "Options argument should be a table.")
        if options.tag then
            tail = format('</%s>', options.tag)
            if options.attributes then
                head = format('<%s %s>', options.tag, renderAttributes(options.attributes))
            else
                head = format('<%s>', options.tag)
            end
        end
        insertHead = options.insertHead
        insertTail = options.insertTail
        prependHead = options.prependHead
        appendTail = options.appendTail
    end
    accum[#accum + 1] = prependHead
    accum[#accum + 1] = head
    accum[#accum + 1] = insertHead
    renderTree(tree, links, accum)
    if accum[#accum] == NEWLINE then accum[#accum] = nil end
    accum[#accum + 1] = insertTail
    accum[#accum + 1] = tail
    accum[#accum + 1] = appendTail
    return concat(accum)
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local function pwrap(...)
    local status, value = pcall(...)
    if status then
        return value
    else
        return nil, value
    end
end

local function renderLineIterator(stream, options)
    return pwrap(renderLinesRaw, stream, options)
end

local function renderTable(t, options)
    return pwrap(renderLinesRaw, tableLineStream(t), options)
end

local function renderString(str, options)
    return pwrap(renderLinesRaw, stringLineStream(str), options)
end

local renderers = {
    ['string'] = renderString,
    ['table'] = renderTable,
    ['function'] = renderLineIterator
}

local function render(source, options)
    local renderer = renderers[type(source)]
    if not renderer then return nil, "Source must be a string, table, or function." end
    return renderer(source, options)
end

--> SHOSETSU
return {
    render = render,
    renderString = renderString,
    renderLineIterator = renderLineIterator,
    renderTable = renderTable,
}
--< SHOSETSU

-- return setmetatable({
--     render = render,
--     renderString = renderString,
--     renderLineIterator = renderLineIterator,
--     renderTable = renderTable
-- }, {
--     __call = function(self, ...) -- luacheck: no unused args
--         return render(...)
--     end
-- })

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
-- {"id":3239,"ver":"0.1.1","libVer":"1.0.0","author":"N4O","dep":["MDLua>=1.0.0","dkjson>=1.0.1"]}

local mdRender = Require("MDLua").render
local json = Require("dkjson");

local baseURL = "https://inoveltranslation.com"
local baseAPIURL = "https://api.inoveltranslation.com"
local placeholderImage = "https://inoveltranslation.com/placeholder.png"

local function markdownToHTML(markdown)
    local html, err = mdRender(markdown)
    if err then
        error(err)
    end
    return Document(html)
end

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-inoveltranslation%.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

--- @param url string
--- @return string
local function expandAPIURL(url)
    return baseAPIURL .. url
end

--- @param chapterURL string
--- @return string
local function getPassage(chapterURL)
    local doc = GETDocument(expandAPIURL(chapterURL))
    local docContent = json.decode(doc:text())

    --- @type string
    local chTitle = docContent.title
    local chContent = markdownToHTML(docContent.content):selectFirst("body")
    if chTitle then
        chContent:child(0):before("<h2>" .. chTitle .. "</h2><hr/>")
    end
    local notes = docContent.notes
    -- total child

    if notes then
        chContent:lastElementSibling():after("<hr/><h2>Notes</h2>" .. markdownToHTML(notes):selectFirst("body"):html())
    end
    return pageOfElem(chContent)
end

--- @param doc Document
--- @return string
local function parseDescription(doc)
    local body = doc:selectFirst("body")
    local desc = ""
    map(body:children(), function (v)
        local text = v:text()
        if v:tagName():upper() == "BR" then
            desc = desc .. "\n"
        else
            desc = desc .. text .. "\n"
        end
    end)
    -- strip trailing newlines
    desc = desc:gsub("\n+$", "")
    return desc
end

local function getCoverOrFallback(coverMeta)
    local cover = placeholderImage
    if coverMeta ~= nil then
        -- https://api.inoveltranslation.com/image/TheEmperorIsMyBrother'sBestFriend-2222.png
        local coverFilename = coverMeta.filename
        if coverFilename then
            cover = "https://api.inoveltranslation.com/image/" .. coverFilename
        end
    end
    return cover
end

local function makeChapterTitle(chapterMeta)
    -- chapterMeta {
    -- 	slug : str
    -- 	chapter : int
    -- 	volume ?: nullable/int
    -- 	title ?; nullable/str
    -- 	tierId ?: nullable/int
    -- 	id : int
    -- }
    -- format:
    -- Vol. XX Ch. XX: Chapter Title
    -- Vol. XX Ch. XX
    -- Ch. XX
    -- Ch. XX: Chapter Title

    local chapterTitle = ""
    if chapterMeta.volume ~= nil then
        chapterTitle = chapterTitle .. "Vol. " .. chapterMeta.volume .. " "
    end
    chapterTitle = chapterTitle .. "Ch. " .. chapterMeta.chapter
    if chapterMeta.title ~= nil then
        chapterTitle = chapterTitle .. " - " .. chapterMeta.title
    end
    return chapterTitle
end

--- @param novelURL string
--- @return NovelInfo
local function parseNovel(novelURL, loadChapters)
    local doc = GETDocument(expandAPIURL(novelURL))
    local contents = json.decode(doc:text())
    local novel = NovelInfo {
        title = contents.title,
        imageURL = getCoverOrFallback(contents.cover),
        description = parseDescription(markdownToHTML(contents.description):selectFirst("body")),
    }
    local authors = contents.author
    local genres = contents.genres

    if authors ~= nil then
        local authorPass = { authors.name }
        novel:setAuthors(authorPass)
    end
    if genres ~= nil then
        novel:setGenres(map(genres, function (v)
            return v.name
        end))
    end
    -- staff as tags
    local staff = contents.staff
    if staff ~= nil then
        novel:setTags(map(staff, function (v)
            return v.job .. ": " .. v.username
        end))
    end
    if loadChapters then
        local chapterDoc = GETDocument(expandAPIURL(novelURL .. "/feed"))
        local chapterJson = json.decode(chapterDoc:text()).chapters
        local chapters = {}
        map(AsList(chapterJson), function (chraw)
            local chapter = NovelChapter {
                title = makeChapterTitle(chraw),
            }
            chapter:setOrder(chraw.id)
            chapter:setLink("/chapters/" .. chraw.id)
            local tierId = chraw.tierId
            if tierId == nil then
                -- ignore all the locked chapter.
                chapters[#chapters + 1] = chapter
            end
        end)
        novel:setChapters(AsList(chapters))
    end
    return novel
end

local function fetchNovelListing()
    local doc = GETDocument("https://api.inoveltranslation.com/novels")
    local contents = json.decode(doc:text())
    local novels = {}
    map(AsList(contents.novels), function (data)
        local coverMeta = data.cover
        -- if coverMeta is null
        local cover = getCoverOrFallback(coverMeta)
        local novel = Novel {
            title = data.title,
            link = "/novels/" .. data.id,
            imageURL = cover,
        }
        novels[#novels + 1] = novel
    end)
    return novels
end

return {
    id = 3239,
    name = "iNoveltranslation",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/iNovel.png",
    chapterType = ChapterType.HTML,

    hasCloudFlare = false,
    hasSearch = false,

    -- Must have at least one value
    listings = {
        -- for now, no incrementals
        Listing("Latest", false, function()
            return fetchNovelListing()
        end),
    },

    -- Default functions that have to be set
    getPassage = getPassage,
    parseNovel = parseNovel,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()