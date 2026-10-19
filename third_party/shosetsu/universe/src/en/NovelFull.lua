-- {"id":1,"ver":"3.0.1","libVer":"1.0.0","author":"Bigrand, Doomsdayrs, TechnoJo4","dep":["novelvault>=1.0.0"]}

return Require("novelvault")("https://novelfull.com", {
	id = 1,
	name = "NovelFull",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/NovelFull.png",

	searchImgModFunc = function(imageURL)
		return imageURL:gsub("00aa49a68cf30c9157b01d4feff36ff7", "2239c49aee6b961904acf173b7e4602a")
	end,

	listingConfigs = {
		{ name = "Hot Novel", incrementing = true, param = "hot-novel" },
		{ name = "Most Popular", incrementing = true, param = "most-popular" },
		{ name = "Completed Novel", incrementing = true, param = "completed-novel" },
		{ name = "Ongoing Novel", incrementing = true, param = "status/Ongoing" },
		{ name = "Latest Release", incrementing = true, param = "latest-release-novel" },
	},

	supportedFilters = { "genre", "author", "status" },

	statuses = {
        { name = "Ongoing",   param = "status/Ongoing" },
        { name = "Completed", param = "completed-novel" },
    },

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
		"History",
		"Horror",
		"Josei",
		"Lolicon",
		"Magical Realism",
		"Martial",
		"Martial Arts",
		"Mature",
		"Mecha",
		"Mystery",
		"Psychological",
		"Romance",
		"School Life",
		"Sci-fi",
		"Seinen",
		"Shoujo",
		"Shounen",
		"Shounen Ai",
		"Slice of Life",
		"Smut",
		"Sports",
		"Supernatural",
		"Tragedy",
		"Wuxia",
		"Xianxia",
		"Xuanhuan",
		"Yaoi",
		"Yuri",
	}
})
