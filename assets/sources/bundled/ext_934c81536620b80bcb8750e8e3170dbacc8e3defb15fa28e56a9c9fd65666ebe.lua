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
__modules["CommonCSS"] = function()
-- {"ver":"1.0.1","author":"TechnoJo4"}

-- Collection of common CSS snippets

local tbl = {}

-- abuse of lua's syntax but it looks nice
local function def(key)
    return function(value)
        local function id(c) return c end

        tbl[key] = value
            :gsub("^%s+", "")
            :gsub("%s+$", "")
            :gsub("%s*([;{}])%s*", id)

        return def
    end
end

def

"table" [[
:root {
    --table-color: #007CBA;
}
table {
    background: none !important;
    margin: 10px auto !important;
    width: 90% !important;
    outline: var(--table-color) solid 3px !important;
    border-spacing: 3px !important;
    border-collapse: separate !important;
}
td {
    padding: 3px !important;
    background: var(--table-color) !important;
}
]]

return tbl

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
__modules["unhtml"] = function()
-- {"ver":"1.0.1","author":"Bigrand","dep":["utf8"]}

--[[
    This lib turns HTML into plain text.

    It converts tags like <p>, <br>, and <hr> to their string equivalent so the structure isn’t lost, 
    but pretty much everything else gets stripped out. It also turns HTML entities into actual characters
    and does its best to handle tables and image alt text.

    Notable:
        - Table and image alt text support.

    Caveats:
        - Unordered and ordered lists just come out as bullet lists without indentation
        - <pre> and anything with formatting gets flattened
        - No custom decorations (e.g., <h1> will look the same as a regular <p> tag)
        - No support for lots of HTML tags and edge cases. REGEX/Pattern matching gave me PTSD :D
        
    Available functions:
        - HTMLToString(s: string, config: table)
        - trim(s: string)
        - collapseWS(s: string)
        - ensureString(input: any, funcName: string)
        - ensureTable(input: any, funcName: string)
        - removeComments(s: string)
        - normalizeTags(s: string)
        - removeSpecialTags(s: string)
        - addTagBreaks(s: string)
        - fixDivPBreaks(s: string)
        - removeUnallowedTags(s: string, allowedTags: table)
        - formatHrTags(s: string, character: string, length: integer)
        - newlineToSpace(s: string)
        - formatLists(s: string, character: string)
        - brToNewlines(s: string)
        - cleanLines(s: string)
        - limitNewlines(s: string)
        - formatImages(s: string)
        - formatTables(s: string)
        - convertHTMLentities(s: string)
        - shouldExecute(s: string, pattern: string|table)
    
    If you want more details on what each function does, just check out the return {} (at the end of this file)
    and hover over the functions or find the function itself in the code and look above it. You'll find all the info you need there.
]]

-- Cache all functions used
local gsub     = string.gsub
local match    = string.match
local gmatch   = string.gmatch
local lower    = string.lower
local rep      = string.rep
local sub      = string.sub
local find     = string.find
local format   = string.format
local concat   = table.concat
local insert   = table.insert
local sort     = table.sort
local max      = math.max
local tonumber = tonumber
local type     = type
local ipairs   = ipairs
local pairs    = pairs
local error    = error
local pcall    = pcall
local tostring = tostring

local utf8 = Require("utf8")

local htmlComment       = "<!%-%-.-%-%->"
local anyTag            = "<%s*(/?)%s*([%w]+)(.-)(/?)%s*>"
local htmlAttr          = "([%a][%w-]*)%s*="
local scriptTag         = "<script[^>]*>.-</script>"
local styleTag          = "<style[^>]*>.-</style>"
local doctypeTag        = "<!doctype[^>]*>"
local divP              = "</div>(%s*)<p>"
local brTag             = "<%s*br%s*/?%s*>"
local closeTag          = "^</%s*([a-z0-9-]+)"
local openTag           = "^<%s*([a-z0-9-]+)"
local hrTag             = "<%s*/?%s*hr[^>]*%s*/?%s*>"
local htmlEntity        = "(&%a+;)"
local decimalEntity     = "&#(%d+);"
local hexadecimalEntity = "&#x(%x+);"
local newline           = "[\r\n]+"
local brWS              = "<br>%s*"
local brLi              = "(<br>%s*)<li%s*>"
local openLi            = "<li%s*>"
local closeLi           = "</li%s*>"
local multiNewline      = "%s*\n%s*\n%s*\n+%s*"
local tableBlock        = "<table.-</table>"
local trBlock           = "<tr.-</tr>"
local tableCell         = "<(t[dh])[^>]*>(.-)</%1>"
local simpleAnyTag      = "<[^>]+>"
local imgTag            = "(<img.-/?>)"
local imgAltAttrDouble  = [[alt%s*=%s*"([^"]*)"]]
local imgAltAttrSingle  = [[alt%s*=%s*'([^']*)']]
local anyThTag          = "<th"

-- Jsoup already decodes HTML entities but I'm using pattern matching
-- because I'm a dumbass, so enjoy it :)
local htmlEntities = {
	-- Basic Entities
	["&nbsp;"] = " ", ["&amp;"] = "&", ["&quot;"] = "\"", ["&apos;"] = "'", ["&lt;"] = "<", ["&gt;"] = ">",

	-- Copyright and Trademark
	["&copy;"] = "©", ["&reg;"] = "®", ["&trade;"] = "™",

	-- Currency
	["&cent;"] = "¢", ["&pound;"] = "£", ["&euro;"] = "€", ["&yen;"] = "¥", ["&curren;"] = "¤",

	-- Math Operators
	["&times;"] = "×", ["&divide;"] = "÷",

	-- ISO-8859-1 Symbols
	["&iexcl;"] = "¡", ["&brvbar;"] = "¦", ["&sect;"] = "§", ["&uml;"] = "¨", ["&ordf;"] = "ª", ["&laquo;"] = "«",
	["&not;"] = "¬", ["&macr;"] = "¯", ["&deg;"] = "°", ["&plusmn;"] = "±", ["&sup2;"] = "²", ["&sup3;"] = "³",
	["&acute;"] = "´", ["&micro;"] = "µ", ["&para;"] = "¶", ["&cedil;"] = "¸", ["&sup1;"] = "¹", ["&ordm;"] = "º",
	["&raquo;"] = "»", ["&frac14;"] = "¼", ["&frac12;"] = "½", ["&frac34;"] = "¾", ["&iquest;"] = "¿",

	-- Math Symbols
	["&forall;"] = "∀", ["&part;"] = "∂", ["&exist;"] = "∃", ["&empty;"] = "∅", ["&nabla;"] = "∇", ["&isin;"] = "∈",
	["&notin;"] = "∉", ["&ni;"] = "∋", ["&prod;"] = "∏", ["&sum;"] = "∑", ["&minus;"] = "−", ["&lowast;"] = "∗",
	["&radic;"] = "√", ["&prop;"] = "∝", ["&infin;"] = "∞", ["&ang;"] = "∠", ["&and;"] = "∧", ["&or;"] = "∨",
	["&cap;"] = "∩", ["&cup;"] = "∪", ["&int;"] = "∫", ["&there4;"] = "∴", ["&sim;"] = "∼", ["&cong;"] = "≅",
	["&asymp;"] = "≈", ["&ne;"] = "≠", ["&equiv;"] = "≡", ["&le;"] = "≤", ["&ge;"] = "≥", ["&sub;"] = "⊂",
	["&sup;"] = "⊃", ["&nsub;"] = "⊄", ["&sube;"] = "⊆", ["&supe;"] = "⊇", ["&oplus;"] = "⊕", ["&otimes;"] = "⊗",
	["&perp;"] = "⊥", ["&sdot;"] = "⋅",

	-- Greek Letters (Uppercase)
	["&Alpha;"] = "Α", ["&Beta;"] = "Β", ["&Gamma;"] = "Γ", ["&Delta;"] = "Δ", ["&Epsilon;"] = "Ε", ["&Zeta;"] = "Ζ",
	["&Eta;"] = "Η", ["&Theta;"] = "Θ", ["&Iota;"] = "Ι", ["&Kappa;"] = "Κ", ["&Lambda;"] = "Λ", ["&Mu;"] = "Μ",
	["&Nu;"] = "Ν", ["&Xi;"] = "Ξ", ["&Omicron;"] = "Ο", ["&Pi;"] = "Π", ["&Rho;"] = "Ρ", ["&Sigma;"] = "Σ",
	["&Tau;"] = "Τ", ["&Upsilon;"] = "Υ", ["&Phi;"] = "Φ", ["&Chi;"] = "Χ", ["&Psi;"] = "Ψ", ["&Omega;"] = "Ω",

	-- Greek Letters (Lowercase)
	["&alpha;"] = "α", ["&beta;"] = "β", ["&gamma;"] = "γ", ["&delta;"] = "δ", ["&epsilon;"] = "ε", ["&zeta;"] = "ζ",
	["&eta;"] = "η", ["&theta;"] = "θ", ["&iota;"] = "ι", ["&kappa;"] = "κ", ["&lambda;"] = "λ", ["&mu;"] = "μ",
	["&nu;"] = "ν", ["&xi;"] = "ξ", ["&omicron;"] = "ο", ["&pi;"] = "π", ["&rho;"] = "ρ", ["&sigmaf;"] = "ς",
	["&sigma;"] = "σ", ["&tau;"] = "τ", ["&upsilon;"] = "υ", ["&phi;"] = "φ", ["&chi;"] = "χ", ["&psi;"] = "ψ",
	["&omega;"] = "ω", ["&thetasym;"] = "ϑ", ["&upsih;"] = "ϒ", ["&piv;"] = "ϖ",

	-- Miscellaneous
	["&OElig;"] = "Œ", ["&oelig;"] = "œ", ["&Scaron;"] = "Š", ["&scaron;"] = "š", ["&Yuml;"] = "Ÿ", ["&fnof;"] = "ƒ",

	-- Arrows
	["&larr;"] = "←", ["&rarr;"] = "→", ["&uarr;"] = "↑", ["&darr;"] = "↓",
	["&lArr;"] = "⇐", ["&rArr;"] = "⇒", ["&uArr;"] = "⇑", ["&dArr;"] = "⇓",
	["&harr;"] = "↔", ["&hArr;"] = "⇔",

	-- Typographic Symbols
	["&ndash;"] = "–", ["&mdash;"] = "—", ["&tilde;"] = "˜",
	["&lsquo;"] = "‘",  ["&rsquo;"] = "’", ["&circ;"] = "ˆ",
	["&ldquo;"] = "“",   ["&rdquo;"] = "”",
	["&bdquo;"] = "„", ["&dagger;"] = "†",
	["&Dagger;"] = "‡", ["&bull;"] = "•", ["&hellip;"] = "…",

	-- Common Accented Latin Characters
	["&Agrave;"] = "À", ["&Aacute;"] = "Á", ["&Acirc;"] = "Â", ["&Atilde;"] = "Ã", ["&Auml;"] = "Ä", ["&Aring;"] = "Å",
	["&AElig;"] = "Æ", ["&Ccedil;"] = "Ç", ["&Egrave;"] = "È", ["&Eacute;"] = "É", ["&Ecirc;"] = "Ê", ["&Euml;"] = "Ë",
	["&Igrave;"] = "Ì", ["&Iacute;"] = "Í", ["&Icirc;"] = "Î", ["&Iuml;"] = "Ï", ["&ETH;"] = "Ð", ["&Ntilde;"] = "Ñ",
	["&Ograve;"] = "Ò", ["&Oacute;"] = "Ó", ["&Ocirc;"] = "Ô", ["&Otilde;"] = "Õ", ["&Ouml;"] = "Ö", ["&Oslash;"] = "Ø",
	["&Ugrave;"] = "Ù", ["&Uacute;"] = "Ú", ["&Ucirc;"] = "Û", ["&Uuml;"] = "Ü", ["&Yacute;"] = "Ý", ["&THORN;"] = "Þ",
	["&szlig;"] = "ß", ["&agrave;"] = "à", ["&aacute;"] = "á", ["&acirc;"] = "â", ["&atilde;"] = "ã", ["&auml;"] = "ä",
	["&aring;"] = "å", ["&aelig;"] = "æ", ["&ccedil;"] = "ç", ["&egrave;"] = "è", ["&eacute;"] = "é", ["&ecirc;"] = "ê",
	["&euml;"] = "ë", ["&igrave;"] = "ì", ["&iacute;"] = "í", ["&icirc;"] = "î", ["&iuml;"] = "ï", ["&eth;"] = "ð",
	["&ntilde;"] = "ñ", ["&ograve;"] = "ò", ["&oacute;"] = "ó", ["&ocirc;"] = "ô", ["&otilde;"] = "õ", ["&ouml;"] = "ö",
	["&oslash;"] = "ø", ["&ugrave;"] = "ù", ["&uacute;"] = "ú", ["&ucirc;"] = "û", ["&uuml;"] = "ü", ["&yacute;"] = "ý",
	["&thorn;"] = "þ", ["&yuml;"] = "ÿ",

	-- Card Suits and Symbols
	["&hearts;"] = "♥", ["&diams;"] = "♦", ["&clubs;"] = "♣", ["&spades;"] = "♠",
	["&star;"] = "★", ["&check;"] = "✓", ["&cross;"] = "✗",

	-- Additional Math and Technical Symbols
	["&prime;"] = "′", ["&Prime;"] = "″",
	["&frasl;"] = "⁄", ["&weierp;"] = "℘",
	["&image;"] = "ℑ", ["&real;"] = "ℜ",
	["&alefsym;"] = "ℵ",

	-- Extra Space Characters
	["&ensp;"] = " ", ["&emsp;"] = " ", ["&thinsp;"] = " ",

	-- Control Characters
	["&zwj;"] = "\u{200D}", ["&zwnj;"] = "\u{200C}",
	["&lrm;"] = "\u{200E}", ["&rlm;"] = "\u{200F}",
}

---Ensures the input is a string, converting it if possible or raising an error.
---
---@param input any 
---@param funcName string Used for error reporting. The name of the section calling this function.
---@return string validatedString The validated string or an error :)
local function ensureString(input, funcName)
    funcName = funcName or "ensureString"

    if type(input) == "string" then
        return input
    end

    local success, result = pcall(tostring, input)
    if success and type(result) == "string" then
        return result
    end

    error(format(
        "unhtml(%s): expected a string or a value convertible to string, but got a '%s'.",
        funcName,
        type(input)
    ), 2)
end


---Ensures the input is a table, converting it if possible or raising an error.
---
---@param input any
---@param funcName string Used for error reporting. The name of the section calling this function.
---@return table validatedTable The validated table or an error :)
local function ensureTable(input, funcName)
    funcName = funcName or "ensureTable"

    if type(input) ~= "table" then
        error(format(
            "unhtml(%s): expected a table, but got '%s'. Ensure the input is in the correct format.",
            funcName,
            type(input)
        ), 2)
    end

    -- If the input is a table, return it as is
    return input
end

local trimWS = "^%s*(.-)%s*$"

---Trims whitespace from both ends.
---
---@param s string
---@return string modifiedInput
local function trim(s)
    s = ensureString(s, "trim")
    if s == "" then return "" end

    return match(s, trimWS)
end


local whitespace = "%s+"

---Collapses all sequences of whitespace characters in the input string into a single space.
---
---@param s string
---@return string modifiedText
---@return integer nReplacements
local function collapseWS(s)
    s = ensureString(s, "collapseWS")
    if s == "" then return "", 0 end

    return gsub(s, whitespace, " ")
end

---Removes all HTML comment tags from the input string.
---
---@param s string
---@return string modifiedInput
---@return integer nReplacements
local function removeComments(s)
    s = ensureString(s, "removeComments")
    if s == "" then return "", 0 end

    return gsub(s, htmlComment, "")
end

---Normalizes HTML tags in the input string by ensuring lowercase tags and attributes,
---and correctly formatting self-closing and closing tags.
---
---@param s string
---@return string modifiedInput
---@return integer nReplacements
local function normalizeTags(s)
    s = ensureString(s, "normalizeTags")
    if s == "" then return "", 0 end

    return gsub(s, anyTag, function(closing, tag, attributes, selfClosing)
        tag = lower(tag)

        if closing ~= "" then
            return "</" .. tag .. ">"
        else
            local attrText = ""
            if attributes and match(attributes, "%S") then
                local normalizedAttrs = gsub(attributes, htmlAttr, function(attr)
                    return lower(attr) .. "="
                end)

                attrText = " " .. trim(normalizedAttrs)
            end

            if selfClosing ~= "" then
                return "<" .. tag .. attrText .. "/>"
            else
                return "<" .. tag .. attrText .. ">"
            end
        end
    end
    )
end

---Removes special HTML tags (script, style, doctype) from the input string.
---
---@param s string
---@return string modifiedInput
---@return integer nReplacements
local function removeSpecialTags(s)
    s = ensureString(s, "removeSpecialTags")
    if s == "" then return "", 0 end

    local nTotal = 0
    local n

    s, n = gsub(s, scriptTag, "")
    nTotal = nTotal + n

    s, n = gsub(s, styleTag, "")
    nTotal = nTotal + n

    s, n = gsub(s, doctypeTag, "")
    nTotal = nTotal + n

    return s, nTotal
end

---Adds `<br>` tags before and after specified block tags in the input string to preserve text structure.
---
---@param s string
---@param blockTags table A table of block tags with associated before and after <br> counts. Each entry should be a table in the form `{tagName, beforeCount, afterCount}`.
---@return string modifiedInput
local function addTagBreaks(s, blockTags)
    s = ensureString(s, "addTagBreaks")
    if s == "" then return "" end
    ensureTable(blockTags, "addTagBreaks")

    -- Create a lookup table for faster tag access and to handle duplicates
    local tagLookup = {}
    for _, tagInfo in ipairs(blockTags) do
        local tag, before, after = tagInfo[1], tagInfo[2], tagInfo[3]
        tagLookup[tag] = {
            before = rep("<br>", before),
            after = rep("<br>", after)
        }
    end

    -- Collect all tag positions to avoid processing the same section multiple times
    local modifications = {}

    -- Process closing tags first (add breaks after)
    for tag, config in pairs(tagLookup) do
        local pattern = "</" .. tag .. ">"
        local startPos = 1

        while true do
            local tagPos = find(s, pattern, startPos, true)
            if not tagPos then break end

            local endPos = tagPos + #pattern - 1
            insert(modifications, {
                position = endPos + 1,
                content = config.after,
                type = "after"
            })

            startPos = endPos + 1
        end
    end

    -- Process opening tags (add breaks before)
    for tag, config in pairs(tagLookup) do
        if #config.before > 0 then
            local startPos = 1

            while true do
                local tagStart = find(s, "<" .. tag .. "[^>]*>", startPos)
                if not tagStart then break end

                local tagEnd = find(s, ">", tagStart)
                if not tagEnd then break end

                insert(modifications, {
                    position = tagStart,
                    content = config.before,
                    type = "before"
                })

                startPos = tagEnd + 1
            end
        end
    end

    -- Sort modifications in reverse order to avoid position shifts
    sort(modifications, function(a, b)
        return a.position > b.position
    end)

    -- Apply modifications
    for _, mod in ipairs(modifications) do
        if mod.type == "after" then
            s = sub(s, 1, mod.position - 1) .. mod.content .. sub(s, mod.position)
        else -- "before"
            s = sub(s, 1, mod.position - 1) .. mod.content .. sub(s, mod.position)
        end
    end

    return s
end


---Inserts `<br><br>` between `</div>` and `<p>` if no `<br>` tags are found between them.
---
---@param s string
---@return string modifiedText
---@return integer nReplacements
local function fixDivPBreaks(s)
    s = ensureString(s, "fixDivPBreaks")
    if s == "" then return "", 0 end

    return gsub(s, divP, function (whitespace)
        -- If there's a <br> already, return the original string
        if find(whitespace, brTag) then
            return "</div>" .. whitespace .. "<p>"
        else
            return "</div>" .. whitespace .. "<br><br><p>"
        end
    end)
end

---Removes all HTML tags from the input string except for those specified in the `allowedTags` table.
---
---@param s string
---@param allowedTags table A table of tag names that are allowed to remain in the string. Each entry is a string: `{"hr", "br"}`.
---@return string modifiedInput
local function removeUnallowedTags(s, allowedTags)
    s = ensureString(s, "removeUnallowedTags")
    if s == "" then return "" end
    ensureTable(allowedTags, "removeUnallowedTags")

    local result = ""
    local position = 1

    while position <= #s do
        -- Find the next opening angle bracket
        local tagStart = find(s, "<", position)
        if not tagStart then
            -- No more tags, add the rest of the string
            result = result .. sub(s, position)
            break
        end

        -- Add string up to the tag
        result = result .. sub(s, position, tagStart - 1)

        -- Find the closing angle bracket
        local tagEnd = find(s, ">", tagStart)
        if not tagEnd then
            -- Unclosed tag, treat as string
            result = result .. sub(s, tagStart)
            break
        end

        -- Extract the tag
        local tag = sub(s, tagStart, tagEnd)

        -- Check if it's a closing or opening tag 
        local tagName
        if match(tag, closeTag) then
            tagName = match(tag, closeTag)
        else
            tagName = match(tag, openTag)
        end

        -- Only keep the tag if it's allowed
        local keepTag = false
        for _, allowed in ipairs(allowedTags) do
            if tagName == allowed then
                keepTag = true
                break
            end
        end

        if keepTag then
            result = result .. tag
        end

        position = tagEnd + 1
    end

    return result
end

---Replaces `<hr>` tags with a line seperator.
---
---@param s string
---@param character string The character to be used as a separator. Defaults to ─.
---@param length integer The number of times the character will be repeated. Must be positive. Defaults to 10.
---@return string modifiedInput
---@return integer nReplacements
local function formatHrTags(s, character, length)
    s = ensureString(s, "formatHrTags")
    if s == "" then return "", 0 end

    character = character or "─"
    length = max(1, tonumber(length) or 10)

    local separator = rep(character, length)

    return gsub(s, hrTag, "<br><br>" .. separator .. "<br><br>")
end

---Replaces all newline characters in the input string with spaces.
---
---@param s string
---@return string modifiedText
---@return integer nReplacements
local function newlineToSpace(s)
    s = ensureString(s, "newlineToSpace")
    if s == "" then return "", 0 end

    return gsub(s, newline, " ")
end

---Partial support for HTML lists. Converts `<li>` tags to bullet points and removes `</li>` tags.
---Doesn't preserve nested/indented lists or ordered lists.
---
---@param s string
---@param character string The character to be used as the bullet point. Defaults to •.
---@return string modifiedInput
---@return integer nReplacements
local function formatLists(s, character)
    s = ensureString(s, "formatLists")
    if s == "" then return "", 0 end

    character = character or "•"

    local nTotal = 0
    local n

    -- Remove any extra whitespace after <br>
    s, n = gsub(s, brWS, "<br>")
    nTotal = nTotal + n

    -- If `<li>` is preceded by a <br>, just add a bullet
    s, n = gsub(s, brLi, "%1" .. character .. " ")
    nTotal = nTotal + n

    -- For opening `<li>` tags, add a bullet and line break
    s, n = gsub(s, openLi, "<br>" .. character .. " ")
    nTotal = nTotal + n

    -- Remove closing `</li>` tags
    s, n = gsub(s, closeLi, "")
    nTotal = nTotal + n

    return s, nTotal
end

---Replaces all `<br>` tags in the input string with newline characters.
---
---@param s string
---@return string modifiedInput
---@return integer nReplacements
local function brToNewlines(s)
    s = ensureString(s, "brToNewlines")
    if s == "" then return "", 0 end

    return gsub(s, brTag, "\n")
end

---Cleans up line formatting by trimming and collapsing whitespace on each line.
---Preserves line breaks and ensures consistent spacing within the text.
---
---@param s string
---@return string modifiedInput
local function cleanLines(s)
    s = ensureString(s, "cleanLines")
    if s == "" then return "" end

    local processedLines = {}

    for line in gmatch(s .. "\n", "(.-)\n") do
        local cleaned = trim(collapseWS(line))
        insert(processedLines, cleaned)
    end

    s = concat(processedLines, "\n")

    return s
end

---Limits consecutive newlines in a string to "\n\n"
---
---@param s string
---@return string modifiedInput
---@return integer nReplacements
local function limitNewlines(s)
    s = ensureString(s, "limitNewlines")
    if s == "" then return "", 0 end

    return gsub(s, multiNewline, "\n\n")
end

---Replaces image tags with their alt text. If an image has alt text, the format will be `[Image: <alt-text>]`.
---if no alt text is found, it will be replaced with `[Image]`.
---
---@param s string
---@return string modifiedInput
local function formatImages(s)
    s = ensureString(s, "formatImages")
    if s == "" then return "" end

    local lastPos = 1
    local processedChunks = {}

    local imgPos = 1
    while true do
        local imgStart, imgEnd, imgTagText = find(s, imgTag, imgPos)

        -- If no more images found, exit the loop
        if not imgStart then
            break
        end

        -- Add text before the image as it was
        insert(processedChunks, sub(s, lastPos, imgStart - 1))

        -- Extract alt attribute
        local alt = imgTagText:match(imgAltAttrDouble) or imgTagText:match(imgAltAttrSingle) or ""

        -- Replace the image tag with its alt text
        if alt ~= "" then
            insert(processedChunks, "[Image: " .. alt .. "]")
        else
            insert(processedChunks, "[Image]")
        end

        -- Move on to look for the next image
        lastPos = imgEnd + 1
        imgPos = imgEnd + 1
    end

    -- Add remaining text after last image
    insert(processedChunks, sub(s, lastPos))
    s = concat(processedChunks)

    return s
end

---Converts HTML table tags into a string table format with padded columns.
---Header rows are separated by a line of dashes.
---
---@param s string
---@return string modifiedInput
local function formatTables(s)
    s = ensureString(s, "formatTables")
    if s == "" then return "" end

    local lastPos = 1
    local tableChunks = {}

    local pos = 1
    while true do
        -- Find the next table
        local tableStart, tableEnd = find(s, tableBlock, pos)

        -- Add text before the table as it was
        if not tableStart then
            break
        end

        insert(tableChunks, sub(s, lastPos, tableStart - 1))

        -- Extract the table HTML
        local tableHTML = sub(s, tableStart, tableEnd)

        local rows = {}
        local isHeader = false
        local maxColumns = {}

        -- Pull out all rows and calculate the widest cell in each column
        for row in gmatch(tableHTML, trBlock) do
            local columns = {}
            local isHeaderRow = find(row, anyThTag) ~= nil
            if isHeaderRow then isHeader = true end

            -- Grab each <td> or <th> in the row
            for tag, content in gmatch(row, tableCell) do
                local raw = gsub(content, simpleAnyTag, "") -- Remove HTML tags
                local text = trim(collapseWS(raw))
                insert(columns, text)

                -- Update the max width for this column if needed
                maxColumns[#columns] = max(maxColumns[#columns] or 0, #text)
            end

            -- Only add the row if it has content
            if #columns > 0 then
                insert(rows, { columns = columns, isHeader = isHeaderRow })
            end
        end

        local outputLines = {}

        -- Format everything with padding
        for i, row in ipairs(rows) do
            local formattedRow = {}
            for j, text in ipairs(row.columns) do
                insert(formattedRow, text .. rep(" ", maxColumns[j] - #text))
            end
            insert(outputLines, concat(formattedRow, " | "))

            -- If it's a header row, add in a separator line after it
            if i == 1 and isHeader then
                local separator = {}
                for j = 1, #row.columns do
                    insert(separator, rep("-", maxColumns[j]))
                end
                insert(outputLines, concat(separator, " | "))
            end
        end

        -- Insert the formatted table into the result string
        insert(tableChunks, concat(outputLines, "\n") .. "\n\n")

        -- Move on to look for the next table
        lastPos = tableEnd + 1
        pos = tableEnd + 1
    end

    -- Add remaining text after last table
    insert(tableChunks, sub(s, lastPos))
    s = concat(tableChunks)

    return s
end

---Converts HTML entities in a string to their corresponding characters.
---Supports named, decimal, and hexadecimal HTML entities.
---
---@param s string
---@return string modifiedInput
---@return integer nReplacements
local function convertHTMLentities(s)
    s = ensureString(s, "convertHTMLentities")
    if s == "" then return "", 0 end

    local nTotal = 0
    local r

    s, r = gsub(s, htmlEntity, htmlEntities)
    nTotal = nTotal + r

    s, r = gsub(s, decimalEntity, function(num)
        local n = tonumber(num) or 0
        return n and utf8.char(n) or ""
    end)
    nTotal = nTotal + r

    s, r = gsub(s, hexadecimalEntity, function(hex)
        local n = tonumber(hex, 16)
        return n and utf8.char(n) or ""
    end)
    nTotal = nTotal + r

    return s, nTotal
end

---Quickly checks if a string contains specific patterns to determine if a function should be executed
---
---@param s string
---@param pattern string|table
---@return boolean shouldExecute True if the pattern(s) were found
local function shouldExecute(s, pattern)
    -- If input is not a string or empty, don't execute
    if type(s) ~= "string" or s == "" then
        return false
    end

    -- If pattern is a table of patterns, check each one
    if type(pattern) == "table" then
        for _, p in ipairs(pattern) do
            if find(s, p, 1, true) then
                return true
            end
        end
        return false
    end

    -- Check for single pattern
    return find(s, pattern, 1, true) ~= nil
end

--- Converts a string containing HTML to a strings representation with formatting.
--- Some decorations can be customized using the `config` table.
---
--- @param s string The HTML input string to be converted. If it's not a string, it will be converted into one if possible.
--- @param config table Configuration options to customize output:
---   - `hrTagSeparator` (string): Character(s) used for horizontal rule replacement (default: `"─"`).
---   - `hrTagSeparatorLength` (number): Length of the horizontal rule (default: `10`).
---   - `listBulletPointCharacter` (string): Bullet character for list items (default: `"•"`).
--- 
--- @example
--- ```lua
--- local config = {
---     hrTagSeparator = "─",
---     hrTagSeparatorLength = 10,
---     listBulletPointCharacter = "•"
--- }
--- 
--- -- Can also be a plain string with HTML tags.
--- local html = info:selectFirst(".description .hidden-content")
---
--- local output = HTMLToString(html, config)
--- print(output)
--- ```
local function HTMLToString(s, config)
    s = ensureString(s, "HTMLToString")
    if s == "" then return "" end

    -- Config
    config = config or {}
    local hrTagSeparator = config.hrTagSeparator or "─"
    local hrTagSeparatorLength = config.hrTagSeparatorLength or 10
    local listBulletPointCharacter = config.listBulletPointCharacter or "•"

    if shouldExecute(s, "<!--") then
        s = removeComments(s)
    end

    s = normalizeTags(s)

    if shouldExecute(s, {"<script", "<style", "<!doctype"}) then
        s = removeSpecialTags(s)
    end

    local blockTags = {
        -- {tag, brBefore, brAfter}
        {"address",   2, 2},
        {"article",   2, 2},
        {"aside",     2, 2},
        {"blockquote",2, 2},
        {"details",   2, 2},
        {"div",       2, 2},
        {"fieldset",  2, 2},
        {"figure",    2, 2},
        {"h1",        2, 2},
        {"h2",        2, 2},
        {"h3",        1, 2},
        {"h4",        1, 2},
        {"h5",        1, 2},
        {"h6",        1, 2},
        {"header",    2, 2},
        {"main",      2, 2},
        {"nav",       2, 2},
        {"p",         1, 2},
        {"pre",       2, 2},
        {"section",   2, 2},
        {"title",     0, 2},
    }

    -- Create a pattern to detect block tags quickly
    local blockTagPatterns = {}
    for _, tagInfo in ipairs(blockTags) do
        insert(blockTagPatterns, "<" .. tagInfo[1])
        insert(blockTagPatterns, "</" .. tagInfo[1])
    end

    if shouldExecute(s, blockTagPatterns) then
        s = addTagBreaks(s, blockTags)
    end

    -- Edge-case check
    if shouldExecute(s, "</div") and shouldExecute(s, "<p") then
        s = fixDivPBreaks(s)
    end

    local allowedTags = {"br", "hr", "li", "img", "table","tr",
                        "td", "th", "thead", "tbody", "tfoot"}
    s = removeUnallowedTags(s, allowedTags)

    if shouldExecute(s, {"<hr", "</hr"}) then
        s = formatHrTags(s, hrTagSeparator, hrTagSeparatorLength)
    end

    if shouldExecute(s, {"\r", "\n"}) then
        s = newlineToSpace(s)
    end

    if shouldExecute(s, {"<li", "</li"}) then
        s = formatLists(s, listBulletPointCharacter)
    end

    if shouldExecute(s, "<br") then
        s = brToNewlines(s)
    end

    s = cleanLines(s)

    if shouldExecute(s, "<img") then
        s = formatImages(s)
    end

    if shouldExecute(s, "<table") then
        s = formatTables(s)
    end

    if shouldExecute(s, "&") then
        s = convertHTMLentities(s)
    end

    s = limitNewlines(s)

    return trim(s)
end

return {
    ensureString = ensureString,
    ensureTable = ensureTable,
    trim = trim,
    collapseWS = collapseWS,
    removeComments = removeComments,
    normalizeTags = normalizeTags,
    removeSpecialTags = removeSpecialTags,
    addTagBreaks = addTagBreaks,
    fixDivPBreaks = fixDivPBreaks,
    removeUnallowedTags = removeUnallowedTags,
    formatHrTags = formatHrTags,
    newlineToSpace = newlineToSpace,
    formatLists = formatLists,
    brToNewlines = brToNewlines,
    cleanLines = cleanLines,
    limitNewlines = limitNewlines,
    formatImages = formatImages,
    formatTables = formatTables,
    convertHTMLentities = convertHTMLentities,
    shouldExecute = shouldExecute,
    HTMLToString = HTMLToString
}

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
-- {"id":36833,"ver":"1.0.18","libVer":"1.0.0","author":"TechnoJo4","dep":["url>=1.0.0","CommonCSS>=1.0.0","unhtml>=1.0.0"]}

local baseURL = "https://www.royalroad.com"

local qs = Require("url").querystring
local HTMLToString = Require("unhtml").HTMLToString
local css = Require("CommonCSS").table

-- LUA ARRAYS ONLY KNOW HOW TO COUNT FROM 0 or 1
local KEYWORD_FILTER_KEY = 099
local AUTHOR_FILTER_KEY = 100
local GENRES_FILTER_EXT = {"Action", "Adventure", "Comedy", "Contemporary", "Drama", "Fantasy", "Historical", "Horror", "Mystery", "Psychological", "Romance", "Satire", "Sci-fi", "Short Story", "Tragedy"}
local GENRES_FILTER_KEY = 200
local GENRES_FILTER_INT = { --individual, start from 1 to match ext
	[GENRES_FILTER_KEY+01] = "action",
	[GENRES_FILTER_KEY+02] = "adventure",
	[GENRES_FILTER_KEY+03] = "comedy",
	[GENRES_FILTER_KEY+04] = "contemporary",
	[GENRES_FILTER_KEY+05] = "drama",
	[GENRES_FILTER_KEY+06] = "fantasy",
	[GENRES_FILTER_KEY+07] = "historical",
	[GENRES_FILTER_KEY+08] = "horror",
	[GENRES_FILTER_KEY+09] = "mystery",
	[GENRES_FILTER_KEY+10] = "psychological",
	[GENRES_FILTER_KEY+11] = "romance",
	[GENRES_FILTER_KEY+12] = "satire",
	[GENRES_FILTER_KEY+13] = "sci_fi",
	[GENRES_FILTER_KEY+14] = "one_shot",
	[GENRES_FILTER_KEY+15] = "tragedy",
}
local TAGS_FILTER_EXT = {"Anti-Hero Lead", "Artificial Intelligence", "Attractive MC", "Cyberpunk", "Dungeon", "Dystopia", "Female Lead", "First Contact", "GameLit", "Gender Bender", "Genetically Engineered", "Grimdark", "Hard Sci-fi", "Harem", "High Fantasy", "LitRPG", "Loop", "Low Fantasy", "Magic", "Male Lead", "Martial Arts", "Multiple Lead Characters", "Mythos", "Non-Human lead", "Portal Fantasy / Isekai", "Post Apocalyptic", "Progression", "Reader interactive", "Reincarnation", "Ruling Class", "School Life", "Secret Identity", "Slice of Life", "Soft Sci-fi", "Space Opera", "Sports", "Steampunk", "Strategy", "Strong Lead", "Super Heroes", "Supernatural", "Technologically Engineered", "Time Travel", "Urban Fantasy", "Villainous Lead", "Virtual Reality", "War and Military", "Wuxia", "Xianxia"}
local TAGS_FILTER_KEY = 300
local TAGS_FILTER_INT = { --individual, start from 1 to match ext
	[TAGS_FILTER_KEY+01] = "anti-hero_lead",
	[TAGS_FILTER_KEY+02] = "Artificial_Intelligence",
	[TAGS_FILTER_KEY+03] = "attractive-mc",
	[TAGS_FILTER_KEY+04] = "cyberpunk",
	[TAGS_FILTER_KEY+05] = "dungeon",
	[TAGS_FILTER_KEY+06] = "Dystopia",
	[TAGS_FILTER_KEY+07] = "female_lead",
	[TAGS_FILTER_KEY+08] = "First_Contact",
	[TAGS_FILTER_KEY+09] = "gamelit",
	[TAGS_FILTER_KEY+10] = "gender_bender",
	[TAGS_FILTER_KEY+11] = "Genetically_Engineered",
	[TAGS_FILTER_KEY+12] = "grimdark",
	[TAGS_FILTER_KEY+13] = "Hard_Sci_fi",
	[TAGS_FILTER_KEY+14] = "harem",
	[TAGS_FILTER_KEY+15] = "high_fantasy",
	[TAGS_FILTER_KEY+16] = "litrpg",
	[TAGS_FILTER_KEY+17] = "Loop",
	[TAGS_FILTER_KEY+18] = "low_fantasy",
	[TAGS_FILTER_KEY+19] = "magic",
	[TAGS_FILTER_KEY+20] = "male_lead",
	[TAGS_FILTER_KEY+21] = "martial_arts",
	[TAGS_FILTER_KEY+22] = "multiple_lead",
	[TAGS_FILTER_KEY+23] = "mythos",
	[TAGS_FILTER_KEY+24] = "non-human_lead",
	[TAGS_FILTER_KEY+25] = "summoned_hero",
	[TAGS_FILTER_KEY+26] = "post_apocalyptic",
	[TAGS_FILTER_KEY+27] = "Progression",
	[TAGS_FILTER_KEY+28] = "reader_interactive",
	[TAGS_FILTER_KEY+29] = "reincarnation",
	[TAGS_FILTER_KEY+30] = "ruling_class",
	[TAGS_FILTER_KEY+31] = "school_life",
	[TAGS_FILTER_KEY+32] = "secret_identity",
	[TAGS_FILTER_KEY+33] = "slice_of_life",
	[TAGS_FILTER_KEY+34] = "Soft_Sci_fi",
	[TAGS_FILTER_KEY+35] = "space_opera",
	[TAGS_FILTER_KEY+36] = "sports",
	[TAGS_FILTER_KEY+37] = "steampunk",
	[TAGS_FILTER_KEY+38] = "strategy",
	[TAGS_FILTER_KEY+39] = "strong_lead",
	[TAGS_FILTER_KEY+40] = "super_heroes",
	[TAGS_FILTER_KEY+41] = "supernatural",
	[TAGS_FILTER_KEY+42] = "Technologically_Engineered",
	[TAGS_FILTER_KEY+43] = "Time_Travel",
	[TAGS_FILTER_KEY+44] = "urban_fantasy",
	[TAGS_FILTER_KEY+45] = "villainous_lead",
	[TAGS_FILTER_KEY+46] = "virtual_reality",
	[TAGS_FILTER_KEY+47] = "war_and_military",
	[TAGS_FILTER_KEY+48] = "wuxia",
	[TAGS_FILTER_KEY+49] = "xianxia",
}
local CONTENT_WARNINGS_FILTER_EXT = {"Profanity", "Sexual Content", "Gore", "Traumatising content"}
local CONTENT_WARNINGS_FILTER_KEY = 400
local CONTENT_WARNINGS_FILTER_INT = { --individual, start from 1 to match ext
	[CONTENT_WARNINGS_FILTER_KEY+1] = "profanity",
	[CONTENT_WARNINGS_FILTER_KEY+2] = "sexuality",
	[CONTENT_WARNINGS_FILTER_KEY+3] = "gore",
	[CONTENT_WARNINGS_FILTER_KEY+4] = "traumatising",
}
local PAGES_MIN_FILTER_KEY = 500
local PAGES_MAX_FILTER_KEY = 501
local RATING_MIN_FILTER_KEY = 502
local RATING_MAX_FILTER_KEY = 503
local STATUS_FILTER_EXT = {"ALL", "COMPLETED", "DROPPED", "ONGOING", "HIATUS", "STUB"}
local STATUS_FILTER_KEY = 600
local STATUS_FILTER_INT = { --individual, start from 1 to match ext
	[STATUS_FILTER_KEY+1] = "ALL",
	[STATUS_FILTER_KEY+2] = "COMPLETED",
	[STATUS_FILTER_KEY+3] = "DROPPED",
	[STATUS_FILTER_KEY+4] = "ONGOING",
	[STATUS_FILTER_KEY+5] = "HIATUS",
	[STATUS_FILTER_KEY+6] = "STUB",
}
local ORDER_BY_FILTER_EXT = {"Relevance", "Popularity", "Average Rating", "Last Update", "Release Date", "Followers", "Number of Pages", "Views", "Title"}
local ORDER_BY_FILTER_KEY = 700
local ORDER_BY_FILTER_INT = { --dropdown, start from 0
	[0] = "relevance",
	"popularity",
	"rating",
	"last_update",
	"release_date",
	"followers",
	"length",
	"views",
	"title",
}
local ORDER_FILTER_KEY = 800
local TYPE_FILTER_EXT = {"All", "Fan Fiction", "Original"}
local TYPE_FILTER_KEY = 900
local TYPE_FILTER_INT = { --dropdown, start from 0
	[0] = "all",
	"fanfiction",
	"original",
}

local function shrinkURL(url, t)
	if t == 1 then -- novel url
		url = url:match("/fiction/(%d+)")
	else
		url = url:gsub("^.-royalroad%.com/?", "")
	end
	return url
end

local function expandURL(url, t)
	url = (url:sub(1, 1) == "/" and "" or "/") .. url
	if t == 1 then -- novel url
		url = "/fiction" .. url
	end
	return baseURL .. url
end

local function TriStateFilter_(int, str)
	if TriStateFilter then
		return TriStateFilter(int, str)
	else
		return CheckboxFilter(int, str)
	end
end

local function MultiTriStateFilter(offset, filter_ext, stop)
	local f={}
	for i=1,stop do
		f[#f+1] = TriStateFilter_(offset+i, filter_ext[i])
	end
	return f
end

local function createFilterString(data)
	local function emptyNil(str)
		if str == "" then
			return nil
		end
		return str
	end

	local statuses = {}
	for i=1,#STATUS_FILTER_EXT do
		if data[STATUS_FILTER_KEY+i] then
			statuses[#statuses+1] = STATUS_FILTER_INT[STATUS_FILTER_KEY+i]
		end
	end
	
	local order
	if data[ORDER_BY_FILTER_KEY] ~= 0 then
		order = ORDER_BY_FILTER_INT[data[ORDER_BY_FILTER_KEY]]
	end
	
	local dir
	if data[ORDER_FILTER_KEY] then
		dir = "asc"
	end
	
	local type
	if data[TYPE_FILTER_KEY] ~= 0 then
		type = TYPE_FILTER_INT[data[TYPE_FILTER_KEY]]
	end
	
	local tagsAdd, tagsRemove = {}, {}
	local function MultiTriQuery(strings, start, len)
		for i=start+1,start+len do
			if data[i] then
				if (data[i] == 2) then
					tagsRemove[#tagsRemove+1] = strings[i]
				elseif (data[i] == 1) then
					tagsAdd[#tagsAdd+1] = strings[i]
				end
			end
		end
	end
	
	MultiTriQuery(GENRES_FILTER_INT, GENRES_FILTER_KEY, #GENRES_FILTER_EXT)
	MultiTriQuery(TAGS_FILTER_INT, TAGS_FILTER_KEY, #TAGS_FILTER_EXT)
	MultiTriQuery(CONTENT_WARNINGS_FILTER_INT, CONTENT_WARNINGS_FILTER_KEY, #CONTENT_WARNINGS_FILTER_EXT)
	
	return "?"..qs({
		title = data[QUERY],
		keyword = emptyNil(data[KEYWORD_FILTER_KEY]),
		author = emptyNil(data[AUTHOR_FILTER_KEY]),
		minPages = emptyNil(data[PAGES_MIN_FILTER_KEY]),
		maxPages = emptyNil(data[PAGES_MAX_FILTER_KEY]),
		minRating = emptyNil(data[RATING_MIN_FILTER_KEY]),
		maxRating = emptyNil(data[RATING_MAX_FILTER_KEY]),
		status = statuses,
		orderBy = order,
		dir = dir,
		tagsAdd = tagsAdd,
		tagsRemove = tagsRemove,
		page = data[PAGE]
	})
end

local function parseListing(doc)
	local results = doc:selectFirst(".fiction-list")

	return mapNotNil(results:children(), function(v)
		local a = v:selectFirst(".fiction-title a")
		--No results matching these criteria were found
		if a then
			return Novel {
				title = a:text(),
				link = a:attr("href"):match("/fiction/(%d+)/.-"),
				imageURL = v:selectFirst("a img"):attr("src")
			}
		end
	end)
end

local function listing(name, inc, url)
	url = expandURL(url)
	return Listing(name, inc, function(data)
		-- ?genre= (instead of ?tagsAdd=) is the only working listing filter,
		-- so if any filter is used, switch from listing to search
		local filterstring = createFilterString(data)
		if filterstring ~= "?page=1" then
			url = expandURL("/fictions/search")
			inc = false --don't crash the site
		end
		return parseListing(GETDocument(url..filterstring..(inc and "&page="..data[PAGE] or "")))
	end)
end

local styleKeep = {
	["text-decoration"] = true
}

return {
	id = 36833,
	name = "RoyalRoad",
	baseURL = baseURL,
	imageURL = "https://gitlab.com/shosetsuorg/extensions/-/raw/dev/icons/RoyalRoad.png",
	chapterType = ChapterType.HTML,

	listings = {
		listing("Best Rated", true, "fictions/best-rated"),
		listing("Trending", false, "fictions/trending"),
		listing("Ongoing", true, "fictions/active-popular"),
		listing("Complete", true, "fictions/complete"),
		listing("Popular Weekly", true, "fictions/weekly-popular"),
		listing("Latest Updates", true, "fictions/latest-updates"),
		listing("New Releases", true, "fictions/new-releases"),
		listing("Rising Stars", false, "fictions/rising-stars")
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,

	parseNovel = function(url, loadChapters)
		local doc = GETDocument(baseURL.."/fiction/"..url.."/a")

		local page = doc:selectFirst(".page-content-inner")
		local header = page:selectFirst(".fic-header")
		local title = header:selectFirst(".fic-title")
		local info = page:selectFirst(".fiction-info")
		local type_status_genrestags = info:selectFirst(".margin-bottom-10")
		local novel_type = type_status_genrestags:selectFirst(".label")
		local genres_tags = type_status_genrestags:selectFirst(".tags")
		local content_warnings = info:selectFirst(".text-center")

		local s = mapNotNil(type_status_genrestags:select(":nth-child(2)"), function(v)
			local text = v:ownText()
			if text == "" or text ~= text:upper() then
				return
			end
			return text
		end)[1]

		s = s and ({
			COMPLETED = NovelStatus.COMPLETED,
			--DROPPED = NovelStatus.DROPPED,
			ONGOING = NovelStatus.PUBLISHING,
			HIATUS = NovelStatus.PAUSED,
			--STUB = NovelStatus.STUB,
		})[s] or NovelStatus.UNKNOWN

		local function tablecontains(t, e)
			for _, v in ipairs(t) do
				if e == v then
					return true
				end
			end
			return false
		end

		local genres = {}
		local tags = {}
		table.insert(tags, novel_type:text())
		mapNotNil(genres_tags:select("a"), function(a)
			local genre_tag = a:text()
			if tablecontains(GENRES_FILTER_EXT, genre_tag) then
				table.insert(genres, genre_tag)
			else
				table.insert(tags, genre_tag)
			end
		end)
		mapNotNil(content_warnings:select("li"), function(cw)
			table.insert(tags, cw:text())
		end)

		local description = HTMLToString(info:selectFirst(".description .hidden-content"))

		local text = function(v) return v:text() end
		local novel = NovelInfo {
			title = title:selectFirst("h1"):text(),
			imageURL = header:selectFirst("img"):attr("src"),
			description = description,
			genres = genres,
			tags = tags,
			authors = { title:selectFirst("h4 a"):text() },
			status = s
		}

		if loadChapters then
			local i = 0
			novel:setChapters(AsList(map(doc:selectFirst("#chapters tbody"):children(), function(v)
				local a = v:selectFirst("a")
				local a_time = v:selectFirst("time")
				i = i + 1
				return NovelChapter {
					order = i,
					title = a:text(),
					link = a:attr("href"),
					release = (a_time and (a_time:attr("title") or a_time:attr("unixtime") or v:selectLast("a"):text())) or nil
				}
			end)))
		end

		return novel
	end,

	getPassage = function(url)
		local chap = GETDocument(expandURL(url))
		local head = chap:selectFirst("head")
		chap = chap:selectFirst(".chapter-page")
		local title = chap:selectFirst(".fic-header h1"):text()
		chap = chap:selectFirst(".chapter-content")

		-- insert title at start of chapter
		chap:prepend("<h1>" .. title .. "</h1>")

		-- find hidden paragraphs

		local hiddenClasses = {}
		head:traverse(NodeVisitor(function(v)
			local tag = tostring(v)
			if v:tagName() == "style" and tag:find("display: none") then
				-- get the class name
				local class = string.sub(tag,tag:find("%.%w+{"))
				-- add it to the list, removing the { and .
				class = string.gsub(class,"[%.{]","")
				hiddenClasses[#hiddenClasses+1] = class
			end
		end))


		-- remove empty paragraphs & forced paragraph indents
		local toRemove = {}
		chap:traverse(NodeVisitor(function(v)
			-- remove hidden paragraphs (pirating warnings)
			for _, x in ipairs(hiddenClasses) do
				if v:attr("class")== x then
					toRemove[#toRemove+1] = v
				end
			end
			-- remove whitespace at the start of the paragraph
				if v:tagName() == "p" then
					local nodes = v:textNodes()
					if not nodes:isEmpty() then
						local tn = nodes:get(0)
						local o = tn:text()
						local s = o:gsub("^[ \n ]+", "")

						if s == "" and nodes:size() == 1 then
							toRemove[#toRemove+1] = v
						elseif o ~= s then
							tn:text(s)
						end
					end
				elseif v:parent():tagName() == "p" and v:elementSiblingIndex() == 0 then
					-- Trim leading whitespace from the first child of a paragraph,
					-- but don't remove wrapper elements like <span> that contain nested text.
					local nodes = v:textNodes()
					if not nodes:isEmpty() then
						local tn = nodes:get(0)
						local o = tn:text()
						local s = o:gsub("^[ \n ]+", "")

						if o ~= s then
					end
				end
			end

			if v:hasAttr("border") then
				v:removeAttr("border")
			end

			if v:hasAttr("align") then
				v:removeAttr("align")
			end

			if v:hasAttr("class") then
				v:removeAttr("class")
			end

			-- manually remove all style attributes except the useful ones
			-- TODO: if this becomes useful for other extensions, move this to a lib
			if v:hasAttr("style") then
				local s = ""
				for k,v in (v:attr("style")..";"):gmatch("(.-):%s*(.-);%s*") do
					if styleKeep[k] then
						s = s .. k .. ":" .. v .. ";"
					end
				end
				if s == "" then
					v:removeAttr("style")
				else
					v:attr("style", s)
				end
			end
		end, nil, true))

		for _,v in pairs(toRemove) do
			v:remove()
		end

		-- insert author notes
		local noteTitleStyle = "text-transform:uppercase;font-weight:700"
		map(chap:previousElementSiblings(), function(v)
			if v:hasClass("author-note-portlet") then
				v:selectFirst(".portlet-title"):attr("style", noteTitleStyle)
				chap:prepend("<hr>")
				chap:prepend(v)
			end
		end)

		map(chap:nextElementSiblings(), function(v)
			if v:hasClass("author-note-portlet") then
				v:selectFirst(".portlet-title"):attr("style", noteTitleStyle)
				chap:append("<hr>")
				chap:append(v)
			end
		end)

		return pageOfElem(chap, false, css)
	end,

	search = function(data)
		return parseListing(GETDocument(baseURL .. "/fictions/search" .. createFilterString(data)))
	end,
	isSearchIncrementing = false,
	searchFilters = {
		TextFilter(KEYWORD_FILTER_KEY, "Keyword (title or description)"),
		TextFilter(AUTHOR_FILTER_KEY, "Author name"),
		FilterGroup("Genres", MultiTriStateFilter(GENRES_FILTER_KEY, GENRES_FILTER_EXT, #GENRES_FILTER_EXT)),
		FilterGroup("Additional Tags", MultiTriStateFilter(TAGS_FILTER_KEY, TAGS_FILTER_EXT, #TAGS_FILTER_EXT)),
		FilterGroup("Content Warnings", MultiTriStateFilter(CONTENT_WARNINGS_FILTER_KEY, CONTENT_WARNINGS_FILTER_EXT, #CONTENT_WARNINGS_FILTER_EXT)),
		TextFilter(PAGES_MIN_FILTER_KEY, "Number of Pages min 0"), --todo number slider/selector
		TextFilter(PAGES_MAX_FILTER_KEY, "Number of Pages max 20000"),
		TextFilter(RATING_MIN_FILTER_KEY, "Rating min 0.0"),
		TextFilter(RATING_MAX_FILTER_KEY, "Rating max 5.0"),
		FilterGroup("Status", {
			CheckboxFilter(601, STATUS_FILTER_EXT[01]),
			CheckboxFilter(602, STATUS_FILTER_EXT[02]),
			CheckboxFilter(603, STATUS_FILTER_EXT[03]),
			CheckboxFilter(604, STATUS_FILTER_EXT[04]),
			CheckboxFilter(605, STATUS_FILTER_EXT[05]),
			CheckboxFilter(606, STATUS_FILTER_EXT[06]),
		}),
		DropdownFilter(ORDER_BY_FILTER_KEY, "Order by", ORDER_BY_FILTER_EXT),
		SwitchFilter(ORDER_FILTER_KEY, "Descending / Ascending"),
		DropdownFilter(TYPE_FILTER_KEY, "Type", TYPE_FILTER_EXT),
	},
}

end)()