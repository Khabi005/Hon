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
__modules["novelvault"] = function()
-- {"ver":"1.0.11","author":"Bigrand","dep":["url>=1.0.0", "unhtml>=1.0.0"]}

local qs = Require("url").querystring
local unhtml = Require("unhtml")
local HTMLToString = unhtml.HTMLToString
local trim = unhtml.trim

local toText = function(v)
    return v:text()
end

-- BRIEF WARNING!!!
-- 
-- Certain defaults aren't actually defined by default. 
-- It may crash the entire app if you don't set them up. 
-- The exact ones are unknown, as it doesn't log a stack trace
-- but it's probably `listingConfigs`, `supportedFilters`, `genres`, and/or `statuses`.
-- Anyway, it shouldn't be a problem as long as you set up the extension correctly :D
local defaults = {
    hasCloudFlare = false,
    hasSearch = true,
    chapterType = ChapterType.HTML,
    isSearchIncrementing = true,

    -- Some sources don't have an exclusive path for novels
    --
    -- For example,
    -- - with special path: `.com/novel/i-kissed-your-mom`
    -- - with no special path: `.com/i-kissed-your-mom.html`
    --
    -- Used to expand or shrink the URLs accordingly
    novelParam = nil,

    authorParam = "author", -- Source's exclusive path for authors. Used to build the authors CSS selector
    genreParam = "genre", -- Source's exclusive path for genres. Used to build the genre CSS selector
    tagParam = "tag", -- Source's exclusive path for tags. Used to build the tags CSS Selector.
    searchParam = "search", -- Source's exclusive path for searches. Used to build the search URL

    genreSpace = "+", -- Used to generate genre params. Character that replaces spaces.

    -- If this is set to `""` (empty string), it will append just the number to the URL.
    -- Meaning that instead of `popular?page=X`, you will get `popular/X`.
    pageParam = "page", -- Used to build the search URL. Refers to this part: `?page=X`

    -- This lib doesn't support paginated chapters because I'm tired.
    -- I've been working on this for too much time, and I'm sick of it.
    -- Total known sources affected by this: 1 (novellive.app) :D
    --
    -- AJAX endpoint to get chapters. No fallback.
    -- Known endpoints are:
    -- `"ajax-chapter-option"`, `"ajax/chapter-archive"` and `"get_chapter_list"`.
    -- If chapters are obtained through the novel's page, you must set `ajaxChaptersURL` to `"noajax"`.
    ajaxChaptersURL = "ajax-chapter-option",
    novelIdParam = "novelId", -- This is the query used to fetch chapters via the AJAX endpoint.

    novelIdAttribute = "data-novel-id", -- This ID is used to fetch chapters
    novelIdPattern   = nil, -- Use pattern matching on the novel's URL instead if the novel ID isn't accessible by attribute.

    -- Listings builder.
    -- Just add the name, whether it's paginated or not and its path.
    -- Example:
    -- ```lua
    -- listingConfigs = {
    --      { name = "Hot Novel", incrementing = true, param = "sort/hot-novel"},
    --      -- add or remove rows here as needed
    -- }
    -- ```
    listingConfigs = {},

    -- Must be overridden to enable filters.
    -- Possible options:
    -- `"genre"`, `"author"`, `"tag"` and `"status"`
    supportedFilters = {},
    genres = {}, -- Only define if its filter is enabled in `supportedFilters`

    -- Statuses are technically listings, but they are also relevant as filters.
    -- So, add them as filters and listings. Why not? :D
    --
    -- Example:
    -- ```lua
    -- statuses = {
    --     { name = "Ongoing",  param = "sort/nov-love-ongoing" },
    --     { name = "Completed",param = "sort/nov-love-completed" },
    --     -- Add or remove entries as needed.
    -- }
    -- ```
    statuses = {}, -- Only define this if the status filter is enabled in `supportedFilters`.

    -- Some sources provide search results through POST requests instead of GET.
    isSearchPOST = false,

    -- Most sources use low-resolution images with weird aspect ratios for search results.
    -- Luckily, some have a predictable URL pattern that can be modified to get the full resolution image.
    -- If the extension defines `searchImgModFunc`, it will inject the function to modify the image URL. Otherwise, the original `imageURL` is returned.
    -- The injected functions receives and must return an expanded image URL string.
    --
    -- Note: Shosetsu may fetch different HTML than a regular browser, so image URLs can vary.
    -- Some sources do provide low-resolution images with the correct aspect ratio (even if they serve different ratios to regular browsers).
    searchImgModFunc = nil,

    customStyle = "", -- Inject custom CSS for passages. Useful for RTL support.

    -- Used to build the correct chapter URL when the AJAX chapter URLs redirect to a different domain.
    -- This is specifically made for mirrors where chapter links redirect to `novelbin.com`,
    -- even though the chapters are also hosted on the domain using an alternate path.
    -- If defined, use `novelParam` with `chapterNovelParam` for chapter URLs only.
    --
    -- For example:
    --   - `novelbin.me/novel-book/<novelid>/chapter-1` → redirects to `novelbin.com`'s chapter URL
    --   - `novelbin.me/b/<novelid>/chapter-1` → directly serves the chapter
    --
    -- If the source has this problem:
    -- Both `novelParam` and `chapterNovelParam` must be defined to correctly build the correct URL.
    chapterNovelParam = nil,

    -- Element Selectors:
    -- `selectWithFallback()` tries each function in order. Ideally, one function checks multiple 
    -- CSS selectors by combining them into a single multi-selector string. If necessary, multiple 
    -- functions can be used, and it will check each one until a valid result (not falsey or an empty string) is found.
    -- These functions can be customized per extension without needing to update the library.
    -- All processing should be done inside the functions, which must return the expected type and value for the field.

    -- Yeah, it's kinda messy, but I want to avoid constantly updating this lib or hardcoding fixes.
    -- So I added function injection support for all selectors to keep things flexible,
    -- even if it's not the most efficient or cleaniest solution.
    -- Multiple functions are supported because it's a remnant of an old refactor.
    -- Removing it would require another refactor (idk actually), and I really don't want to do that for less features :D
    -- And why do I keep commenting useless shit? Because I'm lonely, so suck it up :DDD

    listingSelector = {
        function(el)
            local listing = el:select(".archive .list .row, .ul-list1.ul-list1-2.ss-custom .li-row")
            return listing
        end
    },

    listingTitleSelector = {
        function(el)
            local title = el:selectFirst(".novel-title, .truyen-title, .tit")
            if not title then
                error("No results found...")
            end
            return title and title:text()
        end
    },

    listingLinkSelector = {
        function(el)
            local link = el:selectFirst(".novel-title a, .truyen-title a, .tit a")
            return link and link:attr("href")
        end
    },

    -- Used by `getImgURL()`, so it must fetch the listing covers or the novel's cover
    imageURLAttribute = {
        function(el)
            local img = el:selectFirst("img.cover, .pic img") or el:selectFirst("div.book img, .m-imgtxt img")
            if not img then return nil end

            local src = img:attr("src")
            if src and src ~= "" then return src end

            local dataSrc = img:attr("data-src")
            if dataSrc and dataSrc ~= "" then return dataSrc end

            local cfsrc = img:attr("data-cfsrc")
            if cfsrc and cfsrc ~= "" then return cfsrc end

            return "NO_IMAGE_AVAILABLE"
        end
    },

    titleSelector = ".title, .m-desc > .tit",

    descriptionSelector = ".desc-text, .txt > .inner",

    altNamesSelector = {
        function(el)
            local altNames = {}
            local altNamesElement = el:selectFirst(
                ".info > li:has(h3:containsOwn(lternative))," ..
                ".info > div:has(h3:containsOwn(lternative))," ..
                'div.txt span[title="Alternative names"] + div.right span.s1'
            )

            if altNamesElement then
                local h3 = altNamesElement:selectFirst("h3")

                if h3 then
                    h3:remove()
                end

                local text = altNamesElement:text()
                for name in string.gmatch(text, '([^,]+)') do
                    table.insert(altNames, trim(name))
                end
            end

            return altNames
        end
    },

    statusSelector = {
        function(el)
            local status = el:selectFirst(
                ".info .text-primary," ..
                ".info > div:has(h3:containsOwn(tatus)) > a," ..
                ".info > div:has(h3:contains(tatus)) > h3:nth-of-type(2)," ..
                'div.txt span[title="Status"] + div.right span.s1'
            )

            return status:text()
        end
    },

    tagsSelector = {
        function(self, el)
            local tags = el:select(
                '.info a[href*="/'.. self.tagParam .. '/"],' ..
                '.txt a[href*="/'.. self.tagParam .. '/"]'
            )
            return map(tags, toText)
        end
    },

    genresSelector = {
        function(self, el)
            local genres = el:select(
                '.info a[href*="/'.. self.genreParam .. '/"],' ..
                '.m-imgtxt > .txt a[href*="/' .. self.genreParam ..'/"]'
            )

            if genres:isEmpty() then
                genres = el:select(
                    ".info > div:has(h3:containsOwn(enre)) > a," ..
                    ".info > li:has(h3:containsOwn(enre)) > a"
                )
            end

            return map(genres, toText)
        end
    },

    authorSelector = {
        function(self, el)
            local authors = el:select(
                '.info a[href*="/' .. self.authorParam .. '/"],' ..
                '.m-imgtxt > .txt a[href*="/' .. self.authorParam .. '/"]'
            )

            if authors:isEmpty() then
                authors = el:select(
                    ".info > div:has(h3:containsOwn(uthor)) > a," ..
                    ".info > li:has(h3:containsOwn(uthor)) > a"
                )
            end

            return map(authors, toText)
        end
    },

    chapterTitleSelector = {
        function(el)
            local chapTitle = el:selectFirst(".chapter-heading-text, .chapter-text, .chr-title, .wp > .top > span")
            return chapTitle and chapTitle:text()
        end
    },

    chapterContentSelector = {
        function(el)
            local chapSelector = "#chr-content, #chapter-content, .wp > .txt"
            local chapContent = el:selectFirst(chapSelector)

            local usedSelector = nil
            if chapContent then
                if chapContent:id() == "chr-content" then
                    usedSelector = "#chr-content"
                elseif chapContent:id() == "chapter-content" then
                    usedSelector = "#chapter-content"
                else
                    usedSelector = ".wp > .txt"
                end
            end

            return chapContent, usedSelector -- Returns the CSS selector for passage processing
        end
    },

    chapterFetchSelector = {
        function(doc)
            local links = doc:select(".m-newest2 > .ul-list5 > li > a")
            if not links:isEmpty() then
                return links, "ul"
            end

            links = doc:select("select option")
            if not links:isEmpty() then
                return links, "select"
            end

            -- NovelBin AJAX chapter archive
            links = doc:select("li[data-chapter-item] a")
            if not links:isEmpty() then
                return links, "list"
            end

            links = doc:select(".list-chapter li a")
            if not links:isEmpty() then
                return links, "list"
            end

            -- Specific to Light Novel Plus
            links = doc:select("pre"):text()
            links = Document(links)
            links = links:select("select option")
            if not links:isEmpty() then
                return links, "select"
            end

            error("Error: Couldn't fetch chapter links.")
        end
    }
}

-- Ideally, each extension would define the exact CSS selector,
-- but requiring that makes extensions annoying to add and test.
--
--- @param element Element          -- The element to match selectors against.
--- @param selectorFuncs function[] -- Array of functions that take an element and return element(s). For example, `el:selectFirst(".title"):text()`.          
local function selectWithFallback(element, selectorFuncs, context, msg)
    if type(context) == "string" and msg == nil then
        msg, context = context, nil
    end

    for _, fn in ipairs(selectorFuncs) do
        local results

        if context then
            results = { fn(context, element) }
        else
            results = { fn(element) }
        end

        if #results > 0 then
            local allValid = true

            for _, value in ipairs(results) do
                if not value or value == "" then
                    allValid = false
                    break
                end
            end

            if allValid then
                return table.unpack(results)
            end
        end
    end

    error("Error: All selectors failed. " .. (msg and ("type: " .. msg) or "") )
end

-- Automatically, generates the URL params used by the genre filter.
-- If it doesn't follow lowercase and hyphens for spaces format
-- then you must set it yourself inside `self.genres` using `param`
--
---@return table genreParams
function defaults:generateGenreParams()
    local out = { "" }
    for i, item in ipairs(self.genres) do
        local name, param

        if type(item) == "table" then
            name  = item.name or ""
            param = item.param or ""
            out[i+1] = param
        else
            name  = item
            param = name:lower():gsub(" ", self.genreSpace)
            out[i+1] = self.genreParam .. "/" .. param
        end
    end
    return out
end

-- gsub does pattern-based replacements, not literal substring replacements.
-- This function escapes all Lua pattern-matching characters in the `substring`,
-- so Lua doesn't interpret it as a pattern.
--
--- @param s string        The input string in which to perform replacements.
--- @param substring string The exact substring to be replaced (treated literally).
--- @param replacement string The string to replace each occurrence with.
--- @return string
--- @return integer nReplacements
local function replace(s, substring, replacement)
    local escaped = substring:gsub("(%p)", "%%%1")
    return s:gsub(escaped, replacement)
end

function defaults:expandURL(url)
    if self.novelParam then
        return self.baseURL .. "/" .. self.novelParam .. "/" .. url
    end

    return self.baseURL .. "/" .. url
end

function defaults:shrinkURL(url)
    if self.novelParam then
        return replace(url, self.baseURL .. "/" .. self.novelParam .. "/", "")
    end

    return replace(url, self.baseURL .. "/", "")
end


---@param imageURL string 
---@return string modifiedImageURL
function defaults:getFullSizeImage(imageURL)
    local finalImageURL = imageURL

    if self.searchImgModFunc then
        finalImageURL = self.searchImgModFunc(imageURL)
    end

    return finalImageURL
end

---@return string
function defaults:getImgURL(el)
    local imageURL = selectWithFallback(el, self.imageURLAttribute, "img")

    -- Basically, normalizes the URL so it's always an expanded one.
    -- Can't use `expandURL()` because it's used for novel URLs
    if not imageURL:match("^https?://") then
        imageURL = imageURL:match("^/(.*)") or imageURL
        imageURL = self.baseURL .. "/" .. imageURL
    end

    return imageURL
end

function defaults:searchPOST(query)
    local payload = "searchkey=" .. query
    local MTYPE = MediaType("application/x-www-form-urlencoded")
    local body = RequestBody(payload, MTYPE)

    -- Not sure if it's necessary, but whatever lol
    local HEADERS = HeadersBuilder()
        :add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        :add("Accept-Language", "en-US,en;q=0.5")
        :add("Content-Type", "application/x-www-form-urlencoded")
        :add("Origin", self.baseURL)
        :add("DNT", "1")
        :add("Sec-GPC", "1")
        :add("Connection", "keep-alive")
        :add("Referer", self.baseURL .. "/" .. self.searchParam)
        :build()

    local results = RequestDocument(POST(self.baseURL .. "/" .. self.searchParam, HEADERS, body))

    return results
end

-- Some sources repeat the last page's results when there are no more pages
-- causing duplicate entries. If `page` is passed, we compare the current results with the last ones.
-- If they're the same, we return empty results and stop Shosetsu from loading more pages.
local lastSeen = nil

function defaults:parseListing(listingURL, page, postQuery)
    local document

    -- `postQuery` is only provided if `isSearchPOST` is true
    if postQuery then
        document = self.searchPOST(postQuery)
    else
        document = GETDocument(listingURL)
    end

    local listing = selectWithFallback(document, self.listingSelector, "listing")

    local current = listing:text()
    if page then
        if page > 1 and lastSeen == current then
            return {}
        end

        lastSeen = current
    end

    return map(listing, function(v)
        local title = selectWithFallback(v, self.listingTitleSelector, "listingTitle")

        local imageURL = self.getImgURL(v)
        imageURL = self.getFullSizeImage(imageURL)

        local link = selectWithFallback(v, self.listingLinkSelector, "listingLink")
        link = self.shrinkURL(link)
        link = link:match("^/(.*)") or link
        link = link

        return Novel {
            title = title,
            imageURL = imageURL,
            link = link
        }
    end)
end

function defaults:search(data)
    local userQuery = data[QUERY]
    local currentPage = data[PAGE]
    local url = qs({ keyword = userQuery, [self.pageParam] = currentPage}, self.baseURL .. "/" .. self.searchParam)

    -- A bad way to to do it but the document is requested inside `parseListing()`
    if self.isSearchPOST then
        return self.parseListing(url, currentPage, userQuery)
    end

    return self.parseListing(url, currentPage)
end

function defaults:getPassage(chapterURL)
    local url = self.expandURL(chapterURL)

    if self.chapterNovelParam and self.novelParam then
        url = replace(url, self.novelParam, self.chapterNovelParam)
    end

    local document = GETDocument(url)

    local title = selectWithFallback(document, self.chapterTitleSelector, "title")
    local chapter, chapSelector = selectWithFallback(document, self.chapterContentSelector, "chapterContent")

    -- Maybe using the tail would be better but whatever
    local toRemove = {}
    chapter:traverse(NodeVisitor(function (v)
        local tag = v:tagName()
        if not v:hasText() then
            table.insert(toRemove, v)
        end

        if tag == "iframe" or tag == "script" then
            table.insert(toRemove, v)
        end
    end), function()end, true)

    for _, node in ipairs(toRemove) do
        node:remove()
    end

    toRemove = {}
    chapter:traverse(NodeVisitor(function (v)
        local tag = v:tagName()

        -- Remove that one annoying <br> between paragraphs - Specific to NovLove but others could benefit too
        -- This doesn't account for stray text nodes, which means it could potentially remove useful
        -- <br> tags and the like. BUT! I don't care, so won't fix :D
        if tag == "br" then
            local previous = v:previousElementSibling()
            local next = v:nextElementSibling()

            if previous and next and previous:tagName() == "p" and next:tagName() == "p" then
                table.insert(toRemove, v)
            end
        end
    end, function()end, true)) -- Enable elements only to avoid crashes

    for _, node in ipairs(toRemove) do
        node:remove()
    end

    if chapter:hasAttr("style") then
        chapter:removeAttr("style")
    end

    -- Remove duplicated titles
    -- The CSS selector (and others) could be simplified by using a simple `:is()`, 
    -- but for some reason, I can't get it working :DDDDD
    local headingTags = { "h1", "h2", "h3", "h4", "h5", "h6", "p" }
    local selectorParts = {}
    for _, tag in ipairs(headingTags) do
        table.insert(selectorParts, chapSelector .. " " .. tag)
    end

    local selector = table.concat(selectorParts, ", ")
    local dupEl = document:selectFirst(selector)
    local titleLower = trim(title):gsub("^\239\187\191", ""):gsub("%c+", ""):lower()
    local prefixLen = math.min(#titleLower, 9)
    local titlePrefix = titleLower:sub(1, prefixLen)

    -- This only checks the very first text of the chapter.
    -- Meaning that it doesn't detect double or more duplicated titles.
    -- It's probably an easy fix? Yes. Will I do it? No. I'm sick of all of this :D
    if dupEl and dupEl:text():lower():find(titlePrefix, 1, true) then
        local dupText = dupEl:text()
        dupEl:remove()

        local _, count = dupText:lower():gsub(titlePrefix, "")

        local ratioLimit = 1.8
        local okLength = #dupText <= ratioLimit * #title

        local isSuitableDup = count < 2 and (#dupText > #title and okLength)

        -- The reason we are keeping the duplicated title and removing the original one  
        -- is that sometimes the duplicated title is correctly ripped off and has more info  
        -- or correct formatting than the one in the index. So, that's why we check for length.
        if isSuitableDup then
            chapter:prepend("<h1>" .. dupText .. "</h1>")
        else
            chapter:prepend("<h1>" .. title .. "</h1>")
        end
    else
        chapter:prepend("<h1>" .. title .. "</h1>")
    end

    -- Remove watermark
    local watermarkElement = document:selectFirst(chapSelector .. " > p:last-child")
    if watermarkElement and string.find(watermarkElement:text():lower(), "source:", 1, true) then
        watermarkElement:remove()
    end

    -- Remove premium buttons - Specific to NovLove, NovelBin
    local premiumElement = document:selectFirst(".unlock-buttons")
    if premiumElement then
        premiumElement:remove()
    end

    -- Remove error report suggestion - Specific to NovelFull
    local suggestionElement = document:selectFirst(chapSelector .. " > div:last-of-type")
    if suggestionElement and string.find(suggestionElement:text():lower(), "report chapter", 1, true) then
        suggestionElement:remove()
    end

    return pageOfElem(chapter, false, self.customStyle)
end

local function parseSelectChapter(element)
    local chapTitle = element:text()
    local chapLink = element:attr("value")

    return { title = chapTitle, link = chapLink }
end

local function parseListChapter(element)
    local titleElement = element:selectFirst(".nchr-text") or element

    local isPremium = titleElement:selectFirst(".premium-label")
    local isPaid = titleElement:selectFirst(".paid-label")

    if isPremium or isPaid then
        return nil
    end

    local chapTitle = element:attr("title")
    if not chapTitle or chapTitle == "" then
        chapTitle = element:text()
    end
    local chapLink = element:attr("href")

    return { title = chapTitle, link = chapLink }
end

local function parseUlChapter(element)
    local chapTitle = element:text()
    local chapLink = element:attr("href")

    return { title = chapTitle, link = chapLink }
end

function defaults:parseNovel(novelURL, loadChapters)
    local url = self.expandURL(novelURL)
    local document = GETDocument(url)

    local title = document:selectFirst(self.titleSelector)
    if not title then
        error("Error: Novel not found. Contact developers.")
    end
    title = title:text()

    local novelID = document:selectFirst("div[" .. self.novelIdAttribute .. "]")
    if self.ajaxChaptersURL ~= "noajax" then
        if self.novelIdPattern then
            novelID = string.match(url, self.novelIdPattern)
        elseif novelID then
            novelID = novelID:attr(self.novelIdAttribute)
        else
            error("Error: Couldn't get novel ID. Contact developers.")
        end
    end

    local imageURL = self.getImgURL(document)
    local description = HTMLToString(document:selectFirst(self.descriptionSelector))
    local altNames = selectWithFallback(document, self.altNamesSelector, "altNames")
    local status = selectWithFallback(document, self.statusSelector, "status")
    local tags = selectWithFallback(document, self.tagsSelector, self, "tags")
    local genres = selectWithFallback(document, self.genresSelector, self, "genres")
    local authors = selectWithFallback(document, self.authorSelector, self, "authors")

    local NovelInfo = NovelInfo {
        title = title,
        alternativeTitles = altNames,
        imageURL = imageURL,
        description = description,
        status = ({
            Ongoing = NovelStatus.PUBLISHING,
            OnGoing = NovelStatus.PUBLISHING,
            Completed = NovelStatus.COMPLETED,
        })[status] or NovelStatus.UNKNOWN,
        tags = tags,
        genres = genres,
        authors = authors,
    }

    if loadChapters then
        if self.chapterFetcher then
            NovelInfo:setChapters(self.chapterFetcher(self, url, document))
        else
        local lastFreeChapterNum = nil
        local latestChapterEl = document:selectFirst(".l-chapter .chapter-title")
        if latestChapterEl then
            local latestText = latestChapterEl:text()
            local num = latestText:match("[Cc]hapter%s+(%d+)")
            if num then
                lastFreeChapterNum = tonumber(num)
            end
        end

        local chapterIndexURL
        chapterIndexURL = qs({[self.novelIdParam] = novelID}, self.baseURL .. "/" .. self.ajaxChaptersURL)

        local chapterIndexDoc
        if self.ajaxChaptersURL ~= "noajax" then
            chapterIndexDoc = GETDocument(chapterIndexURL)
        else
            chapterIndexDoc = document
        end
        local chapterLinks, method = selectWithFallback(chapterIndexDoc, self.chapterFetchSelector, "chapterFetch")

        local i = 0
        local chapters = AsList(mapNotNil(chapterLinks, function(v)
            local parsed

            if method == "select" then
                parsed = parseSelectChapter(v)
            elseif method == "list" then
                parsed = parseListChapter(v)
            else
                parsed = parseUlChapter(v)
            end

            if not parsed or not parsed.title or not parsed.link then
                return nil
            end

            -- Skip chapters beyond the last free chapter
            if lastFreeChapterNum then
                local chNum = parsed.title:match("[Cc]hapter%s+(%d+)")
                if chNum and tonumber(chNum) > lastFreeChapterNum then
                    return nil
                end
            end

            local link = parsed.link
            link = link:match("^/(.*)") or self.shrinkURL(link)
            link = link

            i = i + 1 -- explicitly calculate order
            return NovelChapter {
                order = i,
                title = parsed.title,
                link = link
            }
        end))

        NovelInfo:setChapters(chapters)
        end -- chapterFetcher else
    end

    return NovelInfo
end

local GENRE_FILTER_ID = 2
local AUTHOR_FILTER_ID = 3
local STATUS_FILTER_ID = 4
local TAG_FILTER_ID = 5
function defaults:getListing(name, inc, sortString)
    return Listing(name, inc, function(data)
        local page   = data[PAGE]
        local genre  = data[GENRE_FILTER_ID]
        local author = data[AUTHOR_FILTER_ID]
        local status = data[STATUS_FILTER_ID]
        local tag    = data[TAG_FILTER_ID]

        -- `getListing()` also handles filter URL building.
        -- We need to know if it's a normal listing or a filter listing.
        local isListing = true
        local url

        if genre and genre ~= 0 then
            -- `generateGenreParams()` should handle path building.
            local GENRE_PARAMS = self:generateGenreParams()
            local genreValue = GENRE_PARAMS[genre + 1]

            url = self.baseURL .. "/" .. genreValue
            isListing = false
        end

        if author and author ~= "" and isListing then
            url = self.baseURL .. "/" .. self.authorParam .. "/" .. author
            isListing = false
        end

        if status and status ~= 0 and isListing then
            local STATUS_PARAMS = self.statuses
            local statusValue = STATUS_PARAMS[status].param

            url = self.baseURL .. "/" .. statusValue
            isListing = false
        end

        if tag and tag ~= "" and isListing then
            url = self.baseURL .. "/" .. self.tagParam .. "/" .. tag:upper()
            isListing = false
        end

        if isListing then
            url = self.baseURL .. "/" .. sortString
        end

        if page and page > 1 and inc then
            local sep = url:find("?", 1, true) and "&" or "?"
            if self.pageParam and self.pageParam ~= "" then
                url = url .. sep .. self.pageParam .. "=" .. page
            else
                url = url .. "/" .. page
            end
        end

        return self.parseListing(url, page)
    end)
end

function defaults:getFilters()
    local filters = {}
    local priorityOrder = { "genre", "author", "status", "tag" }

    if #self.supportedFilters > 1 then
        local activeFilters = {}
        for _, f in ipairs(self.supportedFilters) do
            activeFilters[f] = true
        end

        local priorityList = {}
        for _, key in ipairs(priorityOrder) do
            if activeFilters[key] then
                table.insert(priorityList, key)
            end
        end

        local priorityNote = "Note: Filters can't be combined. Use one at the time. (Reset)\n" ..
                             "Priority: " .. table.concat(priorityList, " > ")

        table.insert(filters, RadioGroupFilter(1000, priorityNote, {}))
    end

    for _, v in ipairs(self.supportedFilters) do
        if v == "genre" then
            local genres = { "None" }
            for _, item in ipairs(self.genres) do
                if type(item) == "table" then
                    table.insert(genres, item.name)
                else
                    table.insert(genres, item)
                end
            end
            table.insert(filters, DropdownFilter(GENRE_FILTER_ID, "Genre", genres))
        elseif v == "author" then
            table.insert(filters, TextFilter(AUTHOR_FILTER_ID, "Author Name (Single)"))
        elseif v == "status" then
            local statuses = { "All" }
            for _, status in ipairs(self.statuses) do
                table.insert(statuses, status.name)
            end
            table.insert(filters, DropdownFilter(STATUS_FILTER_ID, "Status", statuses))
        else
            table.insert(filters, TextFilter(TAG_FILTER_ID, "Tag (Single)"))
        end
    end

    return filters
end

return function(baseURL, _self)
    -- An extension can't override a default with nil.
    _self = setmetatable(_self or {}, { __index = function(_, k)
        local d = defaults[k]
        return (type(d) == "function" and wrap(_self, d) or d)
    end })

    _self["baseURL"] = baseURL
    _self["searchFilters"] = _self.getFilters()

    local listings = {}
    for _, cfg in ipairs(_self.listingConfigs) do
        table.insert(listings, _self.getListing(cfg.name, cfg.incrementing, cfg.param))
    end
    _self["listings"] = listings

    return _self
end

end
return (function()
-- {"id":111359,"ver":"1.0.0","libVer":"1.0.0","author":"Bigrand","dep":["novelvault>=1.0.0"]}

return Require("novelvault")("https://novgo.net", {
	id = 111359,
	name = "Novgo (NET)",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/NovgoNET.png",

	listingConfigs = {
		{ name = "Hot Novel", incrementing = true, param = "hot-novel" },
		{ name = "Most Popular", incrementing = true, param = "most-popular" },
		{ name = "Completed Novel", incrementing = true, param = "completed-novel" },
		{ name = "Ongoing Novel", incrementing = true, param = "status/Ongoing" },
		{ name = "Latest Release", incrementing = true, param = "latest-release-novel" },
	},

	supportedFilters = { "genre", "author", "status" },

	statuses = {
        { name = "Ongoing",   param = "status/Ongoing" },
        { name = "Completed", param = "completed-novel" },
	},

	genres = {
		"Action",
		"Adult",
		"Adventure",
		"Comedy",
		"Drama",
		"Eastern",
		"Ecchi",
		"Fantasy",
		"Game",
		"Gender Bender",
		"Harem",
		"Hentai",
		"Historical",
		"Horror",
		"Isekai",
		"Josei",
		"LGBT+",
		"Lolicon",
		"Magic",
		"Magical",
		"Magical Realism",
		"Manhua",
		"Martial",
		"Martial Arts",
		"Mature",
		"Mecha",
		"Mystery",
		"Psychological",
		"Reincarnation",
		"Romance",
		"School Life",
		"Sci-fi",
		"Seinen",
		"Shoujo",
		"Shoujo AI",
		"Shounen",
		"Shounen AI",
		"Slice of Life",
		"Smut",
		"Sports",
		"Supernatural",
		"System",
		"Traged",
		"Tragedy",
		"Video Games",
		"Wuxia",
		"Xianxia",
		"Xuanhuan",
		"Yaoi",
		"Yuri",
	}
})

end)()