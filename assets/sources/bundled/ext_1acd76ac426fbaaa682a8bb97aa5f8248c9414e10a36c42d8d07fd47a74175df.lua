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
-- {"id":24271,"ver":"0.1.1","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://yuriko-aya.cc"

local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-yuriko%-aya%.cc", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end


--- @param v Element
local function passageCleanup(v)
    local style = v:attr("style")
    local isAlignment = WPCommon.contains(style, "text-align")
    local isCenterize = WPCommon.contains(style, "center")
    local isValidTocData = WPCommon.isTocRelated(v:text()) and isAlignment and isCenterize and true or false
    if isValidTocData then
        v:remove()
        return
    end
    local classData = v:attr("class")
    if WPCommon.contains(classData, "row") then
        local firstChild = v:child(0)
        if WPCommon.contains(firstChild:attr("class"), "percanav") then
            v:remove()
            return
        end
    end
    local tagId = v:attr("id")
    if WPCommon.contains(tagId, "like-post-wrapper") then
        v:remove()
        return
    end
    if WPCommon.contains(tagId, "jp-relatedposts") then
        v:remove()
        return
    end
    if WPCommon.contains(classData, "switches") then
        v:remove()
        return
    end
    if WPCommon.contains(classData, "sharedaddy") then 
        v:remove()
        return
    end
    local adsByGoogle = v:selectFirst("ins.adsbygoogle")
    if adsByGoogle then
        adsByGoogle:remove()
    end
end

--- @param paragraph Element
local function cleanupChildStyle(paragraph)
    map(paragraph:select("span"), function (v)
        v:removeAttr("style")
    end)
    paragraph:removeAttr("style")
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    local postBody = doc:selectFirst("#main > article")
    local content = postBody:selectFirst(".entry-content")

    WPCommon.cleanupElement(content)
    map(content:select(".switches"), function (v)
        v:remove()
    end)

    map(content:select("> p"), passageCleanup)
    map(content:select("> div"), passageCleanup)
    map(content:select("p"), cleanupChildStyle)

    -- add title
    local postTitle = postBody:selectFirst(".entry-title")
    if postTitle then
        local title = postTitle:text()
        content:child(0):before("<h2>" .. title .. "</h2><hr/>")
    end

    return content
end

--- @param doc Document
local function parseListings(doc)
    local navBar = doc:selectFirst("ul#menu-navbar")

    --- @type Novel[]
    local _novels = {}
    map(navBar:select("> li"), function (v)
        local aref = v:selectFirst("a")
        if not aref then
            return
        end
        local areftext = aref:text()
        if not WPCommon.contains(areftext, "Index") then
            return
        end

        -- sub menu
        local subMenu = v:selectFirst("ul.sub-menu")
        map(subMenu:select("li a"), function (vv)
            _novels[#_novels + 1] = Novel {
                title = vv:text(),
                link = shrinkURL(vv:attr("href")),
            }
        end)
    end)
    return _novels
end


--- @param doc Document
--- @param loadChapters boolean
local function parseNovelInfo(doc, loadChapters)
    local sectionMain = doc:selectFirst("#primary")
    local pageTitle = sectionMain:selectFirst(".page-title")

    -- WPCommon.cleanupElement(content)

    local info = NovelInfo {
        title = pageTitle:text(),
    }

    if loadChapters then
        local chapters = {}
        map(sectionMain:select("article"), function (v)
            local entryHeader = v:selectFirst(".entry-header")
            local entryUrl = entryHeader:selectFirst("a")
            local _temp = NovelChapter {
                order = #chapters + 1,
                title = entryUrl:text(),
                link = shrinkURL(entryUrl:attr("href")),
            }
            chapters[#chapters + 1] = _temp
        end)
        info:setChapters(AsList(chapters))
    end
    return info
end

return {
    id = 24271,
    name = "AYA Translation",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/AyaTL.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, function ()
            return parseListings(GETDocument("https://yuriko-aya.cc/"))
        end),
    },

    getPassage = function(chapterURL)
        return pageOfElem(parsePage(chapterURL))
    end,

    parseNovel = function(novelURL, loadChapters)
        local doc = GETDocument(baseURL .. novelURL)
        return parseNovelInfo(doc, loadChapters)
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()