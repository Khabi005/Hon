-- {"id":1403038472,"ver":"1.1.2","libVer":"1.0.0","author":"JFronny","dep":["XenForo>=1.0.17"]}

return Require("XenForo")("https://forums.spacebattles.com/", {
    id = 1403038472,
    name = "SpaceBattles",
    imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/SpaceBattles.png",
    forums = {
        {
            title = "Creative Writing",
            forum = 18
        },
        {
            title = "Original Fiction",
            forum = 48
        },
        {
            title = "Creative Writing Archives",
            forum = 40
        },
        {
            title = "Worm",
            forum = 115
        },
        {
            title = "Quests",
            forum = 240
        }
        --{
        --    title = "Quests (Story Only)",
        --    forum = 252
        --}
    }
})
