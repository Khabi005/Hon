-- {"id":1241865462,"ver":"1.1.2","libVer":"1.0.0","author":"JFronny","dep":["XenForo>=1.0.2"]}

return Require("XenForo")("https://forums.sufficientvelocity.com/", {
    id = 1241865462,
    name = "Sufficient Velocity",
    imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/SufficientVelocity.png",
    forums = {
        {
            title = "User Fiction",
            forum = 2
        },
        {
            title = "Original Fiction",
            forum = 157
        },
        {
            title = "Worm",
            forum = 94
        },
        {
            title = "Archive",
            forum = 31
        },
        {
            title = "Alternate History",
            forum = 91
        },
        {
            title = "Weird History",
            forum = 95
        },
        {
            title = "Quests",
            forum = 29
        },
        {
            title = "Quests Archive",
            forum = 17
        }
    },
    novelUrlBlacklist = ".*%.20442$"
})
