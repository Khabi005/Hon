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
-- {"id":221702,"ver":"0.3.3","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://reigokaitranslations.com"
local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    local base1Sub = url:gsub("^.-www%.reigokaitranslations%.com", ""):gsub("^.-reigokaitranslations%.com", "")
    return base1Sub:gsub("^.-www%.isekailunatic%.com", ""):gsub("^.-isekailunatic%.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    local content = doc:selectFirst("article")
    local p = content:selectFirst(".entry-content")
    WPCommon.cleanupElement(p)
    WPCommon.cleanupPassages(p:children())

    return p
end

--- @param url string
--- @return string
local function cleanImgUrl(url)
    local found = url:find("?w=")
    if found == nil then
        return url
    end
    return url:sub(0, found - 1)
end

local function getTitleFromHead(doc)
    -- get from header
    local titleHead = doc:selectFirst("title")
    if titleHead then
        local actualTitle = titleHead:text()
        -- remove `| Reigokai: Isekai TL` from title
        return actualTitle:gsub(" | Reigokai: Isekai TL", "")
    end
    return "Unknown title"
end

--- @param doc Document
--- @return string
local function findNovelTitle(doc)
    local articles = doc:selectFirst("article")
    if articles then
        local title = articles:selectFirst(".entry-title")
        if title then
            return title:text()
        else
            local bgeEntryContent = articles:selectFirst(".bge-entry-content")
            if bgeEntryContent then
                local cTitle = bgeEntryContent:selectFirst("h4") or bgeEntryContent:selectFirst("h3")
                local tParentCls = cTitle:parent():attr("class")
                local isShareButton = WPCommon.contains(cTitle:attr("class"), "sharedaddy") or WPCommon.contains(tParentCls, "sd-social")
                if isShareButton then
                    return getTitleFromHead(doc)
                end
                return cTitle:text()
            else
                local entryContent = articles:selectFirst(".entry-content")
                local cTitle = entryContent:selectFirst("h2")
                return cTitle:text()
            end
        end
    end
    return getTitleFromHead(doc)
end

--- @param doc Document
local function findListingFromDocument(doc)
    local primaryMenu = doc:selectFirst("ul#primary-menu")

    local _listings = {}
    map(primaryMenu:children(), function (v)
        local firstNovel = v:selectFirst("a")

        if firstNovel then
            local text = firstNovel:text()
            if (text:find("Active Project", 0, true) or text == "Novels") then
                map(v:selectFirst("ul.sub-menu"):select("> li > a"), function (v)
                    _listings[#_listings + 1] = Novel {
                        title = v:text(),
                        link = shrinkURL(v:attr("href"))
                    }
                end)
            else 
                -- check if link contains reigokaitranslations.com
                local link = firstNovel:attr("href")
                local isReigokai = WPCommon.contains(link, "reigokaitranslations.com")
                local isDonateLink = WPCommon.contains(link, "/donate")
                if isReigokai and not isDonateLink then
                    -- likely a single novel link
                    _listings[#_listings + 1] = Novel {
                        title = firstNovel:text(),
                        link = shrinkURL(link)
                    }
                end
            end
        end
    end)

    return _listings
end

return {
    id = 221702,
    name = "Reigokai - Isekai Lunatic",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/Reigokai.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, function(data)
            local doc = GETDocument(baseURL)
            return findListingFromDocument(doc)
        end)
    },

    getPassage = function(chapterURL)
        return pageOfElem(parsePage(chapterURL))
    end,

    parseNovel = function(novelURL, loadChapters)
        local doc = GETDocument(baseURL .. novelURL)
        local articles = doc:selectFirst("article")

        local info = NovelInfo {
            title = findNovelTitle(doc),
        }

        local imageTarget = articles:selectFirst("img")
        if imageTarget then
            info:setImageURL(cleanImgUrl(imageTarget:attr("src")))
        end

        if loadChapters then
            local chapters = {}
            local chaptersList = articles:selectFirst("div");
            map(chaptersList:select("p a"), function (v)
                local chUrl = v:attr("href")
                if WPCommon.contains(chUrl, "reigokaitranslations.com") or WPCommon.contains(chUrl, "isekailunatic.com") then
                    local _temp = NovelChapter {
                        order = #chapters + 1,
                        title = v:text(),
                        link = shrinkURL(chUrl),
                    }
                    chapters[#chapters + 1] = _temp
                end
            end)
            info:setChapters(AsList(chapters))
        end

        return info
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()