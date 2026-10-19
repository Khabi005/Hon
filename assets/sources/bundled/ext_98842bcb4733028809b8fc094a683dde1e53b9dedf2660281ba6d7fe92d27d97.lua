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
return (function()
-- {"id":19321,"ver":"0.1.2","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.1"]}

local baseURL = "https://soafp.com"
local settings = {}

local WPCommon = Require("WPCommon")

-- To update, paste the following code in Firefox's console while on the search page:
--
-- term_items = temp0.querySelectorAll(".term_item")
-- parsed_items = []
-- for (let i = 0; i < term_items.length; i++) {
--     term = term_items[i];
--     labelInfo = term.querySelector("label")
--     inputInfo = labelInfo.querySelector("input")
--     parsed_items.push(`${labelInfo.textContent}: ${inputInfo.value}`)
-- }
-- '"' + parsed_items.join(`\",\n\"`) + '"'
--
-- The temp0 can be fetched by right-clicking d-flex part of the Genre wrapper
-- and Selecting "Show in Console"
-- This is just a quick and dirty way to quickly update the genres.
local SWITCH_GENRES = {
    "comedy: Comedy",
    "drama: Drama",
    "fantasy: Fantasy",
    "harem: Harem",
    "isekai: Isekai",
    "oneshot: Oneshot",
    "psychological: Psychological",
    "romance: Romance",
    "school-life: School Life",
    "seinen: Seinen",
    "shounen: Shounen",
    "slice-of-life: Slice of Life",
    "soafp: Soafp",
}
local SWITCH_TAGS = {
    "abusive-characters: Abusive Characters",
    "betrayal: Betrayal",
    "broken-mc: Broken MC",
    "bullying: Bullying",
    "depictions-of-cruelty: Depictions of Cruelty",
    "devoted-love-interests: Devoted Love Interests",
    "drama: Drama",
    "false-accusation: False Accusation",
    "female-protagonist: Female Protagonist",
    "important-past: Important Past",
    "incest: Incest",
    "male-protagonist: Male Protagonist",
    "master-servant-relationship: Master-Servant Relationship",
    "misunderstandings: Misunderstandings",
    "mob-protagonist: Mob Protagonist",
    "multiple-pov: Multiple POV",
    "netorare: Netorare",
    "revenge: Revenge",
    "romance: Romance",
    "school-life: School Life",
    "slaves: Slaves",
    "tragedy: Tragedy",
    "trauma: Trauma",
    "tsundere: Tsundere",
    "wholesome: Wholesome",
    "yandere: Yandere",
    "zama: Zama",
}

--- @param arrays table
local function coerceTristate(arrays, startIndex)
    -- the table is either SWITCH_GENRES or SWITCH_TAGS
    -- the table is a list of strings, each string is a "key: value" pair
    -- we also want index
    local index = startIndex or 1
    local coerced = {}
    print(arrays)
    map(arrays, function (v)
        local key, value = v:match("^(.-):%s*(.-)$")
        coerced[#coerced + 1] = TriStateFilter(index, value)
        index = index + 1
    end)
    return coerced
end

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-soafp.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

---@param srcSetStr string
---@return string|nil
local function getImgSrcSet(srcSetStr)
    -- Get the largest image.
    local max_size, max_url = 0, ""
    for url, size in srcSetStr:gmatch("(http.-) (%d+)w") do
        if tonumber(size) > max_size then
            max_size = tonumber(size)
            max_url = url
        end
    end
    if max_url ~= "" then
        return max_url
    end
    return nil
end

---@param image_element Element An img element of which the biggest image shall be selected.
---@return string A link to the biggest image of the image_element.
--- Taken from Madara.lua
local function getImgSrc(image_element)
    -- Check srcset:
    local srcset = image_element:attr("srcset")
    if srcset ~= "" then
        local srcSetBig = getImgSrcSet(srcset)
        if srcSetBig then
            return srcSetBig
        end
    end

    -- Check data-lazy-srcset: (unloaded lazyload)
    local dataLazySet = image_element:attr("data-lazy-srcset")
    if dataLazySet ~= "" then
        local srcSetBig = getImgSrcSet(dataLazySet)
        if srcSetBig then
            return srcSetBig
        end
    end

    -- Default to src (the most likely place to be loaded via script):
    return image_element:attr("src")
end

--- @param doc Document
--- @return Novel[]
local function parseListing(doc)
    local section = doc:selectFirst(".search-results")

    local _novels = {}
    map(section:select("> .search-result"), function (v)
        local titleElem = v:selectFirst(".search-link")

        local novel = Novel {
            title = titleElem:text(),
            link = shrinkURL(titleElem:attr("href")),
        }
        _novels[#_novels + 1] = novel
    end)
    return _novels
end

--- @param data table
--- @return Novel[]
local function latestNovel(data)
    local doc = GETDocument(baseURL .. "/search/")
    return parseListing(doc)
end

--- @param arrays table
--- @param startIndex int
--- @param data table
local function buildCoercedResults(arrays, startIndex, data)
    local index = startIndex or 1
    local allowed = {}
    local blocked = {}
    map(arrays, function (v)
        local key, value = v:match("^(.-):%s*(.-)$")
        if data[index] == 1 then
            allowed[#allowed + 1] = key
        elseif data[index] == 2 then
            blocked[#blocked + 1] = key
        end
        index = index + 1
    end)
    return allowed, blocked
end

--- @param data table
--- @return Novel[]
local function doSearch(data)
    local urlReq = baseURL .. "/search/?title="
    local searchString = data[QUERY]
    urlReq = urlReq .. searchString
    local selGenre, blockGenre = buildCoercedResults(SWITCH_GENRES, 101, data)
    for _, v in ipairs(selGenre) do
        urlReq = urlReq .. "&genre[]=" .. v
    end
    for _, v in ipairs(blockGenre) do
        urlReq = urlReq .. "&bl_genre[]=" .. v
    end
    local selTag, blockTag = buildCoercedResults(SWITCH_TAGS, 201, data)
    for _, v in ipairs(selTag) do
        urlReq = urlReq .. "&tag[]=" .. v
    end
    for _, v in ipairs(blockTag) do
        urlReq = urlReq .. "&bl_tag[]=" .. v
    end

    local doc = GETDocument(urlReq)
    return parseListing(doc)
end

--- @param data table
--- @param loadChapters boolean
--- @return NovelInfo
local function getAndParseNovel(novelUrl, loadChapters)
    local doc = GETDocument(expandURL(novelUrl))

    local section = doc:selectFirst("#primary article")
    local title = section:selectFirst(".entry-title"):text()

    local entryContent = section:selectFirst(".entry-content")

    local novel = NovelInfo {
        title = title,
    }
    local imgEl = entryContent:selectFirst(".wp-block-image img")
    if imgEl then
        novel:setImageURL(getImgSrc(imgEl))
    end

    local textDesc = ""
    map(entryContent:select("> p"), function (v)
        textDesc = textDesc .. v:text() .. "\n"
    end)
    textDesc = textDesc:gsub("\n+$", "")
    novel:setDescription(textDesc)

    local entryDetails = section:selectFirst(".entry-details")

    local novelGenres = entryDetails:selectFirst(".genres-links")
    novel:setGenres(map(novelGenres:select("> a"), function (v)
        return v:text()
    end))

    local novelTags = entryDetails:selectFirst(".tags-links")
    novel:setTags(map(novelTags:select("> a"), function (v)
        return v:text()
    end))

    if loadChapters then
        -- load chapters
        local _loadedChapters = {}
        map(entryContent:select("> .lcp_catlist"), function (v)
            map(v:select("li a"), function (vv)
                local href = vv:attr("href")
                if not WPCommon.contains(href, "soafp.com") then -- invalid chapter
                    return
                end
                local chNov = NovelChapter {
                    title = vv:text(),
                    link = shrinkURL(href),
                    order = #_loadedChapters + 1
                }
                _loadedChapters[#_loadedChapters + 1] = chNov
            end)
        end)
        novel:setChapters(AsList(_loadedChapters))
    end
    return novel
end

--- @param chapterUrl string
--- @return any
local function parsePassages(chapterUrl)
    local doc = GETDocument(expandURL(chapterUrl))

    local article = doc:selectFirst("article")
    local content = article:selectFirst(".entry-content")

    local preBar = content:selectFirst(".pre-bar")
    if preBar then preBar:remove() end

    map(content:children(), function (v)
        local deleted = WPCommon.cleanupElement(v)
        if deleted then return end

        local class = v:attr("class")
        if WPCommon.contains(class, "wp-block-buttons") then
            v:remove()
            return
        end

        local textContent = v:text():lower()
        if WPCommon.contains(textContent, "like loading...") then
            v:remove()
            return
        end
    end)

    -- add title
    local postTitle = article:selectFirst(".entry-title")
    if postTitle then
        local title = postTitle:text()
        content:child(0):before("<h2>" .. title .. "</h2><hr/>")
    end

    return pageOfElem(content)
end

return {
    id = 19321,
    name = "Soafp Translations",
    baseURL = baseURL,

    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/Soafp.png",
    hasSearch = true,
    hasCloudFlare = false,

    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, latestNovel)
    },

    searchFilters = {
        FilterGroup("Genres", coerceTristate(SWITCH_GENRES, 101)),
        FilterGroup("Tags", coerceTristate(SWITCH_TAGS, 201)),
    },

    getPassage = parsePassages,
    parseNovel = getAndParseNovel,

    shrinkURL = shrinkURL,
    expandURL = expandURL,
    search = doSearch,
    updateSetting = function(id, value)
        settings[id] = value
    end
}

end)()