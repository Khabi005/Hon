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
-- {"id":376796,"ver":"0.2.0","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://toastytranslations.com"
local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-toastytranslations%.com", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

--- @param v Element
local function passageCleanup(v)
    if WPCommon.cleanupElement(v) then
        return
    end
    if WPCommon.isTocRelated(v:text()) then
        v:remove()
        return
    end
    local classData = v:attr("class")
    local isTocButton = classData and classData:find("wp-block-buttons", 0, true) and true or false
    if isTocButton then
        v:remove()
        return
    end
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    local content = doc:selectFirst("#main article")
    local p = content:selectFirst(".entry-content")

    WPCommon.cleanupElement(p)

    map(p:select("p"), passageCleanup)
    map(p:select("div"), passageCleanup)

    local title = content:selectFirst(".entry-title")
    if title then
        p:child(0):before("<h2>" .. title:text() .. "</h2><hr/>")
    end

    return p
end

return {
    id = 376796,
    name = "Toasty Translations",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/ToastyTL.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, function(data)
            local doc = GETDocument(baseURL)
            -- desktop version
            return map(flatten(mapNotNil(doc:selectFirst("ul.wp-block-navigation__container"):children(), function (v)
                local linky = v:selectFirst("a")
                local linkText = linky:text()
                return (linkText:find("All Translations")) and
                    map(v:select("ul li a"), function (ev) return ev end)
            end)), function (v)
                return Novel {
                    title = v:text(),
                    link = shrinkURL(v:attr("href"))
                }
            end)
        end)
    },

    getPassage = function(chapterURL)
        return pageOfElem(parsePage(chapterURL))
    end,

    parseNovel = function(novelURL, loadChapters)
        local doc = GETDocument(baseURL .. novelURL)
        local baseArticles = doc:selectFirst("article")
        local content = baseArticles:selectFirst(".entry-content")


        local info = NovelInfo {
            title = baseArticles:selectFirst(".entry-title"):text(),
        }

        local imageTarget = content:selectFirst("img")
        if imageTarget then
            info:setImageURL(imageTarget:attr("src"))
        end

        if loadChapters then
            local counter = 0.0
            info:setChapters(AsList(mapNotNil(content:select("ul li a"), function (v)
                local chUrl = v:attr("href")
                local isShareLink = (chUrl:find("?share=", 0, true) or chUrl:find("&share=")) and true or false
                counter = counter + 1.0
                return (chUrl:find("toastytranslations.com", 0, true) and not isShareLink) and
                    NovelChapter {
                        order = counter,
                        title = v:text(),
                        link = shrinkURL(chUrl)
                    }
            end)))
        end

        return info
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()