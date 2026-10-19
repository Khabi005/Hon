-- Bundled from https://raw.githubusercontent.com/capthehacker99/ShosetLazyExtensions/master/; original sources retained in third_party/shosetsu.
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
__modules["bigint"] = function()
-- {"ver":"1.0.0","author":"Emily empyreuma"}
-- 3-Clause BSD License

-- Copyright (c) Emily "empyreuma" 2016
-- All rights reserved.

-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--     * Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--     * Neither the name of the <organization> nor the
--       names of its contributors may be used to endorse or promote products
--       derived from this software without specific prior written permission.

-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
-- LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-- If this variable is true, then strict type checking is performed for all
-- operations. This may result in slower code, but it will allow you to catch
-- errors and bugs earlier.
local strict = true

--------------------------------------------------------------------------------

local bigint = {}

local function assert(con, msg)
    if not con then
        error(msg)
    end
end

-- Create a new bigint or convert a number or string into a big
-- Returns an empty, positive bigint if no number or string is given
function bigint.new(num)
    local self = {
        sign = "+",
        digits = {}
    }

    -- Return a new bigint with the same sign and digits
    function self:clone()
        local newint = bigint.new()
        newint.sign = self.sign
        for _, digit in pairs(self.digits) do
            newint.digits[#newint.digits + 1] = digit
        end
        return newint
    end

    setmetatable(self, {
        __add = function(lhs, rhs)
            return bigint.add(lhs, rhs)
        end,
        __unm = function()
            if (self.sign == "+") then
                self.sign = "-"
            else
                self.sign = "+"
            end
            return self
        end,
        __sub = function(lhs, rhs)
            return bigint.subtract(lhs, rhs)
        end,
        __mul = function(lhs, rhs)
            return bigint.multiply(lhs, rhs)
        end,
        __div = function(lhs, rhs)
            return bigint.divide(lhs, rhs)
        end,
        __mod = function(lhs, rhs)
            local result, remainder = bigint.divide(lhs, rhs)
            return result
        end,
        __pow = function(lhs, rhs)
            return bigint.exponentiate(lhs, rhs)
        end
    })

    if (num) then
        local num_string = tostring(num)
        for digit in string.gmatch(num_string, "[0-9]") do
            table.insert(self.digits, tonumber(digit))
        end
        if string.sub(num_string, 1, 1) == "-" then
            self.sign = "-"
        end
    end

    return self
end

-- Check the type of a big
-- Normally only runs when global variable "strict" == true, but checking can be
-- forced by supplying "true" as the second argument.
function bigint.check(big, force)
    if (strict or force) then
        assert(#big.digits > 0, "bigint is empty")
        assert(type(big.sign) == "string", "bigint is unsigned")
        for _, digit in pairs(big.digits) do
            assert(type(digit) == "number", digit .. " is not a number")
            assert(digit < 10, digit .. " is greater than or equal to 10")
        end
    end
    return true
end

-- Return a new big with the same digits but with a positive sign (absolute
-- value)
function bigint.abs(big)
    bigint.check(big)
    local result = big:clone()
    result.sign = "+"
    return result
end

-- Convert a big to a number or string
function bigint.unserialize(big, output_type, precision)
    bigint.check(big)

    local num = ""
    if big.sign == "-" then
        num = "-"
    end


    if ((output_type == nil)
    or (output_type == "number")
    or (output_type == "n")
    or (output_type == "string")
    or (output_type == "s")) then
        -- Unserialization to a string or number requires reconstructing the
        -- entire number

        for _, digit in pairs(big.digits) do
            num = num .. math.floor(digit) -- lazy way of getting rid of .0$
        end

        if ((output_type == nil)
        or (output_type == "number")
        or (output_type == "n")) then
            return tonumber(num)
        else
            return num
        end

    else
        -- Unserialization to human-readable form or scientific notation only
        -- requires reading the first few digits
        if (precision == nil) then
            precision = 3
        else
            assert(precision > 0, "Precision cannot be less than 1")
            assert(math.floor(precision) == precision,
                   "Precision must be a positive integer")
        end

        -- num is the first (precision + 1) digits, the first being separated by
        -- a decimal point from the others
        num = num .. big.digits[1]
        if (precision > 1) then
            num = num .. "."
            for i = 1, (precision - 1) do
                num = num .. big.digits[i + 1]
            end
        end

        if ((output_type == "human-readable")
        or (output_type == "human")
        or (output_type == "h")) then
            -- Human-readable output contributed by 123eee555

            local name
            local walkback = 0 -- Used to enumerate "ten", "hundred", etc

            -- Walk backwards in the index of named_powers starting at the
            -- number of digits of the input until the first value is found
            for i = (#big.digits - 1), (#big.digits - 4), -1 do
                name = named_powers[i]
                if (name) then
                    if (walkback == 1) then
                        name = "ten " .. name
                    elseif (walkback == 2) then
                        name = "hundred " .. name
                    end
                    break
                else
                    walkback = walkback + 1
                end
            end

            return num .. " " .. name

        else
            return num .. "*10^" .. (#big.digits - 1)
        end

    end
end

-- Basic comparisons
-- Accepts symbols (<, >=, ~=) and Unix shell-like options (lt, ge, ne)
function bigint.compare(big1, big2, comparison)
    bigint.check(big1)
    bigint.check(big2)

    local greater = false -- If big1.digits > big2.digits
    local equal = false

    if (big1.sign == "-") and (big2.sign == "+") then
        greater = false
    elseif (#big1.digits > #big2.digits)
    or ((big1.sign == "+") and (big2.sign == "-")) then
        greater = true
    elseif (#big1.digits == #big2.digits) then
        -- Walk left to right, comparing digits
        for digit = 1, #big1.digits do
            if (big1.digits[digit] > big2.digits[digit]) then
                greater = true
                break
            elseif (big2.digits[digit] > big1.digits[digit]) then
                break
            elseif (digit == #big1.digits)
                   and (big1.digits[digit] == big2.digits[digit]) then
                equal = true
            end
        end

    end

    -- If both numbers are negative, then the requirements for greater are
    -- reversed
    if (not equal) and (big1.sign == "-") and (big2.sign == "-") then
        greater = not greater
    end

    return (((comparison == "<") or (comparison == "lt"))
            and ((not greater) and (not equal)) and true)
        or (((comparison == ">") or (comparison == "gt"))
            and ((greater) and (not equal)) and true)
        or (((comparison == "==") or (comparison == "eq"))
            and (equal) and true)
        or (((comparison == ">=") or (comparison == "ge"))
            and (equal or greater) and true)
        or (((comparison == "<=") or (comparison == "le"))
            and (equal or not greater) and true)
        or (((comparison == "~=") or (comparison == "!=") or (comparison == "ne"))
            and (not equal) and true)
        or false
end

-- BACKEND: Add big1 and big2, ignoring signs
function bigint.add_raw(big1, big2)
    bigint.check(big1)
    bigint.check(big2)

    local result = bigint.new()
    local max_digits = 0
    local carry = 0

    if (#big1.digits >= #big2.digits) then
        max_digits = #big1.digits
    else
        max_digits = #big2.digits
    end

    -- Walk backwards right to left, like in long addition
    for digit = 0, max_digits - 1 do
        local sum = (big1.digits[#big1.digits - digit] or 0)
                  + (big2.digits[#big2.digits - digit] or 0)
                  + carry

        if (sum >= 10) then
            carry = 1
            sum = sum - 10
        else
            carry = 0
        end

        result.digits[max_digits - digit] = sum
    end

    -- Leftover carry in cases when #big1.digits == #big2.digits and sum > 10, ex. 7 + 9
    if (carry == 1) then
        table.insert(result.digits, 1, 1)
    end

    return result

end

-- BACKEND: Subtract big2 from big1, ignoring signs
function bigint.subtract_raw(big1, big2)
    -- Type checking is done by bigint.compare
    assert(bigint.compare(bigint.abs(big1), bigint.abs(big2), ">="),
           "Size of " .. bigint.unserialize(big1, "string") .. " is less than "
           .. bigint.unserialize(big2, "string"))

    local result = big1:clone()
    local max_digits = #big1.digits
    local borrow = 0

    -- Logic mostly copied from bigint.add_raw ---------------------------------
    -- Walk backwards right to left, like in long subtraction
    for digit = 0, max_digits - 1 do
        local diff = (big1.digits[#big1.digits - digit] or 0)
                   - (big2.digits[#big2.digits - digit] or 0)
                   - borrow

        if (diff < 0) then
            borrow = 1
            diff = diff + 10
        else
            borrow = 0
        end

        result.digits[max_digits - digit] = diff
    end
    ----------------------------------------------------------------------------


    -- Strip leading zeroes if any, but not if 0 is the only digit
    while (#result.digits > 1) and (result.digits[1] == 0) do
        table.remove(result.digits, 1)
    end

    return result
end

-- FRONTEND: Addition and subtraction operations, accounting for signs
function bigint.add(big1, big2)
    -- Type checking is done by bigint.compare

    local result

    -- If adding numbers of different sign, subtract the smaller sized one from
    -- the bigger sized one and take the sign of the bigger sized one
    if (big1.sign ~= big2.sign) then
        if (bigint.compare(bigint.abs(big1), bigint.abs(big2), ">")) then
            result = bigint.subtract_raw(big1, big2)
            result.sign = big1.sign
        else
            result = bigint.subtract_raw(big2, big1)
            result.sign = big2.sign
        end

    elseif (big1.sign == "+") and (big2.sign == "+") then
        result = bigint.add_raw(big1, big2)

    elseif (big1.sign == "-") and (big2.sign == "-") then
        result = bigint.add_raw(big1, big2)
        result.sign = "-"
    end

    return result
end
function bigint.subtract(big1, big2)
    -- Type checking is done by bigint.compare in bigint.add
    -- Subtracting is like adding a negative
    local big2_local = big2:clone()
    if (big2.sign == "+") then
        big2_local.sign = "-"
    else
        big2_local.sign = "+"
    end
    return bigint.add(big1, big2_local)
end

-- BACKEND: Multiply a big by a single digit big, ignoring signs
function bigint.multiply_single(big1, big2)
    bigint.check(big1)
    bigint.check(big2)
    assert(#big2.digits == 1, bigint.unserialize(big2, "string")
                              .. " has more than one digit")

    local result = bigint.new()
    local carry = 0

    -- Logic mostly copied from bigint.add_raw ---------------------------------
    -- Walk backwards right to left, like in long multiplication
    for digit = 0, #big1.digits - 1 do
        local this_digit = big1.digits[#big1.digits - digit]
                         * big2.digits[1]
                         + carry

        if (this_digit >= 10) then
            carry = math.floor(this_digit / 10)
            this_digit = this_digit - (carry * 10)
        else
            carry = 0
        end

        result.digits[#big1.digits - digit] = this_digit
    end

    -- Leftover carry in cases when big1.digits[1] * big2.digits[1] > 0
    if (carry > 0) then
        table.insert(result.digits, 1, carry)
    end
    ----------------------------------------------------------------------------

    return result
end

-- FRONTEND: Multiply two bigs, accounting for signs
function bigint.multiply(big1, big2)
    -- Type checking done by bigint.multiply_single

    local result = bigint.new(0)
    local larger, smaller -- Larger and smaller in terms of digits, not size

    if (bigint.unserialize(big1) == 0) or (bigint.unserialize(big2) == 0) then
        return result
    end

    if (#big1.digits >= #big2.digits) then
        larger = big1
        smaller = big2
    else
        larger = big2
        smaller = big1
    end

    -- Walk backwards right to left, like in long multiplication
    for digit = 0, #smaller.digits - 1 do
        -- Sorry for going over column 80! There's lots of big names here
        local this_digit_product = bigint.multiply_single(larger,
                                                          bigint.new(smaller.digits[#smaller.digits - digit]))

        -- "Placeholding zeroes"
        if (digit > 0) then
            for placeholder = 1, digit do
                table.insert(this_digit_product.digits, 0)
            end
        end

        result = bigint.add(result, this_digit_product)
    end

    if (larger.sign == smaller.sign) then
        result.sign = "+"
    else
        result.sign = "-"
    end

    return result
end


-- Raise a big to a positive integer or big power (TODO: negative integer power)
function bigint.exponentiate(big, power)
    -- Type checking for big done by bigint.multiply
    assert(bigint.compare(power, bigint.new(0), ">"),
           " negative powers are not supported")
    local exp = power:clone()

    if (bigint.compare(exp, bigint.new(0), "==")) then
        return bigint.new(1)
    elseif (bigint.compare(exp, bigint.new(1), "==")) then
        return big
    else
        local result = big:clone()

        while (bigint.compare(exp, bigint.new(1), ">")) do
            result = bigint.multiply(result, big)
            exp = bigint.subtract(exp, bigint.new(1))
        end

        return result
    end

end

-- BACKEND: Divide two bigs (decimals not supported), returning big result and
-- big remainder
-- WARNING: Only supports positive integers
function bigint.divide_raw(big1, big2)
    -- Type checking done by bigint.compare
    if (bigint.compare(big1, big2, "==")) then
        return bigint.new(1), bigint.new(0)
    elseif (bigint.compare(big1, big2, "<")) then
        return bigint.new(0), big1:clone()
    else
        assert(bigint.compare(big2, bigint.new(0), "!="), "error: divide by zero")
        assert(big1.sign == "+", "error: big1 is not positive")
        assert(big2.sign == "+", "error: big2 is not positive")

        local result = bigint.new()

        local dividend = bigint.new() -- Dividend of a single operation, not the
                                      -- dividend of the overall function
        local divisor = big2:clone()
        local factor = 1

        -- Walk left to right among digits in the dividend, like in long
        -- division
        for _, digit in pairs(big1.digits) do
            dividend.digits[#dividend.digits + 1] = digit

            -- The dividend is smaller than the divisor, so a zero is appended
            -- to the result and the loop ends
            if (bigint.compare(dividend, divisor, "<")) then
                if (#result.digits > 0) then -- Don't add leading zeroes
                    result.digits[#result.digits + 1] = 0
                end
            else
                -- Find the maximum number of divisors that fit into the
                -- dividend
                factor = 0
                while (bigint.compare(divisor, dividend, "<=")) do
                    divisor = bigint.add(divisor, big2)
                    factor = factor + 1
                end

                -- Append the factor to the result
                if (factor == 10) then
                    -- Fixes a weird bug that introduces a new bug if fixed by
                    -- changing the comparison in the while loop to "<="
                    result.digits[#result.digits] = 1
                    result.digits[#result.digits + 1] = 0
                else
                    result.digits[#result.digits + 1] = factor
                end

                -- Subtract the divisor from the dividend to obtain the
                -- remainder, which is the new dividend for the next loop
                dividend = bigint.subtract(dividend,
                                           bigint.subtract(divisor, big2))

                -- Reset the divisor
                divisor = big2:clone()
            end

        end

        -- The remainder of the final loop is returned as the function's
        -- overall remainder
        return result, dividend
    end
end

-- FRONTEND: Divide two bigs (decimals not supported), returning big result and
-- big remainder, accounting for signs
function bigint.divide(big1, big2)
    local result, remainder = bigint.divide_raw(bigint.abs(big1),
                                                bigint.abs(big2))
    if (big1.sign == big2.sign) then
        result.sign = "+"
    else
        result.sign = "-"
    end

    return result, remainder
end

-- FRONTEND: Return only the remainder from bigint.divide
function bigint.modulus(big1, big2)
    local result, remainder = bigint.divide(big1, big2)

    -- Remainder will always have the same sign as the dividend per C standard
    -- https://en.wikipedia.org/wiki/Modulo_operation#Remainder_calculation_for_the_modulo_operation
    remainder.sign = big1.sign
    return remainder
end

return bigint

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
-- {"id":1339243358,"ver":"1.1.8","libVer":"1.0.10","author":"","repo":"","dep":[]}
local dkjson = Require("dkjson")
local bigint = Require("bigint")
--- Identification number of the extension.
--- Should be unique. Should be consistent in all references.
---
--- Required.
---
--- @type int
local id = 1339243358

--- Name of extension to display to the user.
--- Should match index.
---
--- Required.
---
--- @type string
local name = "MVLEMPYR"

--- Base URL of the extension. Used to open web view in Shosetsu.
---
--- Required.
---
--- @type string
local baseURL = "https://www.mvlempyr.com/"

--- URL of the logo.
---
--- Optional, Default is empty.
---
--- @type string
local imageURL = "https://assets.mvlempyr.com/images/asset/LogoMage.webp"
--- ChapterType provided by the extension.
---
--- Optional, Default is STRING. But please do HTML.
---
--- @type ChapterType
local chapterType = ChapterType.HTML

--- Index that pages start with. For example, the first page of search is index 1.
---
--- Optional, Default is 1.
---
--- @type number
local startIndex = 1

--- Shrink the website url down. This is for space saving purposes.
---
--- Required.
---
--- @param url string Full URL to shrink.
--- @param _ int Either KEY_CHAPTER_URL or KEY_NOVEL_URL.
--- @return string Shrunk URL.
local function shrinkURL(url, _)
    return url
end

--- Expand a given URL.
---
--- Required.
---
--- @param url string Shrunk URL to expand.
--- @param _ int Either KEY_CHAPTER_URL or KEY_NOVEL_URL.
--- @return string Full URL.
local function expandURL(url, _)
	return url
end

--- Get a chapter passage based on its chapterURL.
---
--- Required.
---
--- @param chapterURL string The chapters shrunken URL.
--- @return string Strings in lua are byte arrays. If you are not outputting strings/html you can return a binary stream.
local function getPassage(chapterURL)
	local url = expandURL(chapterURL):gsub("(%w+://[^/]+)%.io", "%1.io")

	--- Chapter page, extract info from it.
	local document = GETDocument(url)
    local htmlElement = document:selectFirst("#chapter")
    return pageOfElem(htmlElement, true)
end

local function calculateTagId(novel_code)
    local t = bigint.new("1999999997")
    local c = bigint.modulus(bigint.new("7"), t);
    local d = tonumber(novel_code);
    local u = bigint.new(1);
    while d > 0 do
        -- print(bigint.unserialize(t, "string"), bigint.unserialize(c, "string"), d, bigint.unserialize(u, "string"))
        if (d % 2) == 1 then
            u = bigint.modulus((u * c), t)
        end
        c = bigint.modulus((c * c), t);
        d = math.floor(d/2);
    end
    return bigint.unserialize(u, "string")
end

--- Load info on a novel.
---
--- Required.
---
--- @param novelURL string shrunken novel url.
--- @return NovelInfo
local function parseNovel(novelURL)
	local url = expandURL(novelURL)

	--- Novel page, extract info from it.
	local document = GETDocument(url)
    local desc = ""
    map(document:select(".synopsis p"), function(p)
        desc = desc .. '\n' .. p:text()
    end)
    local img = document:selectFirst("img.novel-image2")
    img = img and img:attr("src") or imageURL
    local novel_code = document:selectFirst("#novel-code"):text()
    local headers = HeadersBuilder():add("Origin", "https://www.mvlempyr.com"):build()
    local chapters = {}
    local page = 1
    repeat
        local chapter_data = dkjson.GET("https://chap.heliosarchive.online/wp-json/wp/v2/posts?tags=" .. calculateTagId(novel_code) .. "&per_page=500&page=" .. page, headers)
        for i, v in next, chapter_data do
            table.insert(chapters, NovelChapter {
                order = v.acf.chapter_number,
                title = v.acf.ch_name,
                link = shrinkURL(v.link):gsub("chap.heliosarchive.online", "www.mvlempyr.io")
            })
        end
        page = page + 1
    until #chapter_data < 500
	return NovelInfo({
        title = document:selectFirst(".novel-title2"):text():gsub("\n" ,"www.mvlempyr.io"),
        imageURL = img,
        description = desc,
        chapters = chapters
    })
end

local function getListing(data)
    local data = dkjson.GET("https://chap.heliosarchive.online/wp-json/wp/v2/mvl-novels?per_page=100&offset=" .. (100 * data[PAGE] - 100))
    local novels = {}
    for _, novel in next, data do
        table.insert(novels, Novel {
            title = novel.name,
            link = "https://www.mvlempyr.io/novel/" .. novel.slug,
            imageURL = "https://assets.mvlempyr.io/images/600/" .. novel["novel-code"] .. ".webp"
        })
    end
    return novels
end

local searchHelper = {}

local function search(data)
    local matched = data[QUERY]:match("/novel/(.*)")
    if matched then
        return AsList({
            Novel {
                title = "URL Import",
                link = "https://www.mvlempyr.io/novel/" .. matched,
                imageURL = imageURL
            }
        })
    end
    local query = data[QUERY]:lower()
    local origPage = data[PAGE]
    local page = origPage
    if searchHelper[query] == nil then
        searchHelper = {[query] = {}}
    else
        page = searchHelper[query][page - 1]
        if page == nil then
            page = origPage
        else
            page = page + 1
        end
    end
    local novels = {}
    local idx = 0
    while #novels == 0 and idx < 200 do
        local data = dkjson.GET("https://chap.heliosarchive.online/wp-json/wp/v2/mvl-novels?per_page=200&offset=" .. (200 * page - 200))
        for _, novel in next, data do
            if novel.name:lower():match(query) then
                table.insert(novels, Novel {
                    title = novel.name,
                    link = "https://www.mvlempyr.io/novel/" .. novel.slug,
                    imageURL = "https://assets.mvlempyr.io/images/600/" .. novel["novel-code"] .. ".webp"
                })
            end
        end
        page = page + 1
        idx = idx + 1
    end
    searchHelper[query][origPage] = page
    return novels
end

-- Return all properties in a lua table.
return {
	-- Required
	id = id,
	name = name,
	baseURL = baseURL,
	listings = {
        Listing("Default", true, getListing)
    }, -- Must have at least one listing
	getPassage = getPassage,
	parseNovel = parseNovel,
	shrinkURL = shrinkURL,
	expandURL = expandURL,
    hasSearch = true,
    isSearchIncrementing = true,
    hasCloudFlare = true,
    search = search,
	imageURL = imageURL,
	chapterType = chapterType,
	startIndex = startIndex,
}

end)()