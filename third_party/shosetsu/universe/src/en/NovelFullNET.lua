-- {"id":951840,"ver":"1.0.0","libVer":"1.0.0","author":"Bigrand","dep":["novelvault>=1.0.0"]}

return Require("novelvault")("https://novelfull.net", {
	id = 951840,
	name = "NovelFull (NET)",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/NovelFullNET.png",

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
		"Hentai",
		"Historical",
		"Horror",
		"Isekai",
		"Josei",
		"LGBT+",
		"Lolicon",
		"Magic",
		"Magical",
		"Magical Realism",
		"Manhua",
		"Martial",
		"Martial Arts",
		"Mature",
		"Mecha",
		"Mystery",
		"Psychological",
		"Reincarnation",
		"Romance",
		"School Life",
		"Sci-Fi",
		"Seinen",
		"Shoujo",
		"Shoujo AI",
		"Shounen",
		"Shounen AI",
		"Slice of life",
		"Smut",
		"Sports",
		"Supernatural",
		"System",
		{ name = "Tragedy", param = "genre/traged"},
		"Video Games",
		"Video Games",
		"Wuxia",
		"Xianxia",
		"Xuanhuan",
		"Yaoi",
		"Yuri",
	}
})
