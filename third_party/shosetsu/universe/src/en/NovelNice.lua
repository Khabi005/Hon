-- {"id":17636,"ver":"6.0.0","libVer":"1.0.0","author":"Bigrand, Doomsdayrs","dep":["Madara>=2.9.2"]}

return Require("Madara")("https://novelnice.com", {
	id = 17636,
	name = "Novel Nice (Novlove)",
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/NovLove.png",
	latestNovelSel = "div.page-listing-item",
	shrinkURLNovel = "read",
    searchHasOper = true,
    hasCloudFlare = true,
    hasSearch = true,

	genres = {
        "action",
        "adventure",
        "comedy",
        "drama",
        "eastern",
        "fantasy",
        "game",
        "historical",
        "horror",
        "josei",
        "martial-arts",
        "mystery",
        "psychological",
        "romance",
        "school-life",
        "sci-fi",
        "shounen",
        "slice-of-life",
        "supernatural",
        "urban",
        "wuxia",
        "xianxia",
        "xuanhuan"
	}
})
