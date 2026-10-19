-- {"id":174133,"ver":"1.0.0","libVer":"1.0.0","author":"Bigrand","dep":["novelvault>=1.0.0"]}

return Require("novelvault")("https://lightnovelplus.com", {
	id = 174133,
	name = "Light Novel Plus",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/LightNovelPlus.png",

	searchParam = "book/search.html",
	pageParam = "page_num",
	ajaxChaptersURL = "get_chapter_list",
	novelIdParam = "bookId",
	novelIdPattern = "book/(%d+)",

	listingConfigs = {
		{ name = "Hot Novel", incrementing = true, param = "book/bookclass.html?type=hot_novel" },
		{ name = "Completed Novel", incrementing = true, param = "book/bookclass.html?type=completed_novel" },
		{ name = "Latest Release", incrementing = true, param = "book/bookclass.html?type=last_release" },
	},

	supportedFilters = { "genre" },

	genres = {
		{ name = "Action", param = "book/bookclass.html?type=category_novel&id=132" },
		{ name = "Adventure", param = "book/bookclass.html?type=category_novel&id=62" },
		{ name = "Fantasy", param = "book/bookclass.html?type=category_novel&id=60" },
		{ name = "Fantasy #2", param = "book/bookclass.html?type=category_novel&id=70" },
		{ name = "Historical", param = "book/bookclass.html?type=category_novel&id=74" },
		{ name = "LGBT+", param = "book/bookclass.html?type=category_novel&id=182" },
		{ name = "Modern", param = "book/bookclass.html?type=category_novel&id=66" },
		{ name = "Mystery", param = "book/bookclass.html?type=category_novel&id=63" },
		{ name = "Romance", param = "book/bookclass.html?type=category_novel&id=68" },
		{ name = "Sci-Fi", param = "book/bookclass.html?type=category_novel&id=61" },
		{ name = "Xuanhuan", param = "book/bookclass.html?type=category_novel&id=64" },
	}
})
