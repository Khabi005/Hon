-- {"id":61205,"ver":"1.0.1","libVer":"1.0.0","author":"Zordic"}
-- NOTE: `id` above must be a unique number

local json = Require("dkjson")

local baseURL = "https://en.webnovel.com"

local userAgent =
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

local function baseHeaders()
	return HeadersBuilder()
		:add("User-Agent", userAgent)
		:add("Referer", baseURL .. "/")
		:add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8")
		:add("Accept-Language", "en-US,en;q=0.9")
		:build()
end

local function mobileHeaders()
	return HeadersBuilder()
		:add("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1")
		:add("Referer", "https://m.webnovel.com/")
		:build()
end

--- GET a Document (HTML page) with the User-Agent header applied.
--- @param url string
--- @return Document
local function GETDoc(url)
	local req = RequestBuilder():url(url):headers(baseHeaders()):get():build()
	local response = Request(req)
	local body = response:body():string()
	return Document(body)
end

--- GET a URL and decode the raw response body as JSON.
--- @param url string
--- @return table
local function GETJSON(url)
	local req = RequestBuilder():url(url):headers(baseHeaders()):get():build()
	local response = Request(req)
	local body = response:body():string()
	return json.decode(body)
end

local buildId = nil

local function getBuildId()
	if buildId ~= nil then
		return buildId
	end

	local doc = GETDoc(baseURL .. "/category")
	local script = doc:selectFirst("#__NEXT_DATA__")
	if script ~= nil then
		local ok, data = pcall(json.decode, script:html())
		if ok and data ~= nil and data.buildId ~= nil then
			buildId = data.buildId
			return buildId
		end
	end
	return nil
end


local HIDE_LOCKED_ID = 1
local settings = {
	[HIDE_LOCKED_ID] = false,
}
local settingsModel = {
	SwitchFilter(HIDE_LOCKED_ID, "Hide locked chapters"),
}
local function updateSetting(sid, value)
	settings[sid] = value
end

local function shrinkURL(url, ktype)
	return (url:gsub("^https?://[^/]+", ""))
end

local function expandURL(url, ktype)
	if url:sub(1, 1) ~= "/" then
		url = "/" .. url
	end
	return baseURL .. url
end

local SEX_FILTER_ID = 2
local CATEGORY_FILTER_ID = 3
local STATUS_FILTER_ID = 4
local ORDER_FILTER_ID = 6
local FANFIC_FILTER_ID = 7

local SEX_KEYS = { 0, 1, 2 }
local SEX_VALUES = { "All", "Male Oriented", "Female Oriented" }

local CATEGORY_KEYS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }
local CATEGORY_VALUES = { "All", "Urban", "Fantasy", "History", "Horror", "Sci-fi", "Sports", "Games", "Eastern", "Realistic", "Action", "War", "Teen", "LGBT+", "Fanfic" }

local STATUS_KEYS = { 0, 1, 2 }
local STATUS_VALUES = { "All", "Completed", "Ongoing" }

local ORDER_KEYS = { 1, 2, 3, 4, 5 }
local ORDER_VALUES = { "Popular", "Recommended", "Most Collections", "Rating", "Time Updated" }

local searchFilters = {
	TextFilter(FANFIC_FILTER_ID, "Search fanfics (overrides other filters)"),
	DropdownFilter(SEX_FILTER_ID, "Oriented", SEX_VALUES),
	DropdownFilter(CATEGORY_FILTER_ID, "Category", CATEGORY_VALUES),
	DropdownFilter(STATUS_FILTER_ID, "Status", STATUS_VALUES),
	DropdownFilter(ORDER_FILTER_ID, "Order by", ORDER_VALUES),
}

local function fetchNextCategoryList(filterParams, page)
	local bId = getBuildId()
	if bId == nil then
		return {}
	end

	-- Category path format: {sex}_{categoryId}_{bookStatus}_{vipStatus}_{orderBy}_{pageIndex}
	local filter = filterParams .. "_" .. tostring(page)
	local url = baseURL .. "/_next/data/" .. bId .. "/category/" .. filter .. ".json?param=" .. filter

	local data = GETJSON(url)
	if data == nil or data.pageProps == nil or data.pageProps.result == nil or data.pageProps.result.books == nil then
		return {}
	end

	local books = data.pageProps.result.books

	return map(books, function(b)
		local coverUpdateTime = b.coverId or b.coverUpdateTime
		local img = "https://book-pic.webnovel.com/bookcover/" .. tostring(b.bookId) .. "?imageMogr2/quality/60/strip"
		if coverUpdateTime ~= nil then
			img = img .. "&imageId=" .. tostring(coverUpdateTime)
		end

		return Novel {
			title    = b.name or b.bookName or "No Title Found",
			link     = "/book/" .. tostring(b.bookId),
			imageURL = img,
		}
	end)
end



--- @param ch table  a chapterItems[] entry
--- @return boolean
local function chapterIsLocked(ch)
	-- Observed: free chapter -> isVip=0, isAuth=1. Locked chapter -> isVip=2, isAuth=0.
	return not (ch.isVip == 0 and ch.isAuth == 1)
end

--- @param bookId string
--- @param chapterList table  bookDetail.chapterList from __NEXT_DATA__
--- @return table  NovelChapter[]
local function parseChaptersFromDetail(bookId, chapterList)
	local chapters = {}
	local order = 0
	local volumes = (chapterList and chapterList.volumeItems) or {}

	for _, vol in ipairs(volumes) do
		local items = vol.chapterItems or {}
		for _, ch in ipairs(items) do
			local locked = chapterIsLocked(ch)
			if not (locked and settings[HIDE_LOCKED_ID]) then
				local title = ch.chapterName
				if title == nil or title == "" then
					title = "No Title Found"
				end
				if locked then
					title = title .. " 🔒"
				end

				order = order + 1
				table.insert(chapters, NovelChapter {
					title = title,
					link  = "/book/" .. tostring(bookId) .. "/" .. tostring(ch.chapterId),
					order = order,
				})
			end
		end
	end

	return chapters
end

--- @param novelURL string  shrunk novel URL, e.g. "/book/22063196605076705"
--- @return NovelInfo
local function parseNovel(novelURL)
	local url = expandURL(novelURL, KEY_NOVEL_URL)
	local doc = GETDoc(url)

	local script = doc:selectFirst("#__NEXT_DATA__")
	if script == nil then
		return NovelInfo {
			title       = "No Title Found",
			description = "No Summary Found",
			chapters    = {},
		}
	end

	local data = json.decode(script:html())
	local pageProps = data.props and data.props.pageProps or {}
	local bookDetail = pageProps.bookDetail or {}
	local bookInfo = bookDetail.bookInfo or {}

	local genres = {}
	if bookInfo.categoryName ~= nil and bookInfo.categoryName ~= "" then
		table.insert(genres, bookInfo.categoryName)
	end
	if bookInfo.tagInfo ~= nil then
		for _, tag in ipairs(bookInfo.tagInfo) do
			if tag.name ~= nil and tag.name ~= "" then
				table.insert(genres, tag.name)
			end
		end
	end

	-- Determine novel status based on actionStatus
	local status = NovelStatus.UNKNOWN
	if bookInfo.actionStatus == 50 then
		status = NovelStatus.COMPLETED
	elseif bookInfo.actionStatus == 30 then
		status = NovelStatus.PUBLISHING
	end

	local desc = bookInfo.description

	local coverUpdateTime = bookInfo.coverId or bookInfo.coverUpdateTime
	local img = "https://book-pic.webnovel.com/bookcover/" .. tostring(bookInfo.bookId) .. "?imageMogr2/quality/60/strip"
	if coverUpdateTime ~= nil then
		img = img .. "&imageId=" .. tostring(coverUpdateTime)
	end

	local novel = NovelInfo {
		title       = bookInfo.name or "No Title Found",
		imageURL    = img,
		authors     = { "Author: " .. (bookInfo.authorName or "No Author Found") },
		description = (desc ~= nil and desc ~= "") and desc or "No Summary Found",
		genres      = genres,
		status      = status,
	}
	novel:setChapters(parseChaptersFromDetail(bookInfo.bookId, pageProps.chapterList))

	return novel
end

--- @param chapterURL string  shrunk chapter URL, e.g. "/book/{bookId}/{chapterId}"
--- @return string  HTML content
local function getPassage(chapterURL)
	local url = expandURL(chapterURL, KEY_CHAPTER_URL)
	local doc = GETDoc(url)

	local script = doc:selectFirst("#__NEXT_DATA__")
	if script == nil then
		return "<p>Failed to load chapter content.</p>"
	end

	local data = json.decode(script:html())
	local pageProps = data.props and data.props.pageProps or {}
	local chapterInfo = pageProps.chapterInfo or {}

	local titleHTML = ""
	if chapterInfo.chapterName ~= nil and chapterInfo.chapterName ~= "" then
		titleHTML = "<p><b>" .. chapterInfo.chapterName .. "</b></p>"
	end

	local bodyHTML = ""
	local contents = chapterInfo.contents or {}
	for _, block in ipairs(contents) do
		if block.content ~= nil then
			local text = block.content
			if text:find("<") then
				text = Document(text):text()
			end
			text = text:gsub("^%s+", ""):gsub("%s+$", "")
			if text ~= "" then
				text = text:gsub("<", "&lt;"):gsub(">", "&gt;")
				bodyHTML = bodyHTML .. "<br><br>" .. text
			end
		end
	end

	if bodyHTML == "" then
		bodyHTML = "<p>This chapter is locked / has no accessible content.</p>"
	end

	return titleHTML .. bodyHTML
end

local function doSearch(term, page, stype)
	local url = "https://m.webnovel.com/search?keyword=" .. (term:gsub("%s+", "+")) .. "&pageIndex=" .. tostring(page)
	if stype ~= nil then
		url = url .. "&type=" .. stype
	end
	local req = RequestBuilder():url(url):headers(mobileHeaders()):get():build()
	local response = Request(req)
	local code = response:code()
	local body = response:body():string()
	
	if code ~= 200 then
		return {}
	end

	local doc = Document(body)
	local script = doc:selectFirst("#__NEXT_DATA__")
	if script == nil then
		return {}
	end

	local ok, data = pcall(json.decode, script:html())
	if not ok or data == nil then
		return {}
	end

	local props = data.props or {}
	local initialState = props.initialState or {}
	local entities = initialState.entities or {}

	local bookItems = nil
	local isFanfic = false
	local searchResultList = entities.searchResultList or {}
	for _, entry in pairs(searchResultList) do
		if type(entry) == "table" then
			if entry.bookInfo ~= nil and entry.bookInfo.bookItems ~= nil then
				bookItems = entry.bookInfo.bookItems
				break
			elseif entry.fanficBookInfo ~= nil and entry.fanficBookInfo.fanficBookItems ~= nil then
				bookItems = entry.fanficBookInfo.fanficBookItems
				isFanfic = true
				break
			end
		end
	end

	if bookItems == nil then
		return {}
	end

	local books = entities.books or {}
	return map(bookItems, function(item)
		if isFanfic then
			local bookId = tostring(item.bookId)
			local coverUpdateTime = item.coverId or item.coverUpdateTime
			local img = "https://book-pic.webnovel.com/bookcover/" .. bookId .. "?imageMogr2/quality/60/strip"
			if coverUpdateTime ~= nil then
				img = img .. "&imageId=" .. tostring(coverUpdateTime)
			end

			return Novel {
				title    = item.bookName or item.name or "No Title Found",
				link     = "/book/" .. bookId,
				imageURL = img,
			}
		else
			local bookId = tostring(item)
			local book = books[bookId] or {}
			local coverUpdateTime = book.coverId or book.coverUpdateTime
			local img = "https://book-pic.webnovel.com/bookcover/" .. bookId .. "?imageMogr2/quality/60/strip"
			if coverUpdateTime ~= nil then
				img = img .. "&imageId=" .. tostring(coverUpdateTime)
			end

			return Novel {
				title    = book.bookName or book.name or "No Title Found",
				link     = "/book/" .. bookId,
				imageURL = img,
			}
		end
	end)
end

local function search(data)
	local term = data[QUERY]
	local page = data[PAGE]
	-- Fanfic textbox text → always trigger fanfic search
	local fanficTerm = data[FANFIC_FILTER_ID]
	if fanficTerm ~= nil and fanficTerm ~= "" then
		return doSearch(fanficTerm, page, "fanfic")
	end

	if term ~= nil and term ~= "" then
		return doSearch(term, page)
	end

	-- Category filter search
	local sex = SEX_KEYS[(data[SEX_FILTER_ID] or 0) + 1] or 0
	local cat = CATEGORY_KEYS[(data[CATEGORY_FILTER_ID] or 0) + 1] or 0
	local status = STATUS_KEYS[(data[STATUS_FILTER_ID] or 0) + 1] or 0
	local order = ORDER_KEYS[(data[ORDER_FILTER_ID] or 0) + 1] or 1

	local filterParams = string.format("%d_%d_%d_%d_%d", sex, cat, status, 0, order)
	return fetchNextCategoryList(filterParams, page)
end

local listings = {
	Listing("Browse", true, function(data)
		return search(data)
	end),
}

return {
	-- Required
	id = 61205,
	name = "Webnovel",
	baseURL = baseURL,
	imageURL = "https://en.webnovel.com/favicon.ico",
	listings = listings,
	getPassage = getPassage,
	parseNovel = parseNovel,
	shrinkURL = shrinkURL,
	expandURL = expandURL,
	hasCloudFlare = false,
	hasSearch = true,
	isSearchIncrementing = true,
	settings = settingsModel,
	searchFilters = searchFilters,
	chapterType = ChapterType.HTML,
	startIndex = 1,
	search = search,
	updateSetting = updateSetting,
}