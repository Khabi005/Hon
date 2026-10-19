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
-- {"id":3,"ver":"2.2.5","libVer":"1.0.0","author":"Bigrand, Doomsdayrs","dep":["url>=1.0.0"]}

local baseURL = "https://yomou.syosetu.com"
local passageURL = "https://ncode.syosetu.com"

local encode = Require("url").encode

local function getTotalPages(html)
	local lastPageLink = html:select(".c-pager__item--last"):attr("href")
	if lastPageLink then
		local totalPages = tonumber(lastPageLink:match("p=(%d+)"))

		return totalPages or 1
	end
	return 1
end

---@param url string
local function shrinkURL(url)
	return url:gsub(passageURL, "")
end

---@param url string
local function expandURL(url)
	return passageURL .. url
end

local function parseResults(document)
	return mapNotNil(document:select(".smpnovel_list"), function(v)
		local titleElement = v:selectFirst(".novel_h")
		local linkElement = v:selectFirst(".read_button")

		if not titleElement and not linkElement then
			return nil
		end

		local title = titleElement:text()
		local link = shrinkURL(linkElement:attr("href"))

		return Novel({
			title = title,
			link = link
		})
	end)
end

local function search(data)
	local url = baseURL .. "/search.php?&word=" .. encode(data[0]) .. "&type=re&p=" .. data[PAGE]
	local document = GETDocument(url)

	return parseResults(document)
end

local function parseListing(filter, data)
	if data[PAGE] == 0 then
		data[PAGE] = 1
	end

	local url = baseURL .. filter .. data[PAGE]
	local document = GETDocument(url)

	return parseResults(document)
end

local function getPassage(chapterURL)
	local document = GETDocument(passageURL .. chapterURL)
	local chapTitle = document:selectFirst(".p-novel__subtitle-episode"):text()
	local chapter = document:selectFirst(".p-novel__text")
	chapter:prepend("<h1>" .. chapTitle .. "</h1>")

	return pageOfElem(chapter, false)
end

local function parseNovel(novelURL, loadChapters)
	local document = GETDocument(passageURL .. novelURL)
	local author = { document:selectFirst(".p-novel__author a"):text() }

	if not author[1] then
		error("Error: Author not found!")
	end

	local title = document:selectFirst(".p-novel__title"):text()

	local descriptionElement = document:selectFirst(".p-novel__summary")
	local description = ""
	if descriptionElement then
		description = tostring(descriptionElement):gsub("<br%s*/?>", "\n")
		:gsub("<[^>]->", "")
		:gsub("\n%s*\n+", "\n\n")
		:gsub("^%s+", "")
		:gsub("%s+$", "")
	end

	local NovelInfo = NovelInfo {
		title = title,
		link = novelURL,
		language = "jpn",
		description = description,
		authors = author
	}

	if loadChapters then
		local chapters = {}
		local totalPages = getTotalPages(document)
		for page = 1, totalPages do
			local pageURL = novelURL .. "?p=" .. page

			local pageDocument = GETDocument(passageURL .. pageURL)
			map(pageDocument:select(".p-eplist__sublist"), function(v)
				local chap = NovelChapter()
				local chapterElement = v:selectFirst(".p-eplist__subtitle")
				local chapTitle = chapterElement:text()
				local link = chapterElement:attr("href")
				local release = v:selectFirst(".p-eplist__update"):text()

				chap:setTitle(chapTitle)
				chap:setLink(link)
				chap:setRelease(release)
				table.insert(chapters, chap)
			end)
		end
		NovelInfo:setChapters(AsList(chapters))
	end

	return NovelInfo 
end

return {
	id = 3,
	name = "Syosetsu",
	baseURL = baseURL,
	imageURL = "https://gitlab.com/shosetsuorg/extensions/-/raw/dev/icons/Syosetsu.png",
	hasCloudFlare = false,
	hasSearch = true,
	chapterType = ChapterType.HTML,
	getPassage = getPassage,
	parseNovel = parseNovel,
	shrinkURL = shrinkURL,
	expandURL = expandURL,
	search = search,
	isSearchIncrementing = true,
	startIndex = 1,

	listings = {
		Listing("Most Weekly Views", true, function(data)
			return parseListing("/search.php?type=re&order=weekly&p=", data)
		end),
		Listing("Latest Published", true, function(data)
			return parseListing("/search.php?type=re&order=new&notnizi=1&p=", data)
		end),
		Listing("Most Bookmarked", true, function(data)
			return parseListing("/search.php?type=re&order=favnovelcnt&p=", data)
		end),
		Listing("Most Reviews", true, function(data)
			return parseListing("/search.php?type=re&order=reviewcnt&p=", data)
		end),
		Listing("Highest Overall Points", true, function(data)
			return parseListing("/search.php?type=re&order=hyoka&p=", data)
		end),
		Listing("Highest Daily Points", true, function(data)
			return parseListing("/search.php?type=re&order=dailypoint&p=", data)
		end),
		Listing("Highest Weekly Points", true, function(data)
			return parseListing("/search.php?type=re&order=weeklypoint&p=", data)
		end),
		Listing("Highest Monthly Points", true, function(data)
			return parseListing("/search.php?type=re&order=monthlypoint&p=", data)
		end),
		Listing("Highest Quarterly Points", true, function(data)
			return parseListing("/search.php?type=re&order=quarterpoint&p=", data)
		end),
		Listing("Highest Yearly Points", true, function(data)
			return parseListing("/search.php?type=re&order=yearlypoint&p=", data)
		end),
		Listing("Most Raters", true, function(data)
			return parseListing("/search.php?type=re&order=hyokacnt&p=", data)
		end),
		Listing("Most Words", true, function(data)
			return parseListing("/search.php?type=re&order=lengthdesc&p=", data)
		end),
		Listing("Oldest Published", true, function(data)
			return parseListing("/search.php?type=re&order=generalfirstup&p=", data)
		end),
		Listing("Oldest Updates", true, function(data)
			return parseListing("/search.php?type=re&order=old&p=", data)
		end)
	}
}

end)()