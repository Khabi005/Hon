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
-- {"id":176796,"ver":"0.1.10","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://www.shmtranslations.com"
local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    -- remove www
    url = url:gsub("www%.", ""):lower()
    -- remove shmtranslations.com
    url = url:gsub("shmtranslations%.com", "")
    -- remove https://
    url = url:gsub("https?://", "")
    return url
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

--- @param s string
--- @return string?
local function trimText(s)
    return s:match( "^%s*(.-)%s*$" )
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
    if WPCommon.contains(classData, "wp-post-nav-shortcode") then
        -- the new ToC nav
        v:remove()
        return
    end
    local isTocButton = classData and classData:find("wp-block-buttons", 0, true) and true or false
    if isTocButton then
        v:remove()
        return
    end
    if WPCommon.contains(classData, "ai-viewport-") then
        v:remove()
        return
    end
    -- nuke "SHMtranslation" watermark, it's fucking annoying as an actual reader
    local text = v:text()
    if WPCommon.contains(text:upper(), "SHMTRANSLATION") then
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
    local content = doc:selectFirst("main")
    local p = content:selectFirst(".entry-content")

    WPCommon.cleanupElement(p)

    map(p:select("p"), passageCleanup)
    map(p:select("div"), passageCleanup)
    map(p:select("p"), cleanupChildStyle)

    local title = content:selectFirst(".wp-block-post-title")
    if title then
        p:child(0):before("<h2>" .. title:text() .. "</h2><hr/>")
    end

    return p
end

local function parseListings()
    local doc = GETDocument(baseURL)
    local firstBlock = doc:selectFirst("div.wp-site-blocks")
    
    local _novels = {}
    map(firstBlock:select("> .wp-block-query"), function (block)
        -- check if block has data-wp-router-region, if yes stop
        local h2Title = block:selectFirst("h2.wp-block-heading")
        if h2Title and h2Title:text() == "Latest Update" then
            return
        end

        map(block:select("ul.wp-block-post-template > li.wp-block-post"), function (post)
            local fullBlockText = post:text()
            local titleBlock = post:selectFirst("a")
            local url = shrinkURL(titleBlock:attr("href"))
            print(url)
            local title = trimText(fullBlockText) or fullBlockText
            local _novel = Novel {
                title = title,
                link = url
            }
            local imgBlock = post:selectFirst("img")
            if imgBlock then
                _novel:setImageURL(imgBlock:attr("src"))
            end
            _novels[#_novels + 1] = _novel
        end)
    end)
    return _novels
end

local extraCss = [[
.has-text-align-center {
    text-align: center;
}

.wp-block-table td,
.wp-block-table th {
    border: 1px solid;
    padding: .5em;
}
]]

return {
    id = 176796,
    name = "SHM Translations",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/SHMTranslations.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, parseListings)
    },

    getPassage = function(chapterURL)
        return pageOfElem(parsePage(chapterURL), false, extraCss)
    end,

    parseNovel = function(novelURL, loadChapters)
        local doc = GETDocument(baseURL .. novelURL)
        local baseArticles = doc:selectFirst("main > .entry-content")

        local info = NovelInfo {
            title = baseArticles:selectFirst(".wp-block-heading"):text(),
        }
        if WPCommon.contains(novelURL, "/ongoing/") then
            info:setStatus(NovelStatus.PUBLISHING)
        elseif WPCommon.contains(novelURL, "/completed/") then
            info:setStatus(NovelStatus.COMPLETED)
        elseif WPCommon.contains(novelURL, "/dropped/") then
            info:setStatus(NovelStatus.PAUSED)
        end

        local imageTarget = baseArticles:selectFirst("img")
        if imageTarget then
            info:setImageURL(imageTarget:attr("src"))
        end

        -- wp-block-media-text__content
        local description = baseArticles:selectFirst(".wp-block-media-text__content")
        if description then
            info:setDescription(description:text())
        else
            local figcaption = baseArticles:selectFirst("figcaption")
            if figcaption then
                info:setDescription(figcaption:text())
            end
        end

        if loadChapters then
            local counter = 0.0
            -- wp-block-ub-content-toggle-accordion darkmysite_style_txt_border darkmysite_processed
            local _chapters = {}
            map(baseArticles:select(".wp-block-ub-content-toggle-accordion"), function (accord)
                local accordContent = accord:selectFirst(".wp-block-ub-content-toggle-accordion-content-wrap")
                if accordContent then
                    map(accordContent:select("a"), function (v)
                        local href = v:attr("href"):lower()
                        if not WPCommon.contains(href, "shmtranslations.com") then
                            return
                        end
                        local text = v:text()
                        if not text or text == "" then
                            return
                        end
                        if WPCommon.contains(text, "Quiz ") and WPCommon.contains(novelURL, "isekai-nonbiri") then
                            return
                        end
                        counter = counter + 1.0
                        _chapters[#_chapters + 1] = NovelChapter {
                            order = counter,
                            title = text,
                            link = shrinkURL(href)
                        }
                    end)
                end
            end)
            info:setChapters(AsList(_chapters))
        end

        return info
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()