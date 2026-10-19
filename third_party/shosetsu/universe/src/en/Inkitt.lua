-- {"id":96602,"ver":"1.0.0","libVer":"1.0.0","author":"enhance7191"}
local json = Require("dkjson")
local baseURL = "https://www.inkitt.com"

---@param v Element
local text = function(v)
    return v:text()
end

---@param url string
---@param type int
local function shrinkURL(url)
    return url:gsub(baseURL, "")
end

---@param url string
---@param type int
local function expandURL(url)
    return baseURL .. url
end

local GENRE_FILTER = 2
local GENRE_VALUES = { 
'None',
'Sci-Fi',
'Fantasy',
'Adventure',
'Mystery',
'Action',
'Horror',
'Humor',
'Erotica',
'Poetry',
'Other',
'Thriller',
'Romance',
'Children',
'Drama'
}
local GENREPARAMS = {
'',
'scifi',
'fantasy',
'adventure',
'mystery',
'action',
'horror',
'humor',
'erotica',
'poetry',
'other',
'thriller',
'romance',
'children',
'drama'
}

local SORT_BY_FILTER = 3
local SORT_BY_VALUES = {"Popular", "Recently Updated", "Unexplored" }
local SORT_BY_PARAMS = {"popular", "recently-updated", "unexplored"}

local searchFilters = {
    DropdownFilter(GENRE_FILTER, "Genre", GENRE_VALUES),
    DropdownFilter(SORT_BY_FILTER, "Sort By", SORT_BY_VALUES),
}

local function search(data)
    local doc = GETDocument(baseURL .. "/api/2/search/title?q=" .. data[QUERY] .. "&page=" .. data[PAGE])
    doc = json.decode(doc:text())
    return map(doc.stories, function(v)
        return Novel {
            title = v.title,
            link = v.id,
            imageURL = v.vertical_cover.url or v.vertical_cover.iphone or v.cover.url
        }
    end)
end

--- @param chapterURL string @url of the chapter
--- @return string @of chapter
local function getPassage(chapterURL)
    local htmlElement = GETDocument(chapterURL)
    local title = htmlElement:selectFirst(".chapter-name"):text()
    htmlElement = htmlElement:selectFirst("div#chapterText")
    htmlElement:child(0):before("<h1>" .. title .. "</h1>")
    htmlElement:select("hr"):remove()
    return pageOfElem(htmlElement, true)
end


--- @param novelURL string @URL of novel
--- @return NovelInfo
local function parseNovel(id)
    local url = baseURL .. "/api/stories/" .. id
    local document = GETDocument(url)
    document = json.decode(document:text())

    local document2 = GETDocument(baseURL .. '/stories/'.. id)

    return NovelInfo {
        title = document.title,
        description = document2:selectFirst("p.story-summary"):text(),
        imageURL = document.cover_url,
        authors = { document2:selectFirst(".author-name a"):text()},
        genres = map(document2:select(".story-genres a"), text ),
        chapters = AsList(
                map(document.chapters, function(v)
                    return NovelChapter {
                        order = v,
                        title = v.name,
                        link = baseURL .. '/stories/'.. id .. '/chapters/' .. v.chapter_number
                    }
                end)
        )
    }
end

local function parseListing(listingURL)
    local document = RequestDocument(GET(listingURL, nil, nil))
    document = json.decode(document:text())
    return map(document.stories, function(v)
        return Novel {
            title = v.title,
            link = v.id,
            imageURL = v.vertical_cover.url or v.vertical_cover.iphone or v.cover.url
        }
    end)
end

local function getListing(data)
    local page = data[PAGE]
    local genre = data[GENRE_FILTER]
    local genreValue = ""
    local sortby = data[SORT_BY_FILTER]
    local sortByValue = ""
    if genre ~= nil then
        genreValue = GENREPARAMS[genre+1]
    end
    if sortby ~= nil then
        sortByValue = SORT_BY_PARAMS[sortby+1]
    end
    local url = ""
    if genreValue == "" then
        if sortByValue == "recently-updated" then
            url = baseURL .. "/trending_stories?page=" .. page .. "&period=recent"
        else
            url = baseURL .. "/trending_stories?page=" .. page .. "&period=alltime"
        end
    else
        url = baseURL .. "/genres/".. genreValue .. "/" .. page .. "?period=alltime&sort=" .. sortByValue
    end
    return parseListing(url)
end

return {
    id = 96602,
    name = "Inkitt",
    baseURL = baseURL,
    imageURL = "https://www.inkitt.com/1024_onblack-min.png",
    hasSearch = true,
    listings = {
        Listing("Default", true, getListing)
    },
    parseNovel = parseNovel,
    getPassage = getPassage,
    chapterType = ChapterType.HTML,
    search = search,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
    searchFilters = searchFilters
}
