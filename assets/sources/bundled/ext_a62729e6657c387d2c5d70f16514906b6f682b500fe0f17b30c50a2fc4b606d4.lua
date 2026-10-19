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
-- {"id":1331219,"ver":"1.2.2","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://bakapervert.wordpress.com"
local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-bakapervert%.wordpress%.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

--- @param doc Document
local function propagateToDocument(doc)
    local content = doc:selectFirst(".entry-content")

    local links = mapNotNil(content:select("a"), function(link)
        local href = link:attr("href")
        return href and href:match("^https?://bakapervert%.wordpress%.com") and href
    end)

    if links == nil then
        local firstLink = content:selectFirst("a")
        return GETDocument(expandURL(shrinkURL(firstLink:attr("href"))))
    end

    local fisrtLink = links[1]
    return GETDocument(expandURL(shrinkURL(fisrtLink)))
end

--- @param document Document
--- @return Element
local function selectContent(document)
    local divContent = document:selectFirst("#content div")
    if divContent ~= nil then
        return divContent
    end
    local articleContent = document:selectFirst("#content article")
    return articleContent
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    local content = selectContent(doc)
    local p = content:selectFirst(".entry-content")

    -- check if p is null
    if p == nil then
        doc = propagateToDocument(doc)
        content = selectContent(doc)
        p = content:selectFirst(".entry-content")
    end

    WPCommon.cleanupElement(p)

    local post_flair = content:selectFirst("div#jp-post-flair")
    if post_flair then post_flair:remove() end

    -- get last "p" to remove prev/next links
    local allElements = p:select("p")
    WPCommon.cleanupPassages(allElements, false)

    return p
end

--- @param document Document
--- @return NovelInfo
local function novelParserDesktop(document, loadChapters)
    local content = document:selectFirst("#content div")

    local info = NovelInfo {
        title = content:selectFirst(".entry-title"):text(),
    }

    local imageTarget = content:selectFirst("img")
    if imageTarget then
        info:setImageURL(imageTarget:attr("src"))
    end

    if loadChapters then
        info:setChapters(AsList(mapNotNil(content:selectFirst(".entry-content"):select("p a"), function (v, i)
            local chUrl = v:attr("href")
            return (chUrl:find("bakapervert.wordpress.com", 0, true)) and
                NovelChapter {
                    order = i,
                    title = v:text(),
                    link = shrinkURL(chUrl)
                }
        end)))
    end

    return info
end

--- @param document Document
--- @return NovelInfo
local function novelParserMobile(document, loadChapters)
    local content = document:selectFirst("#content article")
    local info = NovelInfo {
        title = content:selectFirst(".entry-title"):text(),
    }

    local imageTarget = content:selectFirst("img")
    if imageTarget then
        info:setImageURL(imageTarget:attr("src"))
    end

    if loadChapters then
        info:setChapters(AsList(mapNotNil(content:selectFirst(".entry-content"):select("p a"), function (v, i)
            local chUrl = v:attr("href")
            return (chUrl:find("bakapervert.wordpress.com", 0, true)) and
                NovelChapter {
                    order = i,
                    title = v:text(),
                    link = shrinkURL(chUrl)
                }
        end)))
    end

    return info
end


local function novelParserCommon(novelURL, loadChapters)
    local doc = GETDocument(baseURL .. novelURL)
    local bodyClassName = doc:selectFirst("body"):attr("class")
    if WPCommon.contains(bodyClassName, "mobile-theme") then
        return novelParserMobile(doc, loadChapters)
    else
        return novelParserDesktop(doc, loadChapters)
    end
end

--- @param elem Element
local function novelListingParseCommon(elem)
    local _listings = {}
    
    map(elem:select("#menu-menu-1 > li"), function (menu)
        local header = menu:selectFirst("> a")
        local headerText = header:text()
        if WPCommon.contains(headerText:lower(), "projects") then
            map(menu:select("> .sub-menu > li"), function (itemData)
                local link = itemData:selectFirst("> a")

                _listings[#_listings + 1] = Novel {
                    title = link:text(),
                    link = shrinkURL(link:attr("href"))
                }
            end)
        end
    end)

    return _listings
end

local function novelListingCommon()
    local doc = GETDocument(baseURL)
    local bodyClassName = doc:selectFirst("body"):attr("class")
    if WPCommon.contains(bodyClassName, "mobile-theme") then
        return novelListingParseCommon(doc:selectFirst("nav#access > .menu-menu-1-container"))
    else
        return novelListingParseCommon(doc:selectFirst("div#access > .menu-header"))
    end
end

return {
    id = 1331219,
    name = "bakapervert",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/Bakapervert.jpg",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, novelListingCommon)
    },

    getPassage = function(chapterURL)
        return pageOfElem(parsePage(chapterURL))
    end,

    parseNovel = novelParserCommon,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()