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
-- {"id":811702,"ver":"0.1.2","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.0"]}

local baseURL = "https://machineslicedbread.xyz"
local WPCommon = Require("WPCommon")

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-www%.machineslicedbread%.xyz", ""):gsub("^.-machineslicedbread%.xyz", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

--- @param chapterURL string
--- @return string
local function getPassage(chapterURL)
    local doc = GETDocument(expandURL(chapterURL))
    -- check if protected
    local prot = doc:selectFirst("form.post-password-form")
    if prot then
        error("This chapter is locked!")
    end

    -- process
    local p = doc:selectFirst(".entry-content")

    WPCommon.cleanupElement(p)
    local stopRemovingToc = false
    map(p:select("p a"), function (v)
        if stopRemovingToc then return end
        local parent = v:parent()
        if parent then
            if WPCommon.isTocRelated(parent:text()) then
                stopRemovingToc = true
                parent:remove()
            end
        end
    end)
    local textBoxA = p:selectFirst("#textbox")
    if textBoxA then textBoxA:remove() end
    local textBoxB = p:selectFirst("#textbox")
    if textBoxB then textBoxB:remove() end

    local entryTitle = doc:selectFirst(".entry-title")
    if entryTitle then
        local title = entryTitle:text()
        if title then
            p:child(0):before("<h2>" .. title .. "</h2><hr/>")
        end
    end

    return pageOfElem(p)
end

--- @param v Element
--- @return table|nil
local function iterNovelChapter(v)
    local href = v:attr("href")
    local text = v:text()
    if not WPCommon.contains(href, "machineslicedbread") then return nil end

    if WPCommon.contains(text:lower(), "direct link") then
        -- previous elem is chapter title
        local prevEl = v:previousElementSibling()
        if prevEl then
            text = prevEl:text()
        end
    end

    -- locked chapter
    if WPCommon.contains(text:lower(), "(locked)") then return nil end

    return {
        t = text,
        u = shrinkURL(href)
    }
end

--- @param novelURL string
--- @return NovelInfo
local function parseNovel(novelURL)
    local doc = GETDocument(expandURL(novelURL))

    local entryContent = doc:selectFirst("div.entry-content")

    local _novelInfo = NovelInfo {
        title = doc:selectFirst(".entry-title"):text(),
    }
    local imgEl = entryContent:selectFirst("img")
    if imgEl then
        _novelInfo:setImageURL(imgEl:attr("src"))
    end
    if WPCommon.contains(novelURL, "#shosetsu-status-complete") then
        _novelInfo:setStatus(NovelStatus.COMPLETED)
    elseif WPCommon.contains(novelURL, "#shosetsu-status-dropped") then
        _novelInfo:setStatus(NovelStatus.PAUSED)
    else
        _novelInfo:setStatus(NovelStatus.PUBLISHING)
    end

    -- load chapters
    local _Chapters = {}
    map(entryContent:select("p a"), function (v)
        local result = iterNovelChapter(v)
        if result then
            _Chapters[#_Chapters + 1] = NovelChapter {
                title = result.t,
                link = result.u,
                order = #_Chapters + 1,
            }
        end
    end)
    map(entryContent:select("li a"), function (v)
        local result = iterNovelChapter(v)
        if result then
            _Chapters[#_Chapters + 1] = NovelChapter {
                title = result.t,
                link = result.u,
                order = #_Chapters + 1,
            }
        end
    end)
    map(entryContent:select("div a"), function (v)
        local result = iterNovelChapter(v)
        if result then
            _Chapters[#_Chapters + 1] = NovelChapter {
                title = result.t,
                link = result.u,
                order = #_Chapters + 1,
            }
        end
    end)

    _novelInfo:setChapters(AsList(_Chapters))
    return _novelInfo
end

--- @param headEl Element
--- @param hitElement string
local function _getAllNovelsUntil(headEl, hitElement)
    local _novels = {}
    local htmlString = ""
    local nextEl = headEl:nextElementSibling()
    while nextEl and nextEl:tagName() ~= hitElement do
        htmlString = htmlString .. nextEl:html()
        nextEl = nextEl:nextElementSibling()
    end
    local allElement = Document(htmlString)
    map(allElement:select("li"), function (v)
        local novelURL = v:selectFirst("a"):attr("href")
        local novelTitle = v:selectFirst("a"):text()
        if WPCommon.contains(novelURL, "machineslicedbread") then
            _novels[#_novels + 1] = {
                t = novelTitle,
                u = shrinkURL(novelURL)
            }
        end
    end)
    return _novels
end

local function parseListings(isOriginal)
    local doc = GETDocument(baseURL)

    local entryContent = doc:selectFirst("div.entry-content")

    local _listings = {}
    map(entryContent:select("> h2"), function (head)
        if isOriginal then
            -- process original novel
            for _, novel in ipairs(_getAllNovelsUntil(head, "hr")) do
                _listings[#_listings + 1] = Novel {
                    title = novel.t,
                    link = novel.u,
                }
            end
        else
            local h2Text = head:text()
            if WPCommon.contains(h2Text, "Original") then return end
            for _, novel in ipairs(_getAllNovelsUntil(head, "hr")) do
                local novelUrl = novel.u
                -- magical status detection
                if WPCommon.contains(h2Text, "Complete") then
                    novelUrl = novelUrl .. "#shosetsu-status-complete"
                end
                if WPCommon.contains(h2Text, "Hiatus") then
                    novelUrl = novelUrl .. "#shosetsu-status-dropped"
                end
                _listings[#_listings + 1] = Novel {
                    title = novel.t,
                    link = novelUrl,
                }
            end
        end
    end)
    return _listings
end

return {
    id = 811702,
    name = "Machine Sliced Bread",
    baseURL = baseURL,
    chapterType = ChapterType.HTML,

    -- Optional values to change
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/MachineSlicedBread.png",
    hasCloudFlare = false,
    hasSearch = false,

    -- Must have at least one value
    listings = {
        Listing("Translated Novels", false, function()
            return parseListings(false)
        end),
        Listing("Original Novels", false, function()
            return parseListings(true)
        end)
    },

    -- Default functions that have to be set
    getPassage = getPassage,
    parseNovel = parseNovel,
    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()