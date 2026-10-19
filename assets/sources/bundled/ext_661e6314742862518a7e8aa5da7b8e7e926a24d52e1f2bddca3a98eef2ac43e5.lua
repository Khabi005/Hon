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
-- {"id":1308639979,"ver":"1.0.0","libVer":"1.0.0","author":"JFronny, Jobobby04, capthehacker99"}

local url = Require("url")

local baseURL = "https://www.fanfiction.net"
local SORT_ID = 2 -- srt
local SortOptions = {
    {name = "Update Date", value = "1"},
    {name = "Publish Date", value = "2"},
    {name = "Reviews", value = "3"},
    {name = "Favorites", value = "4"},
    {name = "Follows", value = "5"}
}

local RATING_ID = 6 -- r
local RatingOptions = {
    {name = "All", value = "10"},
    {name = "Rated K -> T", value = "103"},
    {name = "Rated K -> K+", value = "102"},
    {name = "Rated K", value = "1"},
    {name = "Rated K+", value = "2"},
    {name = "Rated T", value = "3"},
    {name = "Rated M", value = "4"}
}

local TIME_RANGE_ID = 3 -- t
local TimeRangeOptions = {
    {name = "All", value = "0"},
    {name = "Updated within 24 hours", value = "1"},
    {name = "Updated within 1 week", value = "2"},
    {name = "Updated within 1 month", value = "3"},
    {name = "Updated within 6 months", value = "4"},
    {name = "Updated within 1 year", value = "5"},
    {name = "Published within 24 hours", value = "11"},
    {name = "Published within 1 week", value = "12"},
    {name = "Published within 1 month", value = "13"},
    {name = "Published within 6 months", value = "14"},
    {name = "Published within 1 year", value = "15"}
}

local GENRE_A_ID = 4 -- g1
local GENRE_B_ID = 5 -- g2
local GENRE_EXCLUDE_ID = 10 -- _g1
local GenreOptions = {
    {name = "All", value = "0"},
    {name = "Adventure", value = "6"},
    {name = "Angst", value = "10"},
    {name = "Crime", value = "18"},
    {name = "Drama", value = "4"},
    {name = "Family", value = "19"},
    {name = "Fantasy", value = "14"},
    {name = "Friendship", value = "21"},
    {name = "General", value = "1"},
    {name = "Horror", value = "8"},
    {name = "Humor", value = "3"},
    {name = "Hurt/Comfort", value = "20"},
    {name = "Mystery", value = "7"},
    {name = "Parody", value = "9"},
    {name = "Poetry", value = "5"},
    {name = "Romance", value = "2"},
    {name = "Sci-Fi", value = "13"},
    {name = "Spiritual", value = "15"},
    {name = "Supernatural", value = "11"},
    {name = "Suspense", value = "12"},
    {name = "Tragedy", value = "16"},
    {name = "Western", value = "17"}
}
local genreByNameToValue = {}
for _, option in ipairs(GenreOptions) do
    genreByNameToValue[option.name] = option.value
end

local LANGUAGE_ID = 7 -- lan
local LanguageOptions = {
    {name = "Language", value = "0"},
    {name = "Bahasa Indonesia", value = "32"},
    {name = "Català", value = "34"},
    {name = "Deutsch", value = "4"},
    {name = "Eesti", value = "41"},
    {name = "English", value = "1"},
    {name = "Español", value = "2"},
    {name = "Esperanto", value = "22"},
    {name = "Français", value = "3"},
    {name = "Italiano", value = "11"},
    {name = "Język polski", value = "13"},
    {name = "LINGUA LATINA", value = "35"},
    {name = "Magyar", value = "14"},
    {name = "Nederlands", value = "7"},
    {name = "Norsk", value = "18"},
    {name = "Português", value = "8"},
    {name = "Slovenčina", value = "43"},
    {name = "Suomi", value = "20"},
    {name = "Svenska", value = "17"},
    {name = "čeština", value = "31"},
    {name = "Русский", value = "10"},
    {name = "Українська", value = "44"},
    {name = "עברית", value = "15"},
    {name = "ภาษาไทย", value = "38"},
    {name = "中文", value = "5"},
    {name = "日本語", value = "6"}
}

local LENGTH_ID = 8 -- len
local LengthOptions = {
    {name = "All", value = "0"},
    {name = "< 1K words", value = "11"},
    {name = "< 5K words", value = "51"},
    {name = "> 1K words", value = "1"},
    {name = "> 5K words", value = "5"},
    {name = "> 10K words", value = "10"},
    {name = "> 20K words", value = "20"},
    {name = "> 40K words", value = "40"},
    {name = "> 60K words", value = "60"},
    {name = "> 100K words", value = "100"}
}

local STATUS_ID = 9 -- s
local StatusOptions = {
    {name = "All", value = "0"},
    {name = "In-Progress", value = "1"},
    {name = "Complete", value = "2"}
}

local function optionNames(options)
    local out = {}
    for _, option in ipairs(options) do
        table.insert(out, option.name)
    end
    return out
end

local function shrinkURL(url)
    url = url or ""
    url = url:gsub("^https?://[^/]*fanfiction%.net", "")
    url = url:gsub("^//[^/]*fanfiction%.net", "")
    return url
end

local function expandURL(url)
    url = url or ""
    if url:find("^https?://") then
        return url
    end
    if url:find("^//") then
        return "https:" .. url
    end
    if url:sub(1, 1) ~= "/" then
        url = "/" .. url
    end
    return baseURL .. url
end

local function dropdownValue(options, filterValue, defaultIndex)
    local idx = tonumber(filterValue)
    if idx == nil then
        -- legacy / unexpected string name
        for i, option in ipairs(options) do
            if option.name == filterValue then
                return option.value
            end
        end
        return options[defaultIndex or 1].value
    end
    local option = options[idx + 1]
    if option == nil then
        return options[defaultIndex or 1].value
    end
    return option.value
end

local function storyIdFromURL(url)
    url = shrinkURL(url)
    return url:match("/s/(%d+)")
end

local function normalizeNovelURL(url)
    -- mobile UI is different and has less info
    url = url:gsub("^https?://m%.fanfiction%.net", "https://www.fanfiction.net")
    local id = storyIdFromURL(url)
    if id then
        return "/s/" .. id
    end
    return shrinkURL(url)
end

local STORY_TEXT_SELECTOR = "#storytext, #storycontent, .storytextp .storytext"

---@param contentSelector string
---@param ... string
---@return Document, string
local function fetchDocument(contentSelector, ...)
    local args = table.pack(...)
    local firstDocument = nil
    for i = 1, args.n do
        local path = args[i]
        local document = GETDocument(expandURL(path))
        if i == 1 then
            firstDocument = document
        end
        if document:selectFirst(contentSelector) ~= nil then
            return document
        end

        -- check for message 1 (not found/cached), otherwise try fallback
        local bodyText = document:text() or ""
        if not (bodyText:find("FanFiction.Net Message Type 1", 1, true) or bodyText:find("Story does not have any chapters", 1, true)) then
            return document
        end
    end

    return firstDocument
end

---@param chapterPath string
---@return string
local function getPassage(chapterPath)
    -- Some stories publish text only on /s/{id}/ and reject /s/{id}/1/ with Message Type 1
    local storyId = storyIdFromURL(chapterPath)
    local fallbackPath = storyId ~= nil and "/s/" .. storyId or chapterPath
    local document
    if storyId ~= nil and ((chapterPath == "/s/" .. storyId .. "/1") or (chapterPath == "/s/" .. storyId .. "/1/")) then
        document = fetchDocument(STORY_TEXT_SELECTOR, chapterPath, chapterPath .. "/", fallbackPath, fallbackPath .. "/")
    else
        document = fetchDocument(STORY_TEXT_SELECTOR, chapterPath, chapterPath .. "/")
    end

    local bodyText = document:text() or ""
    if bodyText:find("Story Not Found", 1, true) then
        error("Story not found: " .. tostring(chapterPath))
    end
    local chap = document:selectFirst(STORY_TEXT_SELECTOR)
    if chap == nil then
        error("Could not find story text for " .. tostring(chapterPath))
    end
    chap:select(".landmark"):remove()
    return pageOfElem(chap, true)
end

-- FanFiction separates metadata with " - "
local function splitMeta(query)
    local res = {}
    if query == nil then
        return res
    end
    query = query:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    for raw in (query .. " - "):gmatch("(.-) %- ") do
        local part = raw:match("^%s*(.-)%s*$")
        if part ~= nil and part ~= "" then
            table.insert(res, part)
        end
    end
    return res
end

local function getGenres(genreString)
    if genreString == nil or genreString == "" then
        return nil
    end
    local genres = {}
    for genre in (genreString .. "/"):gmatch("(.-)/") do
        if genreByNameToValue[genre] == nil then
            return nil
        end
    end
    return genres
end

local function extractImage(element)
    if element == nil then
        return nil
    end
    local img = element
    if element.selectFirst ~= nil then
        local nested = element:selectFirst("img.cimage") or element:selectFirst("img[data-original]") or element:selectFirst("img")
        if nested ~= nil then
            img = nested
        end
    end

    local attrs = {"data-original", "data-src", "data-lazy-src", "src"}
    for _, name in ipairs(attrs) do
        local src = img:attr(name)
        if src ~= nil and src ~= "" then
            src = tostring(src):lower()
            local isPlaceholder = src:find("d_60_90", 1, true) or src:find("/static/images/", 1, true) or src:find("data:image", 1, true)
            if not isPlaceholder then
                return expandURL(src)
            end
        end
    end
    return nil
end

--- Prefer #profile_top / #img_large story art, fall back to looking for /image/
local function extractStoryImage(document, profile)
    if profile ~= nil then
        local url = extractImage(profile)
            or extractImage(profile:selectFirst("img.cimage"))
            or extractImage(profile:selectFirst("img"))
        if url then
            return url
        end
    end
    if document ~= nil then
        local url = extractImage(document:selectFirst("#img_large img.cimage"))
            or extractImage(document:selectFirst("#img_large img"))
            or extractImage(document:selectFirst("img.cimage"))
            or extractImage(document:selectFirst("#profile_top img"))
        if url then
            return url
        end
        local html = document:html()
        if html then
            local path = html:match('data%-original%s*=%s*[\'"](/image/[^\'"]+)[\'"]')
                or html:match('src%s*=%s*[\'"](/image/[^\'"]+)[\'"]')
            if path then
                return expandURL(path)
            end
        end
    end
    return nil
end

---@param storyInfoDocument Element
---@param outputInfo NovelInfo
local function parseNovelInfoFromMeta(storyInfoDocument, outputInfo)
    local storyInfo = storyInfoDocument:text()
    storyInfo = storyInfo:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    local tags, characters
    local genres = {}

    for k, v in ipairs(splitMeta(storyInfo)) do
        local function startsWith(start)
            return v:sub(1, #start) == start
        end
        local function parseCount(value)
            if value == nil then
                return 0
            end
            if type(value) == "number" then
                return value
            end
            value = tostring(value):gsub(",", ""):gsub("%s+", "")
            return tonumber(value) or 0
        end
        if startsWith("Chapters:") then
            outputInfo:setChapterCount(parseCount(v:gsub("Chapters:%s*", "")))
        elseif startsWith("Words:") then
            outputInfo:setWordCount(parseCount(v:gsub("Words:%s*", "")))
        elseif startsWith("Reviews:") then
            outputInfo:setCommentCount(parseCount(v:gsub("Reviews:%s*", "")))
        elseif startsWith("Favs:") then
            outputInfo:setFavoriteCount(parseCount(v:gsub("Favs:%s*", "")))
        elseif startsWith("Rated:") then
            table.insert(genres, "Rating: " .. v:gsub("Rated:%s*", ""):gsub("^Fiction%s+", ""))
        elseif startsWith("Follows:") or startsWith("Updated:") or startsWith("Published:") or startsWith("id:") then
            -- others are positional
        elseif k == 2 then
            outputInfo:setLanguage(v)
        elseif not tags then
            tags = getGenres(v)
            if tags == nil then
                characters = v
            end
        else
            characters = v
        end
    end

    if storyInfo:match("Status: Complete") or storyInfo:match(" %- Complete") then
        outputInfo:setStatus(NovelStatus.COMPLETED)
    else
        outputInfo:setStatus(NovelStatus.PUBLISHING)
    end

    if tags ~= nil then
        for _, v in ipairs(tags) do
            table.insert(genres, "Genre: " .. v)
        end
    end
    if characters ~= nil then
        for rel_group in characters:gmatch("%[([^%]]+)%]") do
            local relationship = {}
            for rawChar in rel_group:gmatch("([^,]+)") do
                local char = rawChar:match("^%s*(.-)%s*$")
                if char ~= nil and char ~= "" then
                    table.insert(genres, "Character: " .. char)
                    table.insert(relationship, char)
                end
            end
            table.insert(genres, "Relationship: [" .. table.concat(relationship, ", ") .. "]")
        end

        local charText = characters:gsub("%[[^%]]+%]", "")
        for rawChar in charText:gmatch("([^,]+)") do
            local char = rawChar:match("^%s*(.-)%s*$")
            if char ~= nil and char ~= "" then
                table.insert(genres, "Character: " .. char)
            end
        end
    end
    outputInfo:setGenres(genres)
end

local function buildChapters(document, storyId, novelTitle)
    local chapterSelector = document:selectFirst("#chap_select")
        or document:selectFirst("select#chap_select")
        or document:selectFirst("select[name=chapter]")
    if chapterSelector ~= nil then
        return map(
            chapterSelector:select("option"),
            function(v, i)
                local idx = v:attr("value")
                if idx == nil or idx == "" then
                    idx = tostring(i + 1)
                end
                return NovelChapter {
                    order = tonumber(idx) or (i + 1),
                    title = v:text(),
                    link = "/s/" .. storyId .. "/" .. idx
                }
            end
        )
    end

    local function singleChapter(storyId)
        return {
            NovelChapter {
                order = 1,
                title = "Chapter 1",
                link = "/s/" .. storyId, -- May not have per-chapter pages
            }
        }
    end

    local function multiChapters(storyId, count)
        local chapters = {}
        for i = 1, count do
            table.insert(chapters, NovelChapter {
                order = i,
                title = "Chapter " .. tostring(i),
                link = "/s/" .. storyId .. "/" .. i
            })
        end
        return chapters
    end

    -- Mobile pages expose chapter count as `var chs = N`
    local html = document:html()
    local chs = tonumber(html:match("var%s+chs%s*=%s*(%d+)"))
    if chs ~= nil and chs > 0 and storyId ~= nil then
        return multiChapters(storyId, chs)
    end

    -- Single-chapter stories often have no dropdown, text is in root page
    if storyId ~= nil and document:selectFirst(STORY_TEXT_SELECTOR) ~= nil then
        return singleChapter(storyId)
    end

    local chapterMatch = html:match("Chapters:%s*([%d,]+)")
    chs = chapterMatch and tonumber(chapterMatch:gsub(",", ""))
    if chs ~= nil and chs > 0 and storyId ~= nil then
        return multiChapters(storyId, chs)
    end

    -- "Chapters:" omitted on profile usually means a one-shot
    if chs == nil and html:match("Words:%s*[%d,]+") and storyId ~= nil then
        return singleChapter(storyId)
    end

    return {}
end

---@param novelURL string
---@param loadChapters boolean
---@return NovelInfo
local function parseNovel(novelURL, loadChapters)
    if novelURL:match("^how") then
        return NovelInfo {
            title = "How to use this source",
            description = "You can use this source by:\n1. Searching by keywords.\n2. Pasting a fanfiction.net story URL into search.\n3. Pasting a browse/category URL (for example /movie/Avengers/) into search and using filters.\n4. Opening the Default listing for recently updated stories.\n\nYou may need to open a novel in the webview before you can properly get its chapters"
        }
    end

    local storyId = storyIdFromURL(novelURL)
    local normalized = normalizeNovelURL(novelURL)
    local info = NovelInfo {
        title = "Unknown Title",
        link = normalized,
        description = ""
    }

    local document = fetchDocument("#profile_top", normalized .. "/", normalized)

    local profile = document:selectFirst("#profile_top")
    if profile ~= nil then -- may be null with mobile UA
        local titleEl = profile:selectFirst("b.xcontrast_txt") or profile:selectFirst("b")
        if titleEl ~= nil then
            info:setTitle(titleEl:text())
        end

		local storyImage = extractStoryImage(document, profile)
		if storyImage ~= nil then
        	info:setImageURL(storyImage)
		end

        local authorEl = profile:selectFirst("a[href*='/u/']")
        if authorEl ~= nil then
            info:setAuthors({authorEl:text()})
        end

        local descEl = profile:selectFirst("div.xcontrast_txt")
        info:setDescription(descEl and descEl:text() or "")

        local meta = profile:selectFirst("span.xgray, .xgray, span.xgray.xcontrast_txt")
            or document:selectFirst("span.xgray, .xgray")
        if meta ~= nil then
            parseNovelInfoFromMeta(meta, info)
        end
    end

    -- Fallback if desktop parsing failed
    if info:getTitle() == "Unknown Title" then
        local pageTitle = document:selectFirst("title")
        if pageTitle ~= nil then
            local t = pageTitle:text():gsub("^Fanfic:%s*", ""):gsub("%s*Ch%s*%d+.*$", "")
            if t ~= nil and t ~= "" then
                info:setTitle(setTitle)
            end
        end
    end

    if loadChapters then
        info:setChapters(AsList(buildChapters(document, storyId, info:getTitle())))
    end

    return info
end

local function parseListingDocument(document)
    local results = {}
    local seen = {}

    local function addFromRow(row)
        local titleElement = row:selectFirst("a.stitle") or row:selectFirst(".stitle") or row:selectFirst("a[href*='/s/']")
        local title = titleElement and titleElement:text()
        if title == nil or title == "" then
            return
        end
        local link = normalizeNovelURL(titleElement:attr("href"))
        -- Prefer entries that already have published chapter text
        if seen[link] then
            return
        end
        seen[link] = true
        local rowText = row:text() or ""
        local chaptersMeta = rowText:match("Chapters:%s*([%d,]+)")
        if chaptersMeta ~= nil then
            local n = tonumber((chaptersMeta:gsub(",", ""))) or 0
            if n < 1 then
                return
            end
        end

        local info =
            NovelInfo {
            title = title,
            link = link,
            imageURL = extractImage(titleElement)
                or extractImage(row:selectFirst("img.cimage, img"))
                or extractImage(row)
        }
        local meta = row:selectFirst("div.xgray, span.xgray, .xgray")
        if meta ~= nil then
            parseNovelInfoFromMeta(meta, info)
        end
        table.insert(results, info)
    end

    local rows = document:select("div.z-list, .z-list")
    if rows ~= nil and rows:size() > 0 then
        for i = 0, rows:size() - 1 do
            addFromRow(rows:get(i))
        end
    end

    if #results == 0 then
        -- mobile layout?
        local titles = document:select("#content_wrapper_inner a.stitle, a.stitle")
        if titles ~= nil then
            for i = 0, titles:size() - 1 do
                local a = titles:get(i)
                local parent = a:parent()
                if parent ~= nil and parent:parent() ~= nil then
                    -- prefer the z-list-like container when present
                    local row = a:parent()
                    local guard = 0
                    while row ~= nil and guard < 5 do
                        local cls = row:attr("class") or ""
                        if cls:find("z%-list", 1, false) then
                            break
                        end
                        row = row:parent()
                        guard = guard + 1
                    end
                    if row == nil then
                        row = parent
                    end
                    addFromRow(row)
                else
                    addFromRow(a)
                end
            end
        end
    end

    return results
end

---@param filters table
---@return table<string, string> key-value map for url.querystring
local function filterQueryMap(filters)
    local result = {
        srt = dropdownValue(SortOptions, filters[SORT_ID], 1),
        r = dropdownValue(RatingOptions, filters[RATING_ID], 1)
    }
    local function set(key, val)
        if val ~= "0" then
            result[key] = val
        end
    end
    set("t", dropdownValue(TimeRangeOptions, filters[TIME_RANGE_ID], 1))
    set("g1", dropdownValue(GenreOptions, filters[GENRE_A_ID], 1))
    set("g2", dropdownValue(GenreOptions, filters[GENRE_B_ID], 1))
    set("lan", dropdownValue(LanguageOptions, filters[LANGUAGE_ID], 1))
    set("len", dropdownValue(LengthOptions, filters[LENGTH_ID], 1))
    set("s", dropdownValue(StatusOptions, filters[STATUS_ID], 1))
    set("_g1", dropdownValue(GenreOptions, filters[GENRE_EXCLUDE_ID], 1))
    return result
end

local function isBrowsePath(path)
    if path == nil or path == "" then
        return false
    end
    if path:match("^/s/%d+") then
        return false
    end
    if path:match("^/search/?") then
        return false
    end
    -- category / fandom / just-in style paths, e.g. /movie/Avengers/ or /j/0/0/0/
    return path:match("^/[^/]+/.+") ~= nil
end

---@param filters table @of applied filter values [QUERY] is the search query, may be empty
---@return NovelInfo[]
local function search(filters)
    local page = tonumber(filters[PAGE]) or 1
    local query = filters[QUERY] or ""
    query = query:gsub("^%s*(.-)%s*$", "%1")

    if query == "" then
        return {}
    end

    -- Direct story URL (www / m / relative)
    local storyId = storyIdFromURL(query)
    if storyId ~= nil then
        if page ~= 1 then
            return {}
        end
        return {parseNovel(normalizeNovelURL(query), false)}
    end

    local path = shrinkURL(query)
    -- Full or relative browse/category URL
    if query:find("fanfiction%.net") or isBrowsePath(path) then
        local browseURL = expandURL(path):gsub("[?&]p=%d+", ""):gsub("?$", "")
        local queryMap = filterQueryMap(filters)
        queryMap.p = tostring(page)
        local document = GETDocument(url.querystring(queryMap, browseURL))
        return parseListingDocument(document)
    end

    -- Keyword search
    local searchParams = {
        keywords = query,
        ready = "1",
        type = "story",
        match = "any",
        ppage = tostring(page)
    }
    local function searchFilter(key, id, opts, default, exclude)
        local val = dropdownValue(opts, filters[id], default)
        if val ~= nil and val ~= "0" and val ~= exclude then
            searchParams[key] = val
        end
    end
    searchFilter("languageid", LANGUAGE_ID, LanguageOptions, 1)
    searchFilter("statusid", STATUS_ID, StatusOptions, 1)
    searchFilter("genreid", GENRE_A_ID, GenreOptions, 1)
    searchFilter("genreid2", GENRE_B_ID, GenreOptions, 1)
    searchFilter("censorid", RATING_ID, RatingOptions, 1, "10")

    local document = GETDocument(url.querystring(searchParams, expandURL("/search/")))
    return parseListingDocument(document)
end

local function getDefaultListing(sort)
    -- /j/{category}/{sort}/{language}/
    return function()
        local document = GETDocument(expandURL("/j/0/" .. sort .. "/0/"))
        return parseListingDocument(document)
    end
end

return {
    id = 1308639979,
    name = "FanFiction.net",
    baseURL = baseURL,
    imageURL = "https://www.fanfiction.net/static/icons3/ff-icon-192.png",
    hasCloudFlare = true,
    hasSearch = true,
    isSearchIncrementing = true,
    chapterType = ChapterType.HTML,
    listings = {
        -- Just In has no pages
        Listing("Just In: All Types", false, getDefaultListing(0)),
        Listing("Just In: New Stories", false, getDefaultListing(1)),
        Listing("Just In: Updated Stories", false, getDefaultListing(2)),
        Listing("Just In: New Crossovers", false, getDefaultListing(3)),
        Listing("Just In: Updated Crossovers", false, getDefaultListing(4)),
        Listing("How to use", false, function()
            return {
                Novel {
                    title = "How to use this source",
                    link = "how"
                }
            }
        end),
    },
    getPassage = getPassage,
    parseNovel = parseNovel,
    search = search,
    searchFilters = {
        DropdownFilter(SORT_ID, "Sort", optionNames(SortOptions)),
        DropdownFilter(TIME_RANGE_ID, "Time Range", optionNames(TimeRangeOptions)),
        DropdownFilter(GENRE_A_ID, "Genre (A)", optionNames(GenreOptions)),
        DropdownFilter(GENRE_B_ID, "Genre (B)", optionNames(GenreOptions)),
        DropdownFilter(RATING_ID, "Rating", optionNames(RatingOptions)),
        DropdownFilter(LANGUAGE_ID, "Language", optionNames(LanguageOptions)),
        DropdownFilter(LENGTH_ID, "Length", optionNames(LengthOptions)),
        DropdownFilter(STATUS_ID, "Status", optionNames(StatusOptions)),
        DropdownFilter(GENRE_EXCLUDE_ID, "Genre (Exclude)", optionNames(GenreOptions)),
    },
    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()