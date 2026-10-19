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
-- {"id":213871,"ver":"0.1.0","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://hecatescorner.wordpress.com"

local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-hecatescorner%.wordpress%.com", "")
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
    if WPCommon.contains(classData, "wordads") then
        v:remove()
        return
    end
    local adsByGoogle = v:selectFirst("ins.adsbygoogle")
    if adsByGoogle then
        adsByGoogle:remove()
    end
end


--- @param v Element
local function reappendStyle(v)
    local style = v:attr("style")
    if WPCommon.contains(style, "text-align") then
        -- extract the alignment, some obvious format:
        -- text-align: center;
        -- text-align: center
        -- text-align:center;
        -- text-align:center
        -- there might also be other style, just ignore it
        local alignment = style:match("text%-align%:%s*%w*%s*;?")
        -- get the alignment
        if alignment then
            return alignment
        end
    end
    return nil
end

--- @param paragraph Element
local function cleanupChildStyle(paragraph)
    map(paragraph:select("span"), function (v)
        local reappend = reappendStyle(v)
        v:removeAttr("style")
        if reappend then
            v:attr("style", reappend)
        end
    end)
    local reappend = reappendStyle(paragraph)
    paragraph:removeAttr("style")
    if reappend then
        paragraph:attr("style", reappend)
    end
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    local postBody = doc:selectFirst("article")
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
local function getListings()
    --- @type Novel[]
    local _novels = {}
    _novels[#_novels + 1] = Novel {
        title = "A Maiden's Unwanted Heroic Epic",
        link = shrinkURL("https://hecatescorner.wordpress.com/a-maidens-unwanted-heroic-epic/"),
    }
    _novels[#_novels + 1] = Novel {
        title = "Lightning Empress Maid",
        link = shrinkURL("https://hecatescorner.wordpress.com/lightning-empress-maid/"),
    }
    return _novels
end

--- @param doc Document
--- @param loadChapters boolean
local function parseNovelInfo(doc, loadChapters)
    local sectionMain = doc:selectFirst("article")
    local pageTitle = sectionMain:selectFirst(".entry-title")
    local contents = sectionMain:selectFirst(".entry-content")
    WPCommon.cleanupElement(contents)

    local info = NovelInfo {
        title = pageTitle:text()
    }
    local img = contents:selectFirst("img")
    if img then
        info:setImageURL(img:attr("src"))
    end

    if loadChapters then
        local chapters = {}
        map(contents:select("p a"), function (v)
            if not WPCommon.contains(v:attr("href"), "hecatescorner.wordpress.com") then
                return
            end
            local _temp = NovelChapter {
                order = #chapters + 1,
                title = v:text(),
                link = shrinkURL(v:attr("href")),
            }
            chapters[#chapters + 1] = _temp
        end)
        info:setChapters(AsList(chapters))
    end
    return info
end

return {
    id = 213871,
    name = "Hecate's Corner",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/HecateCorner.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, function ()
            return getListings()
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