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
-- {"id":95570,"ver":"1.1.0","libVer":"1.0.0","author":"Bigrand, Confident-hate","dep":["url>=1.0.0"]}

local baseURL = "https://www.novelhall.com"

local qs = Require("url").querystring

local function shrinkURL(url)
    return url:gsub("^https?://www%.novelhall%.com/", ""):gsub("^/", ""):gsub("/$", "")
end

local function expandURL(url)
    return baseURL .. "/" .. url
end

local GENRE_FILTER_ID = 2
local GENRE_VALUES = {
    "None",
    "Romance",
    "Fantasy",
    "Romantic",
    "Modern Romance",
    "CEO",
    "Urban",
    "Billionaire",
    "Action",
    "Modern Life",
    "Historical Romance",
    "Game",
    "Xianxia",
    "Sci-fi",
    "Historical",
    "Drama",
    "Fantasy Romance",
    "Urban Life",
    "Adult",
    "Comedy",
    "Harem",
    "Farming",
    "Military",
    "Adventure",
    "Wuxia",
    "Games",
    "Son-In-Law",
    "Ecchi",
    "Josei",
    "School Life",
    "Mystery"
}

local GENREPARAMS = {
    "", -- None
    "romance20223",
    "fantasy20223",
    "romantic3",
    "modern_romance",
    "ceo2022",
    "urban",
    "billionaire20223",
    "action3",
    "modern_life",
    "historical_romance2023",
    "game20233",
    "xianxia2022",
    "scifi",
    "historical2023",
    "drama20233",
    "fantasy_romance",
    "urban_life",
    "adult",
    "comedy3",
    "harem20223",
    "farming2023",
    "military2023",
    "adventure",
    "wuxia",
    "games3",
    "soninlaw2022",
    "ecchi",
    "josei",
    "school_life",
    "mystery"
}

local function trim(s)
    if s == "" then return "" end
    return string.match(s, "^%s*(.-)%s*$")
end

local function getPassage(chapterURL)
    local chapter = GETDocument(expandURL(chapterURL))
    local title = chapter:selectFirst("div.single-header > h1"):text()
    chapter = chapter:selectFirst("#htmlContent")

    -- Taken from novelvault
    -- Should be in a lib... eventually.
    local textNodes = {}
    local function collectTextNodes(node)
        for i = 0, node:childNodeSize() - 1 do
            local child = node:childNode(i)
            if child:nodeName() == "#text" and not child:isBlank() then
                table.insert(textNodes, trim(child:text()))
            else
                collectTextNodes(child)
            end
        end
    end
    collectTextNodes(chapter)

    chapter:empty()
    for _, paraText in ipairs(textNodes) do
        local para = chapter:appendElement("p")
        para:appendText(paraText)
    end

    chapter:prepend("<h1>" .. title .. "</h1>")
    return pageOfElem(chapter, true)
end

local function parseNovel(novelURL, loadChapters)
    local document = GETDocument(expandURL(novelURL))

    local title = document:selectFirst(".book-info h1"):text()
    -- Can't use a simple substring replacement because of weird symbols
    -- and corrupted bytes sequences
    local metaPattern = "^.*[:：]%s*(.-)%s*$"
    local author = document:selectFirst('.total span:containsOwn(Author)'):text():match(metaPattern)
    local status = document:selectFirst('.total span:containsOwn(Status)'):text():match(metaPattern)
    local genre = document:selectFirst(".total > a[href]"):text()

    local description = document:selectFirst(".intro .js-close-wrap")
    local backButton = description:selectFirst("span.blue")
    if backButton then backButton:remove() end
    description = description:text()

    local imageURL = document:selectFirst(".book-img img"):attr("src")

    local NovelInfo = NovelInfo {
        title = title,
        status = ({
            active = NovelStatus.PUBLISHING,
            completed = NovelStatus.COMPLETED,
        })[status:lower()] or NovelStatus.UNKNOWN,
        author = author,
        genres = { genre },
        description = description,
        imageURL = imageURL,
    }

    if loadChapters then
        local chapterElements = document:selectFirst("#morelist"):select("li")
        local i = 0
        local chapters = AsList(map(chapterElements, function(v)
            local a = v:selectFirst("a")
            local chapterTitle = a:text()
            local link = shrinkURL(a:attr("href"))

            i = i + 1
            return NovelChapter {
                order = i,
                title = chapterTitle,
                link = link,
            }
        end))
        NovelInfo:setChapters(chapters)
    end

    return NovelInfo
end

local function parseNovelElements(elements)
    return map(elements, function(v)
        local a = v:selectFirst("a")
        return Novel {
            title = a:text(),
            link = shrinkURL(a:attr("href"))
        }
    end)
end

local function search(data)
    local query = data[QUERY]
    local url = qs({ s = "so", module = "book", keyword = query }, baseURL .. "/index.php")
    local doc = GETDocument(url)

    local useless = doc:select(".w30, .hidden-xs")
    if useless then useless:remove() end

    local results = doc:select("tbody > tr > td")
    return parseNovelElements(results)
end

local function parseListing(listingURL)
    local document = GETDocument(listingURL)
    local elements = document:select(".w70")
    return parseNovelElements(elements)
end

local function getListing(name, inc, sortString)
    -- Workaround around filter not retrieving additional pages
    -- when on a non-incrementing listing
    local isIncrementing = inc
    inc = true
    return Listing(name, inc, function(data)
        local genre = data[GENRE_FILTER_ID]
        local page = data[PAGE]

        local isListing = true
        local url
        if genre and genre ~= 0 then
            local genreValue = GENREPARAMS[genre+1]
            isListing = false
            url = expandURL("genre/" .. genreValue .. "/" .. page)
        end

        if isListing then
            if not isIncrementing and page > 1 then return {} end

            if name == "Completed" then
                local prefix = sortString:sub(1, 9)
                local suffix = sortString:sub(10)
                -- completed.html pagination is completed-`page`.html
                url = expandURL(prefix .. "-" .. page .. suffix)
            else
                url = expandURL(sortString)
            end
        end

        return parseListing(url)
    end)
end

return {
    id = 95570,
    name = "NovelHall",
    baseURL = baseURL,
    imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/NovelHall.png",
    hasSearch = true,
    isSearchIncrementing = false,
    search = search,

    listings = {
        getListing("Completed", true, "completed.html"),
        getListing("Power Ranking", false, "ranking.html"),
        getListing("Trending", false, "trending.html"),
        getListing("Latest Novel", false, "new.html"),
        getListing("Latest Release", false, "lastupdate.html")
    },

    parseNovel = parseNovel,
    getPassage = getPassage,
    chapterType = ChapterType.HTML,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
    searchFilters = {
        DropdownFilter(GENRE_FILTER_ID, "Genre", GENRE_VALUES)
    }
}

end)()