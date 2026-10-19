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
-- {"id":1238794,"ver":"0.2.1","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.2"]}

local WPCommon = Require("WPCommon");
local baseURL = "https://Novelplex.org"
local defaultCover = "https://Novelplex.org/aset/gambar/coverNopel/CoverDefault.webp"


local function startsWith(data, start)
    return data:sub(1, #start) == start
end

--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-novelplex%.org", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    if startsWith(url, "/") then
        return baseURL .. url
    end
    return baseURL .. "/" .. url
end

--- @param el Element
--- @return string
local function getImageUrl(el)
    local kotakGambar = el:selectFirst(".akTN__kotakGambar")
    if kotakGambar then
        -- image is injected to child div background-image style
        local child = kotakGambar:child(0)
        if child then
            local bgStyle = child:attr("style")
            local bgUrl = WPCommon.getSpecificStyleAttribute(bgStyle, "background-image")
            if bgUrl then
                -- remove url()
                bgUrl = bgUrl:gsub("url%(", ""):gsub("%)", "")
                -- strip leading/trailing quotes
                bgUrl = bgUrl:gsub("^['\"]*(.-)['\"]*$", "%1")
                if startsWith(bgUrl, "http") then
                    return bgUrl
                end
                return expandURL(bgUrl)
            end
        end
    end

    return defaultCover
end

--- @param doc Document
--- @return Novel[]
local function parseListing()
    local doc = GETDocument(baseURL)
    local areaNovel = doc:selectFirst(".arealistNovel")
    -- local section = areaNovel:selectFirst("> .areaCarouselList")
    local topChoice = areaNovel:selectFirst("#topchoice")

    local _novels = {}
    map(topChoice:select("> .nopelpel"), function (v)
        local title = v:selectFirst(".topchoice"):text()
        local link = shrinkURL(v:attr("href"))

        local novel = Novel {
            title = title,
            link = link,
        }
        novel:setImageURL(getImageUrl(v))
        _novels[#_novels + 1] = novel
    end)
    return _novels
end

--- @param data table
--- @param loadChapters boolean
--- @return NovelInfo
local function getAndParseNovel(novelUrl, loadChapters)
    local doc = GETDocument(expandURL(novelUrl))

    local sectionHead = doc:selectFirst(".novelD__Area")
    local title = sectionHead:selectFirst(".nDjudul__title"):text()

    local novel = NovelInfo {
        title = title,
        language = "English"
    }

    local bgContainer = sectionHead:selectFirst(".novelD__cover")
    local bgUrl = defaultCover
    if bgContainer then
        local imgContainer = bgContainer:selectFirst("img")
        if imgContainer then
            local imgUrl = imgContainer:attr("src")
            if startsWith(imgUrl, "http") then
                bgUrl = imgUrl
            else
                bgUrl = expandURL(imgUrl)
            end
        end
    end
    novel:setImageURL(bgUrl)

    local novelStatus = sectionHead:selectFirst(".nDjudul__other"):selectFirst("strong > span"):text()
    if novelStatus == "Completed" then
        novel:setStatus(NovelStatus.COMPLETED)
    elseif novelStatus == "Ongoing" then
        novel:setStatus(NovelStatus.PUBLISHING)
    end

    local sectionBody = doc:selectFirst(".nAP__dN_contentArea > .nAP__dN_content");

    map(sectionBody:select("> .dNC__section"), function (sect)
        local title = sect:selectFirst(".title"):text()
        if WPCommon.contains(title, "Summary") then
            -- replace <br> with \n
            local textClass = sect:selectFirst("main") or sect:selectFirst("p")
            local textData = textClass:text():gsub("<br>", "\n")
            novel:setDescription(textData)
        elseif WPCommon.contains(title, "Genre") then
            novel:setGenres(map(sect:select(".genreTagWrap > a"), function (vvv)
                return vvv:text()
            end))
        end
    end)

    local novelAuthors = {}
    local authorHead = sectionHead:selectFirst(".nDjudul__address")
    if authorHead then
        novelAuthors[#novelAuthors + 1] = authorHead:text():sub(8)
    end
    novel:setAuthors(novelAuthors)

    if loadChapters then
        -- load chapters
        local chapterList = doc:selectFirst(".nAP__TOCArea")
        local _loadedChapters = {}
        map(chapterList:select("> .TOC__ChapterArea"), function (v)
            map(v:select("> a"), function (vv)
                local order = tonumber(vv:selectFirst(".CB_Number"):text())

                local lockedTest = vv:selectFirst(".CB_Badge")
                if lockedTest then
                    if WPCommon.contains(lockedTest:text():lower(), "lock") then
                        return
                    end
                end

                local cbHead = vv:selectFirst(".CB_Header")
                local cbTitle = cbHead:selectFirst(".CB_HText")
                local cbPublished = cbHead:selectFirst(".TOC__VIChapter")

                local aLink = vv:attr("href")
                local chNov = NovelChapter {
                    title = cbTitle:text(),
                    link = shrinkURL(aLink),
                    order = order
                }
                if cbPublished then
                    chNov:setRelease(cbPublished:text())
                end
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

    local section = doc:selectFirst(".halChap--konten")

    local chapterContainer = section:selectFirst(".halChap--kontenInner")
    local cookieBanner = section:selectFirst(".requiredCookiesBarrier")
    if cookieBanner then
        error("This chapter is locked.")
    end

    map(chapterContainer:select(".chptr-ad"), function (v)
        v:remove()
    end)
    map(chapterContainer:select(".passingthrough_adreminder"), function (v)
        v:remove()
    end)

    local titleHead = doc:selectFirst(".hCJud--head")
    if titleHead then
        local title = titleHead:text()
        chapterContainer:child(0):before("<h2>" .. title .. "</h2><hr/>")
    end
    return pageOfElem(chapterContainer)
end

return {
    id = 1238794,
    name = "NovelPlex",
    baseURL = baseURL,

    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/NovelPlex.png",
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