-- {"id":95562,"ver":"1.1.1","libVer":"1.0.0","author":"Bigrand, Confident-hate"}

local baseURL = "https://readfrom.net"
local encode = Require("url").encode

local function shrinkURL(url)
    return url:gsub("^https?://readfrom%.net/", ""):gsub("^/", "")
end

local function expandURL(url)
    return baseURL .. "/" .. url
end

local GENRE_FILTER = 2
local GENRE_VALUES = {
    "All Books",
    "Romance",
    "Fiction",
    "Fantasy",
    "Young Adult",
    "Contemporary",
    "Mystery & Thrillers",
    "Science Fiction & Fantasy",
    "Paranormal",
    "Historical Fiction",
    "Mystery",
    "Science Fiction",
    "Literature & Fiction",
    "Thriller",
    "Horror",
    "Suspense",
    "Nonfiction",
    "Children's Books",
    "Historical",
    "History",
    "Crime",
    "Ebooks",
    "Children's",
    "Chick Lit",
    "Short Stories",
    "Nonfiction",
    "Humor",
    "Poetry",
    "Erotica",
    "Humor and Comedy",
    "Classics",
    "Gay and Lesbian",
    "Biography",
    "Childrens",
    "Memoir",
    "Adult Fiction",
    "Biographies & Memoirs",
    "New Adult",
    "Gay & Lesbian",
    "Womens Fiction",
    "Science",
    "Historical Romance",
    "Cultural",
    "Vampires",
    "Urban Fantasy",
    "Sports",
    "Religion & Spirituality",
    "Paranormal Romance",
    "Dystopia",
    "Politics",
    "Travel",
    "Christian Fiction",
    "Philosophy",
    "Religion",
    "Autobiography",
    "M M Romance",
    "Cozy Mystery",
    "Adventure",
    "Comics & Graphic Novels",
    "Business",
    "Polyamorous",
    "Reverse Harem",
    "War",
    "Writing",
    "Self Help",
    "Music",
    "Art",
    "Language",
    "Westerns",
    "BDSM",
    "Middle Grade",
    "Western",
    "Psychology",
    "Comics",
    "Romantic Suspense",
    "Shapeshifters",
    "Spirituality",
    "Picture Books",
    "Holiday",
    "Animals",
    "Anthologies",
    "Menage",
    "Zombies",
    "Realistic Fiction",
    "Reference",
    "LGBT",
    "Lesbian Fiction",
    "Food and Drink",
    "Mystery Thriller",
    "Outdoors & Nature",
    "Christmas",
    "Sequential Art",
    "Novels",
    "Military Fiction"
}

local GENREPARAMS = {
    "/allbooks/",
    "/romance/",
    "/fiction/",
    "/fantasy/",
    "/young-adult/",
    "/contemporary/",
    "/mystery-thrillers/",
    "/science-fiction-fantasy/",
    "/paranormal/",
    "/historical-fiction/",
    "/mystery/",
    "/science-fiction/",
    "/literature-fiction/",
    "/thriller/",
    "/horror/",
    "/suspense/",
    "/non-fiction/",
    "/children-s-books/",
    "/historical/",
    "/history/",
    "/crime/",
    "/ebooks/",
    "/children-s/",
    "/chick-lit/",
    "/short-stories/",
    "/nonfiction/",
    "/humor/",
    "/poetry/",
    "/erotica/",
    "/humor-and-comedy/",
    "/classics/",
    "/gay-and-lesbian/",
    "/biography/",
    "/childrens/",
    "/memoir/",
    "/adult-fiction/",
    "/biographies-memoirs/",
    "/new-adult/",
    "/gay-lesbian/",
    "/womens-fiction/",
    "/science/",
    "/historical-romance/",
    "/cultural/",
    "/vampires/",
    "/urban-fantasy/",
    "/sports/",
    "/religion-spirituality/",
    "/paranormal-romance/",
    "/dystopia/",
    "/politics/",
    "/travel/",
    "/christian-fiction/",
    "/philosophy/",
    "/religion/",
    "/autobiography/",
    "/m-m-romance/",
    "/cozy-mystery/",
    "/adventure/",
    "/comics-graphic-novels/",
    "/business/",
    "/polyamorous/",
    "/reverse-harem/",
    "/war/",
    "/writing/",
    "/self-help/",
    "/music/",
    "/art/",
    "/language/",
    "/westerns/",
    "/bdsm/",
    "/middle-grade/",
    "/western/",
    "/psychology/",
    "/comics/",
    "/romantic-suspense/",
    "/shapeshifters/",
    "/spirituality/",
    "/picture-books/",
    "/holiday/",
    "/animals/",
    "/anthologies/",
    "/menage/",
    "/zombies/",
    "/realistic-fiction/",
    "/reference/",
    "/lgbt/",
    "/lesbian-fiction/",
    "/food-and-drink/",
    "/mystery-thriller/",
    "/outdoors-nature/",
    "/christmas/",
    "/sequential-art/",
    "/novels/",
    "/military-fiction/"
}

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function buildDescription(document)
    local descEl = document:selectFirst("h2 + b")
    if not descEl then
        return ""
    end

    local description = "This book is " .. descEl:text()
    local agg = document:selectFirst('span[itemprop="aggregateRating"]')

    if not agg then
        return description
    end

    local value = trim(agg:selectFirst('span[itemprop="ratingValue"]'):text())
    local best  = trim(agg:selectFirst('span[itemprop="bestRating"]'):text())
    local count = trim(agg:selectFirst('span[itemprop="ratingCount"]'):text())

    return string.format(
        "%s\n\nRating: %s out of %s (Based on %s votes)",
        description, value, best, count
    )
end

local function parseNovel(novelURL, loadChapters)
    local url = expandURL(novelURL)
    local document = GETDocument(url)

    local description = buildDescription(document)
    local infoEl = document:selectFirst('div > span[itemprop="author"]')
    local author
    local genres = {}
    if infoEl then
        local infoText = infoEl:text()
        local parts = {}
        for part in infoText:gmatch("[^/]+") do
            table.insert(parts, trim(part))
        end
        for i = 2, #parts do
            table.insert(genres, parts[i])
        end
        author = parts[1]
    else
        author = document:selectFirst('li:last-of-type span[itemprop="name"]'):text()
    end

    local NovelInfo = NovelInfo {
        title = document:selectFirst(".title"):text():gsub(", page 1" ,""),
        imageURL = document:selectFirst(".box_in center .highslide"):attr("href"),
        description = description,
        status = NovelStatus.COMPLETED, -- Each entry is a completed book, not a series.
        genres = genres,
        authors = { author },
    }

    if loadChapters then
        local chaptersEl = document:selectFirst(".splitnewsnavigation2.ignore-select .pages")
        local firstChapter = chaptersEl:selectFirst("span")
        local firstChapterHTML = '<a href="' .. url .. '">' .. firstChapter:text() .. '</a>'
        chaptersEl:prepend(firstChapterHTML)

        local i = 0
        local chapters = AsList(map(chaptersEl:select("a"), function(v)
            i = i + 1
            return NovelChapter {
                order = i,
                title = string.format("‹‹ %s ››", v:selectFirst("a"):text()),
                link = shrinkURL(v:selectFirst('a'):attr("href"))
            }
        end))

        NovelInfo:setChapters(chapters)
    end

    return NovelInfo
end

local function getPassage(chapterURL)
    local url = expandURL(shrinkURL(chapterURL))
    local doc = GETDocument(url)
    local chapter = doc:selectFirst("#textToRead")

    local uselessSelector = "iframe, script, style, noscript, svg, .highslide, .splitnewsnavigation, .splitnewsnavigation2, center"
    local useless = chapter:select(uselessSelector)
    if useless then useless:remove() end

    if chapter:hasAttr("style") then
        chapter:removeAttr("style")
    end

    -- Trim leading and trailing whitespace
    local nbsp = string.char(0xC2, 0xA0)
    local function isRemovable(node)
        local name = node:nodeName()
        if name == "br" or name == "#comment" then
            return true
        elseif name == "#text" then
            local txt = node:getWholeText():gsub(nbsp, " ")
            -- If it's just whitespace, remove it.
            -- Otherwise, it has text, so break the loop.
            return txt:match("^%s*$") ~= nil
        end
        return false
    end

    -- Leading
    while chapter:childNodeSize() > 0 do
        local first = chapter:childNode(0) -- Jsoup (Java) is 0-index based 
        if isRemovable(first) then
            first:remove()
        else
            break
        end
    end

    -- Trailing
    while chapter:childNodeSize() > 0 do
        local lastIndex = chapter:childNodeSize() - 1
        local last      = chapter:childNode(lastIndex)
        if isRemovable(last) then
            last:remove()
        else
            break
        end
    end

    -- Taken from novelvault
    -- Should be in a lib... eventually.
    local textNodes = {}
    local function collectTextNodes(node)
        for i = 0, node:childNodeSize() - 1 do
            local child = node:childNode(i)
            if child:nodeName() == "#text" and not child:isBlank() then
                table.insert(textNodes, trim(child:text()))
            else
                collectTextNodes(child)
            end
        end
    end
    collectTextNodes(chapter)

    chapter:empty()
    for _, paraText in ipairs(textNodes) do
        local para = chapter:appendElement("p")
        para:appendText(paraText)
    end

    return pageOfElem(chapter, true)
end

local function parseListing(listingURL)
    local url = listingURL -- Already expanded
    local document = GETDocument(url)

    return map(document:select("#dle-content article.box.story.shortstory"), function(v)
        return Novel {
            title = v:selectFirst(".title a b"):text(),
            link = shrinkURL(v:selectFirst(".title a"):attr("href")),
            imageURL = v:selectFirst(".text img"):attr("src")
        }
    end)
end

local function search(data)
    local page = data[PAGE]
    if page > 1 then
        return {}
    end

    local queryContent = encode(data[QUERY])
    local doc = GETDocument(baseURL .. "/build_in_search/?q=" .. queryContent)
    return map(doc:select(".box_in article"), function(v)
        return Novel {
            title = v:selectFirst("h2 b"):text(),
            imageURL = v:selectFirst("a"):attr("href"),
            link = shrinkURL(v:selectFirst("h2 a"):attr("href"))
        }
    end)
end

local function getListing(data)
    local genre = data[GENRE_FILTER]
    local page = data[PAGE]
    local genreValue = ""
    if genre ~= nil then
        genreValue = GENREPARAMS[genre+1]
    end
    local url = ""
    if page~=1 then
        url = baseURL .. genreValue .. "page/" .. page .. "/"
    else
        url = baseURL .. genreValue
    end
    return parseListing(url)
end

return {
    id = 95562,
    name = "Read From Net",
    baseURL = baseURL,
    imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/ReadFromNet.png",
    hasSearch = true,
    listings = {
        Listing("Default", true, getListing)
    },
    parseNovel = parseNovel,
    getPassage = getPassage,
    chapterType = ChapterType.HTML,
    isSearchIncrementing = false,
    search = search,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
    searchFilters = {
        DropdownFilter(GENRE_FILTER, "Genre", GENRE_VALUES)
    }
}
