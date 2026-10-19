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
-- {"id":4300,"ver":"1.1.2","libVer":"1.0.0","author":"MechTechnology"}

local baseURL = "https://rainofsnow.com"

-- Filter Keys & Values
local ORDER_BY_FILTER = 3
local ORDER_BY_VALUES = { "Popular", "Latest Update" }
local ORDER_BY_TERMS = { "novels", "latest-release" }
local GENRE_FILTER = 4
local GENRE_VALUES = { 
	"All", "Action", "Adventure", "Chinese", "Comedy", "Cultivation", "Drama", "Fantasy", "Japanese", "Korean", "Mystery", "Original Novel", "Romance",	"Sci-Fi"
 }
 local GENRE_TERMS = { 0,	16, 11, 342, 13, 15, 3, 7, 343, 341, 12, 339, 5, 14 }

local searchFilters = {
	DropdownFilter(ORDER_BY_FILTER, "Order by", ORDER_BY_VALUES),
	DropdownFilter(GENRE_FILTER, "Genre", GENRE_VALUES)
}

local encode = Require("url").encode

local text = function(v)
	return v:text()
end

local function shrinkURL(url)
	return url:gsub("^.-rainofsnow%.com", "")
end

local function expandURL(url)
	return baseURL .. url
end

local function getPassage(chapterURL)
	local chap = GETDocument(expandURL(chapterURL))
	local title = chap:selectFirst("li.menu-toc-current"):text()
	chap = chap:selectFirst(".zoomdesc-cont")
	chap:child(0):before("<h1>" .. title .. "</h1>")
	-- Remove empty <p> tags
	local toRemove = {}
	chap:traverse(NodeVisitor(function(v)
		if v:tagName() == "p" and v:text() == "" then
			toRemove[#toRemove+1] = v
		end
		if v:hasAttr("border") then
			v:removeAttr("border")
		end
	end, nil, true))
	for _,v in pairs(toRemove) do
		v:remove()
	end
	return pageOfElem(chap, true)
end

local function parseNovel(novelURL, loadChapters)
	local doc = GETDocument(expandURL(novelURL))
	local content = doc:selectFirst("div.queen")

	local info = NovelInfo {
		title = content:selectFirst("div.text > h2"):text(),
		imageURL = content:selectFirst("img"):attr("data-src"),
		description = table.concat(map(doc:selectFirst("div#synop"):select("p"), text), '\n'),
		authors = { content:selectFirst("ul.vbtcolor1"):child(1):selectFirst(".vt2"):text() },
		artists = {
			"Translator: " .. content:selectFirst("ul.vbtcolor1"):child(2):selectFirst(".vt2"):text(),
			"Editor: " .. content:selectFirst("ul.vbtcolor1"):child(3):selectFirst(".vt2"):text()
		},
		genres = map(content:selectFirst("ul.vbtcolor1"):child(4):selectFirst(".vt2"):select("a"), text),
		tags = map(content:selectFirst("ul.vbtcolor1"):child(6):selectFirst(".vt2"):select("a"), text)
	}

	if loadChapters then
		local chapters = {}
		chapters[#chapters+1] = (mapNotNil(content:selectFirst("#chapter ul.march1"):select("li"), function(v, i)
			return NovelChapter {
				order = i,
				title = v:selectFirst("a"):text(),
				link = shrinkURL(v:selectFirst("a"):attr("href")),
				release = v:selectFirst(".july"):text()
			}
		end))
		local chapterPages = content:selectFirst("a.next.page-numbers")
		-- Gets chapters from other pages if they exists!
		if chapterPages ~= nil then
			-- Removing the next button and looping throught the numbered page links
			content:select("a.next.page-numbers"):remove()
			map(content:select("a.page-numbers"), function(v)
				chapters[#chapters+1] = mapNotNil(GETDocument(v:attr("href")):selectFirst("#chapter ul.march1"):select("li"), function(v, i)
					return NovelChapter {
						order = i,
						title = v:selectFirst("a"):text(),
						link = shrinkURL(v:selectFirst("a"):attr("href")),
						release = v:selectFirst(".july"):text()
					}
					end)
			end)
		end
		info:setChapters(AsList(flatten(chapters)))
	end
	
	return info
end

local function parseListing(listingURL)
	local doc = GETDocument(listingURL)
	return map(doc:select("div.minbox"), function(v)
		local a = v:selectFirst("a")
		return Novel {
			title = a:attr("title"),
			link = shrinkURL(a:attr("href")),
			imageURL = v:selectFirst("img"):attr("data-src")
		}
	end)
end

local function getListing(data)
	local page = data[PAGE]
	local orderBy = data[ORDER_BY_FILTER]
	local genre = data[GENRE_FILTER]
	
	local url
	-- Genre filtering only works with popular order by.
	if genre ~= nil and genre ~= 0 then
		url = "/novels/" .. "?n_orderby=" .. GENRE_TERMS[genre+1]
	else
		url = "/" .. ORDER_BY_TERMS[orderBy+1] .. "/page/" .. page
	end

	return parseListing(expandURL(url))
end

local function getSearch(data)
	local docURL = expandURL("?s=" ..encode(data[QUERY]))
	return parseListing(docURL)
end

return {
	id = 4300,
	name = "Rain of Snow Translations",
	baseURL = baseURL,
	imageURL = "https://gitlab.com/shosetsuorg/extensions/-/raw/dev/icons/RainOfSnow.png",
	chapterType = ChapterType.HTML,
	
	listings = { 
		Listing("Popular", true, getListing), 
	},
	getPassage = getPassage,
	parseNovel = parseNovel,
	
	hasSearch = true,
	isSearchIncrementing = false,
	search = getSearch,
	searchFilters = searchFilters,

	shrinkURL = shrinkURL,
	expandURL = expandURL
}

end)()