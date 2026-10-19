-- {"id":78,"ver":"1.1.0","libVer":"1.0.0","author":"JFronny"}

local settings = {}

-- concatenate two lists
---@param list1 table
---@param list2 table
local function concatLists(list1, list2)
    for i = 1, #list2 do
        table.insert(list1, list2[i])
    end
    return list1
end

local function lift(xtable)
    local t = {}
    for k, v in next, xtable do
        table.insert(t, { k, v })
    end
    return t
end

local function processArcName(name)
    return name:gsub("^[ ]*", "")
            :gsub("[ ]*$", "")
            :gsub("^Arc [0-9]* ", "")
            :gsub("– ", "")
            :gsub("^%(", "")
            :gsub("%)$", "")
            .. " - "
end

local USERAGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:90.0) Gecko/20100101 Firefox/90.0"
local HEADERS = HeadersBuilder():add("User-Agent", USERAGENT):build()

local auxiliary = {
    ["https://parahumans.wordpress.com/"] = {
        name = "Worm",
        image = "https://parahumans.wordpress.com/wp-content/uploads/2011/06/cityscape2.jpg",
        description = {5, 9},
        arcs = ".widget_categories .cat-item .cat-item:not(.cat-item .cat-item .cat-item)",
        arc = "a",
        chapters = ".cat-item .cat-item a"
    },
    ["https://pactwebserial.wordpress.com/"] = {
        name = "Pact",
        image = "https://pactwebserial.wordpress.com/wp-content/uploads/2014/01/pact-banner2.jpg",
        description = {2, 5},
        arcs = ".widget_categories .cat-item .cat-item:not(.cat-item .cat-item .cat-item)",
        arc = "a",
        chapters = ".cat-item .cat-item a"
    },
    ["https://twigserial.wordpress.com/"] = {
        name = "Twig",
        image = "https://twigserial.wordpress.com/wp-content/uploads/2016/06/cropped-twigheader5.png",
        description = {2, 9},
        extractChapters = function()
            local document = RequestDocument(GET("https://twigserial.wordpress.com/", HEADERS))
            local chaps = {}
            local options = mapNotNil(document:select("#cat option"), function(v) return v end)
            local arcPrefix = ""
            for i = 3, #options do
                if options[i]:attr("class") == "level-1" then
                    arcPrefix = processArcName(options[i]:text())
                else
                    table.insert(chaps, NovelChapter {
                        title = arcPrefix .. options[i]:text(),
                        link = "https://twigserial.wordpress.com/?cat=" .. options[i]:attr("value")
                    })
                end
            end
            return chaps
        end
    },
    ["https://www.parahumans.net/"] = {
        name = "Ward",
        image = "https://i2.wp.com/www.parahumans.net/wp-content/uploads/2017/10/cropped-Ward-Banner-Proper-1.jpg",
        description = {4, 5},
        arcs = "#secondary .widget_nav_menu:not(#nav_menu-2) .menu-item:not(.menu-item .menu-item)",
        arc = "a",
        chapters = ".menu-item .menu-item a"
    },
    ["https://palewebserial.wordpress.com/"] = {
        name = "Pale",
        image = "",
        description = {1, 7},
        arcs = "#nav_menu-2 .menu-item:not(.menu-item .menu-item)",
        arc = "a",
        chapters = ".sub-menu a"
    },
    ["https://clawwebserial.blog/"] = {
        name = "Claw",
        image = "https://clawwebserial.blog/wp-content/uploads/2024/03/claw-banner2.png",
        descriptionUrl = "https://clawwebserial.blog/about/",
        description = {1, 3},
        extractChapters = function()
            local document = RequestDocument(GET("https://clawwebserial.blog/table-of-contents/", HEADERS))
            local chaps = {}
            local paragraphs = mapNotNil(document:select(".entry-content p"), function(v) return v end)
            for i = 2, #paragraphs, 2 do
                local arcPrefix = processArcName(paragraphs[i]:text())
                chaps = concatLists(chaps, mapNotNil(paragraphs[i + 1]:select("a"), function(v)
                    return NovelChapter {
                        title = arcPrefix .. v:text(),
                        link = v:attr("href")
                    }
                end))
            end
            return chaps
        end
    }
    -- We ignore Seek since that does not seem to have a ToC.
    -- If you want to read it, feel free to set it up yourself.
    --["https://seekwebserial.wordpress.com/"] = {
    --    name = "Seek",
    --    image = "https://seekwebserial.wordpress.com/wp-content/uploads/2024/11/headerart_w.png",
    --    descriptionUrl = "https://seekwebserial.wordpress.com/about/",
    --    description = {1, 6},
    --    arcs = "#nav_menu-2 .menu-item:not(.menu-item .menu-item)",
    --    arc = "a",
    --    chapters = ".sub-menu a"
    --}
}

local function parseNovel(novelURL, loadChapters)
    local document = RequestDocument(GET(novelURL, HEADERS))
    local aux = auxiliary[novelURL]

    local aboutDocument = document
    if aux.descriptionUrl then aboutDocument = RequestDocument(GET(aux.descriptionUrl, HEADERS)) end
    local novel = NovelInfo {
        title = aux.name,
        imageURL = aux.image,
        description = table.concat(map(aboutDocument:select("#content .entry-content p"), function(v)
            return v:text()
        end), "\n\n", aux.description[1], aux.description[2]),
        authors = { "Wildbow" },
        status = NovelStatus.COMPLETED
    }

    if loadChapters then
        local chaps = {}
        if aux.extractChapters then
            chaps = aux.extractChapters()
        else
            local i = 0
            local tocDocument = document
            map(tocDocument:select(aux.arcs), function(element)
                local arcPrefix = processArcName(element:selectFirst(aux.arc):text())
                chaps = concatLists(chaps, mapNotNil(element:select(aux.chapters), function(v)
                    i = i + 1
                    return NovelChapter {
                        order = i,
                        title = arcPrefix .. v:text(),
                        link = v:attr("href")
                    }
                end))
            end)
        end

        novel:setChapters(AsList(chaps))
    end

    return novel
end

local function getPassage(chapterURL)
    local document = GETDocument(chapterURL)
    map(document:select(".entry-content > :not(p, h1, hr)"), function(v) v:remove() end)
    return pageOfElem(document:selectFirst(".entry-content"), true)
end

return {
    id = 78,
    name = "Wildbow (Parahumans)",
    baseURL = "https://www.parahumans.net/",
    listings = {
        Listing("Novels", false, function(data)
            return map(lift(auxiliary), function(a)
                return Novel {
                    link = a[1],
                    title = a[2].name,
                    imageURL = a[2].image
                }
            end)
        end)
    },
    getPassage = getPassage,
    parseNovel = parseNovel,
    shrinkURL = function(url) return url end,
    expandURL = function(url) return url end,

    imageURL = "https://parahumans.wordpress.com/wp-content/uploads/2011/06/cityscape2.jpg",
    hasCloudFlare = false,
    hasSearch = false,
    chapterType = ChapterType.HTML,
    startIndex = 1,

    updateSetting = function(id, value)
        settings[id] = value
    end,
}
