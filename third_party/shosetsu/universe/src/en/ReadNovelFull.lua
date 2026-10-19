-- {"id":171264,"ver":"1.0.0","libVer":"1.0.0","author":"Bigrand","dep":["novelvault>=1.0.0"]}

return Require("novelvault")("https://readnovelfull.com", {
	id = 171264,
	name = "Read Novel Full",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/ReadNovelFull.png",

	authorParam = "authors",
	genreParam = "genres",
	searchParam = "novel-list/search",
	ajaxChaptersURL = "ajax/chapter-archive",

	searchImgModFunc = function(imageURL)
		return imageURL:gsub("80x113", "300x439")
	end,

	listingConfigs = {
		{ name = "Hot Novel", incrementing = true, param = "novel-list/hot-novel" },
		{ name = "Most Popular", incrementing = true, param = "novel-list/most-popular-novel" },
		{ name = "Completed Novel", incrementing = true, param = "novel-list/completed-novel" },
		{ name = "Ongoing Novel", incrementing = true, param = "novel-list/ongoing-novel" },
		{ name = "Latest Release", incrementing = true, param = "novel-list/latest-release-novel" },
	},

	supportedFilters = { "genre", "author", "status" },

	statuses = {
		{ name = "Ongoing",   param = "novel-list/ongoing-novel" },
		{ name = "Completed", param = "novel-list/completed-novel" },
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
		"Tragedy",
		"Video Games",
		"Video Games",
		"Wuxia",
		"Xianxia",
		"Xuanhuan",
		"Yaoi",
		"Yuri",
	}
})
