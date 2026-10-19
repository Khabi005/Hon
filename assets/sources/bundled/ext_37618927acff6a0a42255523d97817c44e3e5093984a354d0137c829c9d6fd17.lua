-- {"id":1915581930,"ver":"1.1.0","libVer":"1.0.0","author":"unTanya"}

local baseURL = "https://xiaowaz.fr"

--- Ensure absolute URL
local function ensureAbsolute(url)
    if not url or url == "" then return url end
    if url:match("^https?://") then return url end
    if url:sub(1,1) == "/" then
        return baseURL .. url
    else
        return baseURL .. "/" .. url
    end
end

--- Normalize chapter URL (remove fragments, utm, etc.)
local function normalizeURL(url)
    if not url then return nil end
    url = url:gsub("#.*$", "")
    url = url:gsub("%?utm_[^&]+", "")
    return url
end

--- Get chapter passage
local function getPassage(chapterURL)
    local absURL = ensureAbsolute(chapterURL)
    local doc = GETDocument(absURL)
    local content = doc:selectFirst("div.entry-content")
    if not content then return "Chapter not found." end
    -- remove unwanted blocks
    content:select("div.wp-post-navigation"):remove()
    content:select("div.abh_box"):remove()
    return pageOfElem(content, true)
end

--- Listing all series directly from the navbar
local function allSeries(_)
    local doc = GETDocument(baseURL)
    local results = {}
    local seen = {}

    local parent = doc:selectFirst("nav.main-navigation li.page-item-866 ul.children")
    if not parent then return {} end

    local links = parent:select("li a")

    for i = 0, links:size() - 1 do
        local a = links:get(i)
        local href = ensureAbsolute(a:attr("href"))
        local title = a:text()
        if not title or title == "" then
            title = "Unknown"
        end

        if href and href ~= "" and not seen[href] then
            seen[href] = true
            table.insert(results, Novel {
                title = title,
                link = href,
                imageURL = "@icon/Xiaowaz.png"
            })
        end
    end

    return results
end

-- Cache all series for title lookup
local seriesCache
local function getAllSeries()
    if not seriesCache then
        seriesCache = allSeries()
    end
    return seriesCache
end

--- Parse a series page (cover + synopsis + chapters)
local function parseNovel(novelURL)
    local url = ensureAbsolute(novelURL)
    local doc = GETDocument(url)

    -- title: priority to <head><title>
    local title = "Unknown series"
    local headTitle = doc:selectFirst("title")
    if headTitle then
        local raw = headTitle:text()
        if raw and raw ~= "" then
            title = raw:gsub("%s*|%s*Xiaowaz$", "")
        end
    end

    -- fallback 1: h1.entry-title
    if title == "Unknown series" then
        local titleElem = doc:selectFirst("h1.entry-title")
        if titleElem then title = titleElem:text() end
    end

    -- fallback 2: search in allSeries (nav FR)
    if title == "Unknown series" then
        for _, novel in ipairs(getAllSeries()) do
            if novel.link == url then
                title = novel.title
                break
            end
        end
    end

    -- cover
    local cover = "@icon/Xiaowaz.png"
    local entry = doc:selectFirst("div.entry-content")
    if entry then
        local firstImg = entry:selectFirst("p img, img.aligncenter, img.alignleft, img.size-full")
        if firstImg then
            local src = firstImg:attr("src")
            if src and src ~= "" then cover = src end
        end
    end

    -- synopsis
    local description = ""
    if entry then
        local ps = entry:select("p")
        local parts = {}
        for i=0, ps:size()-1 do
            local p = ps:get(i)
            local text = p:text()
            if text and text:match("%S") then
                table.insert(parts, text)
                if #parts >= 3 then break end
            end
        end
        if #parts > 0 then
            description = table.concat(parts, "\n\n")
        end
    end
    if description == "" then description = title end

    -- chapters
    local chapters = {}
    local seenChapters = {}

    if entry then
        local list = entry:select("ul.lcp_catlist li a")
        if list and list:size() > 0 then
            for i=0, list:size()-1 do
                local a = list:get(i)
                local href = ensureAbsolute(a:attr("href"))
                href = normalizeURL(href)
                if href and not seenChapters[href] then
                    seenChapters[href] = true
                    local ctitle = a:text()
                    if not ctitle or ctitle == "" then
                        ctitle = "Chapter"
                    end
                    table.insert(chapters, NovelChapter {
                        title = ctitle,
                        link = href
                    })
                end
            end
        else
            local elems = entry:select("p, li")
            for i=0, elems:size()-1 do
                local links = elems:get(i):select("a[href]")
                for j=0, links:size()-1 do
                    local a = links:get(j)
                    local href = a:attr("href") or ""
                    if href:find("/articles/") then
                        href = ensureAbsolute(href)
                        href = normalizeURL(href)
                        if href and not seenChapters[href] then
                            seenChapters[href] = true
                            local ctitle = a:text()
                            if not ctitle or ctitle == "" then
                                ctitle = "Chapter"
                            end
                            table.insert(chapters, NovelChapter {
                                title = ctitle,
                                link = href
                            })
                        end
                    end
                end
            end
        end
    end

    return NovelInfo {
        title = title,
        description = description,
        imageURL = cover,
        chapters = AsList(chapters)
    }
end

return {
    id = 1915581930,
    name = "Xiaowaz",
    baseURL = baseURL,
    imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/Xiaowaz.png",

    listings = {
        Listing("All Series", false, allSeries)
    },

    parseNovel = parseNovel,
    getPassage = getPassage,
    chapterType = ChapterType.HTML,

    shrinkURL = function(url,_)
        if not url or url == "" then return url end
        if url:sub(1,#baseURL) == baseURL then
            return url:gsub(baseURL.."/","")
        end
        return url
    end,

    expandURL = function(url,_)
        if url and url:match("^https?://") then return url end
        if url and url:sub(1,1) == "/" then return baseURL..url end
        return baseURL.."/"..(url or "")
    end,

    hasSearch = false,
}