-- {"id":1247865462,"ver":"1.0.0","libVer":"1.0.0","author":"JFronny","dep":["XenForo>=1.0.10"]}

return Require("XenForo")("https://althistory.com/", {
    id = 1247865462,
    name = "AltHistory",
    imageURL = "https://althistory.com/data/svg/25/1/1766884702/favicon_192x192.png",
    forums = {
        {
            title = "Stories and Timelines",
            forum = 9
        },
        {
            title = "Historical Timelines",
            forum = 17
        },
        {
            title = "Future and Science Fiction",
            forum = 19
        },
        {
            title = "Weird Stuff",
            forum = 21
        },
        {
            title = "Crossovers",
            forum = 52
        }
    },
    novelUrlBlacklist = ".*%.20442$"
})
