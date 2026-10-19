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
-- {"id":954055,"ver":"0.1.2","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.2"]}

local WPCommon = Require("WPCommon");
local baseURL = "https://www.isotls.com"

local function startsWith(data, start)
    return data:sub(1, #start) == start
end

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-www%.isotls%.com", ""):gsub("^.-isotls%.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    if startsWith(url, "/") then
        return baseURL .. url
    end
    return baseURL .. "/" .. url
end

--- @param doc Document
--- @return Novel[]
local function parseListing()
    local doc = GETDocument(expandURL("/novels/"))
    local novelLists = doc:selectFirst("#novel-list")
    local contentLists = novelLists:selectFirst("ul.content-list")

    local _novels = {}
    map(contentLists:select("> li.content-list-item"), function (v)
        local title = v:selectFirst("> a > p"):text()
        local link = shrinkURL(v:selectFirst("> a"):attr("href"))
        local imgSrc = v:attr("data-img-src")

        local novel = Novel {
            title = title,
            link = link,
            imageURL = imgSrc
        }
        _novels[#_novels + 1] = novel
    end)
    return _novels
end

--- @param data table
--- @param loadChapters boolean
--- @return NovelInfo
local function getAndParseNovel(novelUrl, loadChapters)
    local doc = GETDocument(expandURL(novelUrl))

    local sectionHead = doc:selectFirst("#novel-header")
    local title = sectionHead:selectFirst("h1"):text()

    local novel = NovelInfo {
        title = title,
        language = "English"
    }

    local novelCover = sectionHead:selectFirst(".novel-cover")
    novel:setImageURL(novelCover:attr("src"))

    local synopsis = sectionHead:selectFirst("#synopsis > div")
    if synopsis then
        -- get each paragraph
        local paragraphs = ""
        map(synopsis:select("> p"), function (v)
            paragraphs = paragraphs .. v:text() .. "\n\n"
        end)
        novel:setDescription(paragraphs)
    end

    if loadChapters then
        -- load chapters
        local chapterList = doc:selectFirst("#chapters > ul")
        local _loadedChapters = {}
        map(chapterList:select("> li"), function (v)
            local order = v:attr("data-order")
            local title = v:attr("data-title")

            _loadedChapters[#_loadedChapters + 1] = NovelChapter {
                order = tonumber(order),
                title = title,
                link = shrinkURL(v:selectFirst("a"):attr("href"))
            }
        end)
        novel:setChapters(AsList(_loadedChapters))
    end
    return novel
end

--- @param chapterUrl string
--- @return any
local function parsePassages(chapterUrl)
    local doc = GETDocument(expandURL(chapterUrl))

    local section = doc:selectFirst("article")

    local contents = section:selectFirst(".content")
    map(contents:select("> span"), function (v)
        local className = v:attr("class")
        if WPCommon.contains(className, "ezoic") then
            v:remove()
            return
        end
        if WPCommon.contains(className, "reportline") then
            v:remove()
            return
        end
        if WPCommon.contains(className, "universal-js") then
            v:remove()
            return
        end
        if WPCommon.contains(className, "ez-clear") then
            v:remove()
            return
        end
    end)

    local header = section:selectFirst("header")
    local title = header:selectFirst("h1"):text()

    local novelTitle = header:selectFirst("a"):text()

    contents:child(0):before("<hr />")
    contents:child(0):before("<h2 style='text-align:center'>" .. title .. "</h2><hr/>")
    contents:child(0):before("<h1 style='text-align:center'>" .. novelTitle .. "</h1><hr/>")

    return pageOfElem(contents)
end

return {
    id = 954055,
    name = "ISO Translations",
    baseURL = baseURL,

    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/ISOTranslations.png",
    hasSearch = false,
    hasCloudFlare = false,

    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, parseListing)
    },

    getPassage = parsePassages,
    parseNovel = getAndParseNovel,

    shrinkURL = shrinkURL,
    expandURL = expandURL,
}

end)()