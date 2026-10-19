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
-- {"id":18903,"ver":"0.1.0","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://ret-translations.blogspot.com"

local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-ret%-translations%.blogspot%.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    local postBody = doc:selectFirst("article")
    local content = postBody:selectFirst(".entry-content")
    WPCommon.cleanupElement(content)

    map(content:children(), function (v)
        local isRemoved = WPCommon.cleanupElement(v)
        if isRemoved then return end
        local style = v:attr("style")
        local isAlignCenter = style and style:find("text-align", 0, true) and style:find("center", 0, true) and true or false
        local isValidTocData = WPCommon.isTocRelated(v:text()) and isAlignCenter and true or false
        if isValidTocData then
            v:remove()
            return
        end
    end)

    -- add title
    local postTitle = postBody:selectFirst(".entry-title")
    if postTitle then
        local title = postTitle:text()
        content:child(0):before('<h2 style="text-align: center;">' .. title .. "</h2><hr/>")
    end

    return content
end

--- @param elem Element|nil
--- @return Element|nil
local function findImageNode(elem)
    if not elem then
        return nil
    end

    local nextSib = elem:previousElementSibling()
    if nextSib then
        local className = nextSib:attr("class")
        if WPCommon.contains(className, "separator") then
            local imgNode = nextSib:selectFirst("img")
            if imgNode then
                return imgNode
            end
        end
        local tagName = nextSib:tagName()   
        if tagName == "h2" and WPCommon.contains(className, "wp-block-heading") then
            -- we reach the next heading, stop!
            return nil
        end
        return findImageNode(nextSib)
    end
    return nil
end

--- @param doc Document
local function parseListings(doc)
    local postBody = doc:selectFirst("#post-body")

    return mapNotNil(postBody:select("a"), function (v)
        local url = v:attr("href")
        if not WPCommon.contains(url, "ret-translations.blogspot.com") then
            return nil
        end
        local _parent = v:parent():parent():parent()
        if not _parent then
            return nil
        end

        local _temp = Novel {
            title = v:text(),
            link = shrinkURL(url)
        }
        local imgNode = findImageNode(_parent)

        if imgNode then
            _temp:setImageURL(imgNode:attr("src"))
        end
        return _temp
    end)
end

--- @param elem Element|nil
--- @return Element|nil
local function findVolumeText(elem)
    if not elem then
        return nil
    end

    local prevSib = elem:previousElementSibling()
    if prevSib then
        local className = prevSib:attr("class")
        if WPCommon.contains(className, "separator") then
            return prevSib:previousElementSibling()
        end
        return findVolumeText(prevSib)
    end
    return nil
end

--- @param doc Document
--- @param loadChapters boolean
local function parseNovelInfo(doc, loadChapters)
    local postBody = doc:selectFirst("article")
    local content = postBody:selectFirst("#post-body")
    local postTitle = postBody:selectFirst(".entry-title"):text()

    local info = NovelInfo {
        title = postTitle,
    }

    local separators = content:select(".separator")
    local selectImageTarget = false
    map(separators, function (v, i)
        if i == 0 then
            return
        end
        local imgTarget = v:selectFirst("img")
        if imgTarget and not selectImageTarget then
            info:setImageURL(imgTarget:attr("src"))
        end
    end)

    if loadChapters then
        local chapters = {}
        map(content:select("p b a"), function (v)
            local url = v:attr("href")
            if not WPCommon.contains(url, "ret-translations.blogspot.com") then
                return nil
            end
            local tempText = v:text()
            local _parent = v:parent():parent()
            if not _parent then
                return nil
            end
            local volNode = findVolumeText(_parent)
            -- check if tempText is "Part"
            if WPCommon.contains(tempText, "Part") then
                -- if yes, we want to append the chapter from prev siblings
                local prevSib = _parent:previousElementSibling()
                if prevSib then
                    local prevSibText = prevSib:text()
                    if prevSibText then
                        tempText = prevSibText .. " " .. tempText
                    end
                end
            end
            if volNode then
                tempText = volNode:text() .. " " .. tempText
            end
            -- we want to get the heading text
            local _temp = NovelChapter {
                order = #chapters + 1,
                title = tempText,
                link = shrinkURL(url)
            }
            chapters[#chapters + 1] = _temp
        end)
        info:setChapters(AsList(chapters))
    end
    return info
end

return {
    id = 18903,
    name = "RET Translations",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/RETTranslations.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Ongoing", false, function ()
            return parseListings(GETDocument("https://ret-translations.blogspot.com/p/ongoing-projects.html"))
        end),
        -- Listing("Completed", false, function ()
        -- 	return parseListings(GETDocument("https://ret-translations.blogspot.com/p/completed-projects.html"))
        -- end),
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