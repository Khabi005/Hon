-- {"id":325107,"ver":"1.0.6","libVer":"1.0.0","author":"Bigrand","dep":["novelvault>=1.0.0","dkjson>=1.0.0"]}

local json = Require("dkjson")

return Require("novelvault")("https://freewebnovel.com", {
	id = 325107,
	name = "Free Web Novel",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/FreeWebNovel.png",

	pageParam = "", -- No param, it's `/X`
	authorParam = "author",
	ajaxChaptersURL = "noajax",

	-- There are actually additional filters for this source,  
	-- but it's just this one source that wants to be different and special,  
	-- so it can stay missing for all I care :D
	listingConfigs = {
		{ name = "Latest Release", incrementing = true, param = "sort/latest-release" },
		{ name = "Latest Novel", incrementing = true, param = "sort/latest-novel" },
		{ name = "Completed Novel", incrementing = true, param = "sort/completed-novel" },
		{ name = "Most Popular (All)", incrementing = false, param = "sort/most-popular" },
		{ name = "Most Popular (Month)", incrementing = false, param = "most-popular/monthvisit" },
		{ name = "Most Popular (Week)", incrementing = false, param = "most-popular/weekvisit" },
		{ name = "Most Popular (Day)", incrementing = false, param = "most-popular/dayvisit" },
	},

	supportedFilters = { "genre", "author" },

	-- The AJAX endpoint returns JSON: { code, html, page, pageSize, totalPage, totalChapters }
	-- where `html` holds <li><a href="..." title="..." class="con"> chapter links.
	-- Max pageSize is 200 → only 10 requests for a 1905-chapter novel.
	-- totalPage is read from the first response so we know exactly how many pages to fetch.
	-- We add a 0.5s delay between requests to avoid rate limits on 4000+ chapter novels.
	chapterFetcher = function(self, novelURL, _document)
		local pageSize = 200
		local chapters, i = {}, 0

		local function parsePage(data)
			if type(data) == "string" then data = json.decode(data) end
			if type(data) ~= "table" or data.code ~= 200 or not data.html then return nil end
			mapNotNil(Document(data.html):select("a.con"), function(v)
				local title = v:attr("title")
				local href  = v:attr("href")
				if not href or href == "" then return nil end
				if not title or title == "" then title = v:text() end
				i = i + 1
				table.insert(chapters, NovelChapter { order=i, title=title, link=href:match("^/(.*)") or self.shrinkURL(href) })
				return true
			end)
			return data
		end

		local first = parsePage(json.GET(novelURL .. "?ajax=chapters&page=1&pageSize=" .. pageSize))
		if not first then return AsList(chapters) end
		for p = 2, (first.totalPage or 1) do
			local start = os.time()
			while os.time() - start < 1 do end
			parsePage(json.GET(novelURL .. "?ajax=chapters&page=" .. p .. "&pageSize=" .. pageSize))
		end

		return AsList(chapters)
	end,

	genres = {
		"Action",
		"Adult",
		"Adventure",
		"Comedy",
		"Drama",
		"Eastern",
		"Ecchi",
		"Fantasy",
		"Game",
		"Gender Bender",
		"Harem",
		"Historical",
		"Horror",
		"Josei",
		"Martial Arts",
		"Mature",
		"Mecha",
		"Mystery",
		"Psychological",
		"Reincarnation",
		"Romance",
		"School Life",
		"Sci-fi",
		"Seinen",
		"Shoujo",
		"Shounen",
		"Shounen AI",
		"Slice of Life",
		"Smut",
		"Sports",
		"Supernatural",
		"Tragedy",
		"Wuxia",
		"Xianxia",
		"Xuanhuan",
		"Yaoi",
	}
})
