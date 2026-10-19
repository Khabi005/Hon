-- {"id":96601,"ver":"1.0.1","libVer":"1.0.0","author":"enhance7191"}
local json = Require("dkjson")
local baseURL = "https://shanghaifantasy.com"

---@param v Element
local text = function(v)
    return v:text()
end


---@param url string
---@param type int
local function shrinkURL(url)
    return url:gsub("https://shanghaifantasy.com", "")
end

---@param url string
---@param type int
local function expandURL(url)
    return baseURL .. url
end

local GENRE_FILTER = 2
local GENRE_VALUES = { 
"All",
"1960s",
"1970s",
"1980s",
"ABO",
"abuse",
"Action",
"Adapted to Manhua",
"Adopted Children",
"Adult",
"Adventure",
"Age Gap",
"AI",
"Alternate World",
"Amnesia",
"Ancient China",
"Ancient Romance",
"Ancient Times",
"and many heroines are slapped in the face",
"and rural areas",
"Angst",
"Apocalypse",
"Army",
"Arranged Marriage",
"Beastmen",
"Beautiful Female Lead",
"Beautiful protagonist",
"BG",
"Bickering Couple",
"BL",
"Brotherhood",
"Business management",
"Businessmen",
"Bussiness",
"Buy and Sell",
"Card Game",
"caring protagonist",
"Celebrities",
"celebrity",
"CEO",
"Character Growth",
"Charming Protagonist",
"Childcare",
"Childhood Love",
"cohabitation",
"Comeback Drama",
"comedic undertone",
"Comedy",
"comedy. drama",
"Coming-of-age",
"Completed",
"Cooking",
"Countryside",
"Court",
"Crime",
"Criminal Investigation",
"Crippled Hero",
"Crossing",
"Cub Rearing",
"cultivation",
"cute baby",
"Cute Children",
"cute pet",
"Cute Protagonist",
"Cute Story",
"Cyberpunk",
"Death",
"Devoted Love Interest",
"Dimensional trade",
"disabilities",
"Divine Doctor",
"Doting Brothers",
"Doting Husband",
"Doting Love Interest",
"Drama",
"Dual Purity",
"Ecchi",
"Elite Family",
"Emperor",
"Empress",
"Entertainment",
"Entertainment Industry",
"Era",
"Erotica",
"Escape from Marriage",
"Esports",
"Face-Slapping",
"Familial Love",
"Family conflict",
"Family Drama",
"Fanfiction",
"Fantasy",
"fantasy future",
"Fantasy Magic",
"Fantasy Romance",
"Farming",
"Fat to Fit",
"Feel-good Fiction",
"Female Lead",
"Female Protagonist",
"first love",
"Fishing",
"Flash Marriage",
"Food",
"Future",
"Game",
"Game World",
"Gangsters",
"Gender Bender",
"general",
"GL",
"Godly Power",
"Gourmet Food",
"Group Favorite",
"Growth",
"Growth-Oriented Female Protagonist",
"handsome male lead",
"Hardworking",
"Harem",
"Heartthrob Protagonist",
"Heroism",
"Historical",
"Historical Fiction",
"Historical Romance",
"Hoarding",
"Horror",
"House Fighting",
"Idol",
"Industry Elite",
"infrastructure",
"Innocent",
"Interstellar",
"Isekai",
"Josei",
"large age gap",
"Light-hearted",
"Little Wife",
"Livestream",
"livestreaming",
"love",
"Love After Marriage",
"love at first sight",
"Love Interest Falls in Love First",
"love over time",
"Love triangle",
"Love-Hate Relationship",
"Loving Parents",
"Loyal",
"Lucky Protagonist",
"Mafia",
"Magic",
"Magical",
"magical space",
"Male Protagonist",
"many heroines are slapped in the face",
"Marriage",
"Martial Arts",
"Mature",
"Mecha",
"Medicine",
"Melodrama",
"Military",
"Military Husband",
"Military Strategy",
"Military Wedding",
"Military Wife",
"mind reading",
"Mistreated Child",
"Modern",
"Modern Day",
"modern love",
"Modern Romance",
"Mpreg",
"Multiple Identities",
"Mystery",
"Mythical Beasts",
"Obsessive Love",
"Older Love Interests",
"omegaverse",
"One True Love",
"Palace Drama",
"palace fighting",
"Period Novel",
"Political",
"Poor to rich",
"Possessive Love Interest",
"Power Couple",
"pregnancy",
"Prince",
"Protagonist Strong at the Start",
"Psychological",
"pure love",
"Purity",
"Quick transmigration",
"Rags to Riches",
"rape",
"Rebirth",
"Reborn",
"reincarnation",
"Reunion",
"Revenge",
"Rich CEO",
"Romance",
"Romantic Element",
"Royal Family",
"rural areas",
"Ruthless ML",
"Sadomasochism",
"SameSexMarriage",
"Scheming",
"Scholar",
"School Life",
"Sci-fi",
"Sealed Power",
"Second Chance",
"Secret Crush",
"Secret Identity",
"Selling Platform",
"Short Story",
"Shoujo",
"Shoujo Ai",
"Shounen",
"Shounen Ai",
"Showbiz",
"Slice of Life",
"Slightly BL",
"Slow Burn",
"slow romance",
"Slow-burn Romance",
"Smart",
"Smart Couple",
"Smut",
"Space",
"Space Ability",
"Sports",
"Storage Space",
"Strong Female Lead",
"Strong Lead",
"Strong Love Interest",
"Strong to Stronger",
"Success",
"Supernatural",
"Supporting character",
"Survival Game",
"Suspense",
"Sweet Doting",
"Sweet Love",
"Sweet Romance",
"Sweet Spoiling",
"Sweet Story",
"SweetNovel",
"system",
"System Flow",
"Thriller",
"Time Travel",
"Tragedy",
"Transformation",
"Transmigrated",
"Transmigration",
"trav",
"Unlucky",
"Unrequited Love",
"Urban",
"Urban Love",
"Villain",
"Virtual",
"Weak to Strong",
"Wealthy CEO",
"Wealthy Family",
"weaving",
"workplace",
"Wuxia",
"Xianxia",
"Xuanhuan",
"yandere",
"Yandere Character",
"Yaoi",
"Younger Love Interest",
"Yuri",
"Zombie"
}
local GENREPARAMS = {
"",
"1960s",
"1970s",
"1980s",
"ABO",
"abuse",
"Action",
"Adapted to Manhua",
"Adopted Children",
"Adult",
"Adventure",
"Age Gap",
"AI",
"Alternate World",
"Amnesia",
"Ancient China",
"Ancient Romance",
"Ancient Times",
"and many heroines are slapped in the face",
"and rural areas",
"Angst",
"Apocalypse",
"Army",
"Arranged Marriage",
"Beastmen",
"Beautiful Female Lead",
"Beautiful protagonist",
"BG",
"Bickering Couple",
"BL",
"Brotherhood",
"Business management",
"Businessmen",
"Bussiness",
"Buy and Sell",
"Card Game",
"caring protagonist",
"Celebrities",
"celebrity",
"CEO",
"Character Growth",
"Charming Protagonist",
"Childcare",
"Childhood Love",
"cohabitation",
"Comeback Drama",
"comedic undertone",
"Comedy",
"comedy. drama",
"Coming-of-age",
"Completed",
"Cooking",
"Countryside",
"Court",
"Crime",
"Criminal Investigation",
"Crippled Hero",
"Crossing",
"Cub Rearing",
"cultivation",
"cute baby",
"Cute Children",
"cute pet",
"Cute Protagonist",
"Cute Story",
"Cyberpunk",
"Death",
"Devoted Love Interest",
"Dimensional trade",
"disabilities",
"Divine Doctor",
"Doting Brothers",
"Doting Husband",
"Doting Love Interest",
"Drama",
"Dual Purity",
"Ecchi",
"Elite Family",
"Emperor",
"Empress",
"Entertainment",
"Entertainment Industry",
"Era",
"Erotica",
"Escape from Marriage",
"Esports",
"Face-Slapping",
"Familial Love",
"Family conflict",
"Family Drama",
"Fanfiction",
"Fantasy",
"fantasy future",
"Fantasy Magic",
"Fantasy Romance",
"Farming",
"Fat to Fit",
"Feel-good Fiction",
"Female Lead",
"Female Protagonist",
"first love",
"Fishing",
"Flash Marriage",
"Food",
"Future",
"Game",
"Game World",
"Gangsters",
"Gender Bender",
"general",
"GL",
"Godly Power",
"Gourmet Food",
"Group Favorite",
"Growth",
"Growth-Oriented Female Protagonist",
"handsome male lead",
"Hardworking",
"Harem",
"Heartthrob Protagonist",
"Heroism",
"Historical",
"Historical Fiction",
"Historical Romance",
"Hoarding",
"Horror",
"House Fighting",
"Idol",
"Industry Elite",
"infrastructure",
"Innocent",
"Interstellar",
"Isekai",
"Josei",
"large age gap",
"Light-hearted",
"Little Wife",
"Livestream",
"livestreaming",
"love",
"Love After Marriage",
"love at first sight",
"Love Interest Falls in Love First",
"love over time",
"Love triangle",
"Love-Hate Relationship",
"Loving Parents",
"Loyal",
"Lucky Protagonist",
"Mafia",
"Magic",
"Magical",
"magical space",
"Male Protagonist",
"many heroines are slapped in the face",
"Marriage",
"Martial Arts",
"Mature",
"Mecha",
"Medicine",
"Melodrama",
"Military",
"Military Husband",
"Military Strategy",
"Military Wedding",
"Military Wife",
"mind reading",
"Mistreated Child",
"Modern",
"Modern Day",
"modern love",
"Modern Romance",
"Mpreg",
"Multiple Identities",
"Mystery",
"Mythical Beasts",
"Obsessive Love",
"Older Love Interests",
"omegaverse",
"One True Love",
"Palace Drama",
"palace fighting",
"Period Novel",
"Political",
"Poor to rich",
"Possessive Love Interest",
"Power Couple",
"pregnancy",
"Prince",
"Protagonist Strong at the Start",
"Psychological",
"pure love",
"Purity",
"Quick transmigration",
"Rags to Riches",
"rape",
"Rebirth",
"Reborn",
"reincarnation",
"Reunion",
"Revenge",
"Rich CEO",
"Romance",
"Romantic Element",
"Royal Family",
"rural areas",
"Ruthless ML",
"Sadomasochism",
"SameSexMarriage",
"Scheming",
"Scholar",
"School Life",
"Sci-fi",
"Sealed Power",
"Second Chance",
"Secret Crush",
"Secret Identity",
"Selling Platform",
"Short Story",
"Shoujo",
"Shoujo Ai",
"Shounen",
"Shounen Ai",
"Showbiz",
"Slice of Life",
"Slightly BL",
"Slow Burn",
"slow romance",
"Slow-burn Romance",
"Smart",
"Smart Couple",
"Smut",
"Space",
"Space Ability",
"Sports",
"Storage Space",
"Strong Female Lead",
"Strong Lead",
"Strong Love Interest",
"Strong to Stronger",
"Success",
"Supernatural",
"Supporting character",
"Survival Game",
"Suspense",
"Sweet Doting",
"Sweet Love",
"Sweet Romance",
"Sweet Spoiling",
"Sweet Story",
"SweetNovel",
"system",
"System Flow",
"Thriller",
"Time Travel",
"Tragedy",
"Transformation",
"Transmigrated",
"Transmigration",
"trav",
"Unlucky",
"Unrequited Love",
"Urban",
"Urban Love",
"Villain",
"Virtual",
"Weak to Strong",
"Wealthy CEO",
"Wealthy Family",
"weaving",
"workplace",
"Wuxia",
"Xianxia",
"Xuanhuan",
"yandere",
"Yandere Character",
"Yaoi",
"Younger Love Interest",
"Yuri",
"Zombie"
}

local STATUS_FILTER_KEY = 3
local STATUS_VALUES = { "All", "Completed", "Dropped", "Hiatus", "Ongoing", "Pending" }
local STATUS_PARAMS = {"", "Completed", "Dropped", "Hiatus", "Ongoing", "Pending"}

local searchFilters = {
    DropdownFilter(GENRE_FILTER, "Genre", GENRE_VALUES),
    DropdownFilter(STATUS_FILTER_KEY, "Status", STATUS_VALUES)
}

local function remove_blank_p_tags(doc)
    local toRemove = {}
    doc:traverse(NodeVisitor(function(v)
        if v:tagName() == "p" and v:text() == "" then
            toRemove[#toRemove+1] = v
        end
    end, nil, true))
    for _,v in pairs(toRemove) do
        v:remove()
    end
    return doc
end

--- @param chapterURL string @url of the chapter
--- @return string @of chapter
local function getPassage(chapterURL)
    local htmlElement = GETDocument(chapterURL)
    local title = htmlElement:selectFirst("div.my-5"):text()
    htmlElement = htmlElement:selectFirst("div.flex:nth-child(4)")
    htmlElement:child(0):before("<h1>" .. title .. "</h1>")
    htmlElement:select("button"):remove()
    htmlElement = remove_blank_p_tags(htmlElement)
    return pageOfElem(htmlElement, true)
end

local function parseNovelDescription(document, isFiltered)
    local summaryContent = document:selectFirst("div.rounded-xl:nth-child(1)")
    if summaryContent then
        summaryContent = remove_blank_p_tags(summaryContent)
        local description = table.concat(map(summaryContent:select("p"), text), "\n\n")
        if isFiltered then
            description = "!! 💰 Contains Paid Chapters !! \n" .. description
        end
        return description
    end
    return ""
end

--- @param novelURL string @URL of novel
--- @return NovelInfo
local function parseNovel(novelURL)
    local url = baseURL .. novelURL
    local document = GETDocument(url)
    local novelID = document:selectFirst("#chapterList"):attr("data-cat")
    local chURL = baseURL .. "/wp-json/fiction/v1/chapters?category=" .. novelID .. "&order=asc&page=1&per_page=9999"
    local chResponse = RequestDocument(GET(chURL, nil, nil))

    
    -- Filter out entries with "locked" = true
    local data, _, err = json.decode(chResponse:text())
    if err then
        error("Error parsing JSON: " .. err)
    end

    local filteredData = {}
    local isFiltered = false

    for _, entry in ipairs(data) do
        if not entry.locked then
            table.insert(filteredData, entry)
        else
            isFiltered = true
        end
    end

    return NovelInfo {
        title = document:selectFirst("p.mb-3"):text(),
        description = parseNovelDescription(document, isFiltered),
        imageURL = document:selectFirst("div.mt-10 img"):attr("data-cfsrc"),
        status = ({
            Ongoing = NovelStatus.PUBLISHING,
            Completed = NovelStatus.COMPLETED,
            Hiatus = NovelStatus.PAUSED
        })[document:selectFirst(".ml-5 a p"):text()],
        authors = { document:selectFirst("p.text-sm:nth-child(3)"):text()},
        genres = map(document:select("div.mb-3:nth-child(4) span"), text ),
        chapters = AsList(
                map(filteredData, function(v)
                    return NovelChapter {
                        order = v,
                        title = v.title,
                        link = v.permalink
                    }
                end)
        )
    }
end

local function parseListing(listingURL)
    local document = RequestDocument(GET(listingURL, nil, nil))
    document = json.decode(document:text())
    return map(document, function(v)
        return Novel {
            title = v.title,
            link = shrinkURL(v.permalink),
            imageURL = v.novelImage
        }
    end)
end

local function getListing(data)
    local genre = data[GENRE_FILTER]
    local status = data[STATUS_FILTER_KEY]
    local page = data[PAGE]
    local genreValue = ""
    local statusValue = ""
    if genre ~= nil then
        genreValue = GENREPARAMS[genre+1]
    end
    if status ~= nil then
        statusValue = STATUS_PARAMS[status+1]
    end
    local url = baseURL .. "/wp-json/fiction/v1/novels/?novelstatus=" .. statusValue .. "&term=" .. genreValue .. "&page=".. page .. "&orderby=&order="
    return parseListing(url)
end

return {
    id = 96601,
    name = "Shanghai Fantasy",
    baseURL = baseURL,
    imageURL = "https://shanghaifantasy.com/wp-content/uploads/2021/08/cropped-Showing-3-270x270.png",
    hasSearch = false,
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