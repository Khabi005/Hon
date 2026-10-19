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
-- {"id":28903,"ver":"0.2.1","libVer":"1.0.0","author":"N4O","dep":["WPCommon>=1.0.3"]}

local baseURL = "https://glucosetl.xyz"

local WPCommon = Require("WPCommon")

local function startsWith(data, start)
    return data:sub(1, #start) == start
end


--- @param url string
--- @return string
local function shrinkURL(url)
    return url:gsub("^.-glucosetl%.xyz", "")
end

--- @param url string
--- @return string
local function expandURL(url)
    return baseURL .. url
end

--- @param content Document
--- @return boolean
local function isAnubisPage(content)
    local images = content:selectFirst("img")
    ---@diagnostic disable-next-line: unnecessary-if
    -- get the src attribute of the first image
    if images and images:attr("src") then
        local src = images:attr("src")
        if WPCommon.contains(src, ".within-website") then
            return true
        end
    end

    local title = content:selectFirst("h1#title")
    if title and WPCommon.contains(title:text(), "Making sure you're not a bot") then
        return true
    end
    
    return false
end

local function parsePage(url)
    local doc = GETDocument(expandURL(url))
    if isAnubisPage(doc) then
        -- throw error
        error("Anubis bot protection detected. Please view the page in webview and wait for it to complete")
    end
    local postBody = doc:selectFirst("div.flex.gap-10 > div.items-center.bg-black")

    -- add title
    local postTitle = doc:selectFirst("div.flex.gap-10 > .text-2xl")
    if postTitle then
        local title = postTitle:text()
        postBody:child(0):before("<h2>" .. title .. "</h2><hr/>")
    end

    -- find all image source and replace sz=w1000 with sz=s0
    map(postBody:select("img"), function (img)
        local src = img:attr("src")
        if src and WPCommon.contains(src, "sz=w1000") then
            img:attr("src", src:gsub("sz=w1000", "sz=s0"))
        end
    end)

    return postBody
end

--- @param doc Document
local function parseListings(doc)
    if isAnubisPage(doc) then
        -- throw error
        error("Anubis bot protection detected. Please view the page in webview and wait for it to complete")
    end

    local _listings = {}
    map(doc:select("a.foreground.justify-center"), function (elem)
        local href = elem:attr("href")
        if startsWith(href, "/translations/") then
            print("Found translation: " .. href)
            local image = elem:selectFirst("img")

            local groupElem = elem:select("div > div")
            local title = groupElem:get(0):text()
            local status = groupElem:get(2)

            local novel = Novel {
                title = title,
                link = shrinkURL(href),
            }
            if image and image:attr("src") then
                novel:setImageURL(expandURL(image:attr("src")))
            end
            if status then
                local statusText = status:text()
                -- match the status text
                local lowercaseStatus = statusText:lower()
                if WPCommon.contains(lowercaseStatus, "completed") then
                    novel:setLink(shrinkURL(href .. "#shosetsu-status=completed"))
                elseif WPCommon.contains(lowercaseStatus, "ongoing") then
                    novel:setLink(shrinkURL(href .. "#shosetsu-status=ongoing"))
                elseif WPCommon.contains(lowercaseStatus, "dropped") then
                    novel:setLink(shrinkURL(href .. "#shosetsu-status=dropped"))
                end
            end

            _listings[#_listings + 1] = novel
        end
    end)
    return _listings
end

--- @param volumeUrl string
local function queryVolumeChapters(volumeUrl)
    print("Requesting volumes: " .. volumeUrl)
    local doc = GETDocument(expandURL(volumeUrl))

    local _links = {}
    map(doc:select(".foreground > .flex > div.flex > a.link[href]"), function (chapter)
        local path = chapter:attr("href")
        local volumeTitle = chapter:text()
        -- combine volumeUrl with path
        -- remove the first text before slash
        local slashIndex = path:find("/", 2)

        local fullPath = volumeUrl .. "/" .. path
        if slashIndex then
            fullPath = volumeUrl .. "/" .. path:sub(slashIndex + 1)
        end

        _links[#_links + 1] = {
            title = volumeTitle,
            link = shrinkURL(fullPath),
        }
    end)

    print("Found " .. #_links .. " chapters in volume: " .. volumeUrl)
    return _links
end

--- @param doc Document
--- @param loadChapters boolean
--- @param novelUrl string
local function parseNovelInfo(doc, loadChapters, novelUrl)
    local topArea = doc:selectFirst(".container > .foreground.rounded-lg")
    local title = topArea:selectFirst("div.text-4xl")

    local info = NovelInfo {
        title = title:text(),
        status = NovelStatus.PUBLISHING,
    }

    local imageTarget = topArea:selectFirst("img")
    if imageTarget then
        info:setImageURL(expandURL(imageTarget:attr("src")))
    end

    if WPCommon.contains(novelUrl, "#shosetsu-status=completed") then
        info:setStatus(NovelStatus.COMPLETED)
    elseif WPCommon.contains(novelUrl, "#shosetsu-status=dropped") then
        info:setStatus(NovelStatus.PAUSED)
    end

    if loadChapters then
        local _chapters_temp = {}
        map(doc:select("a.foreground.flex"), function (v)
            local url = v:attr("href")
            local volumeTitle = v:text()
            if not startsWith(url, "/") then
                url = '/translations/' .. url
            end

            local allLinks = queryVolumeChapters(url)
            -- if no links were found, skip
            if #allLinks == 0 then
                return
            end

            -- reverse the order of links
            local reversedLinks = {}
            for i = #allLinks, 1, -1 do
                reversedLinks[#reversedLinks + 1] = allLinks[i]
            end

            for _, link in ipairs(reversedLinks) do
                local _temp = {
                    title = volumeTitle .. ': ' .. link.title,
                    link = link.link,
                }
                _chapters_temp[#_chapters_temp + 1] = _temp
            end
            -- local _temp = NovelChapter {
            --     order = #chapters + 1,
            --     title = tempText,
            --     link = shrinkURL(url)
            -- }
            -- chapters[#chapters + 1] = _temp
        end)

        -- reverse the order of chapters
        local chapters = {}
        for i = #_chapters_temp, 1, -1 do
            local temp = _chapters_temp[i]
            local _temp = NovelChapter {
                order = #chapters + 1,
                title = temp.title,
                link = temp.link,
            }
            chapters[#chapters + 1] = _temp
        end
        info:setChapters(AsList(chapters))
    end
    return info
end

return {
    id = 28903,
    name = "Glucose Translations",
    baseURL = baseURL,
    imageURL = "https://github.com/noaione/shosetsu-extensions/raw/dev/icons/GlucoseTL.png",
    hasSearch = false,
    chapterType = ChapterType.HTML,

    -- Must have at least one value
    listings = {
        Listing("Novels", false, function ()
            return parseListings(GETDocument("https://glucosetl.xyz/translations"))
        end),
    },

    getPassage = function(chapterURL)
        return pageOfElem(parsePage(chapterURL))
    end,

    parseNovel = function(novelURL, loadChapters)
        local doc = GETDocument(baseURL .. novelURL)
        if isAnubisPage(doc) then
            -- throw error
            error("Anubis bot protection detected. Please view the page in webview and wait for it to complete")
        end
        return parseNovelInfo(doc, loadChapters, novelURL)
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}

end)()