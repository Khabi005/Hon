-- {"id":28505740,"ver":"1.2.5","libVer":"1.0.0","author":"Bigrand, Khonkhortisan","dep":["CommonCSS>=1.0.0","unhtml>=1.0.0","url>=1.0.0"]}

local baseURL = "https://novelasligeras.net" --WordPress site, plugins: WooCommerce, Yoast SEO, js_composer, user_verificat_front, avatar-privacy
local HTMLToString = Require("unhtml").HTMLToString
local qs = Require("url").querystring
local css = Require("CommonCSS").table
local urlLib = Require("url")
local encode = urlLib.encode
local decode = urlLib.decode

-- LUA ARRAYS ONLY KNOW HOW TO COUNT FROM 0 or 1
local ORDER_BY_FILTER_EXT = {
	"Ordenar por los últimos",
	"Orden alfabético",
	"Relevancia",
	"Ordenar por popularidad",
	"Ordenar por calificación media",
	"Ordenar por precio: bajo a alto",
	"Ordenar por precio: alto a bajo",
	"Orden aleatorio"
}

local ORDER_BY_FILTER_INT = {
	[0] = "date", --Ordenar por los últimos
	"title"     , --Orden alfabético/Orden por defecto (Listing is title, webview search is title-DESC, selecting Orden por defecto is menu_order)
	"relevance" , --Relevancia (webview search is title-DESC when it should be relevance)
	"popularity", --Ordenar por popularidad
	"rating"    , --Ordenar por calificación media
	"price"     , --Ordenar por precio: bajo a alto
	"price-desc", --Ordenar por precio: alto a bajo
	"rand"      , --single-seed random order
	--only some of these can be descending
}
local ORDER_BY_FILTER_KEY = 789
local ORDER_FILTER_KEY = 1010

--can this be multi-select? https://stackoverflow.com/a/27898435 https://developer.wordpress.org/reference/classes/wp_query/
--https://novelasligeras.net/index.php/lista-de-novela-ligera-novela-web/?ixwpst[product_cat][0]=52&ixwpst[product_cat][1]=49&ixwpst[product_cat][2]=-45
--currently in OR mode, not AND https://wordpress.org/support/topic/multiple-categories-per-filter-results/ https://prnt.sc/tl9zt9 https://prnt.sc/t9wsoy
local CATEGORIAS_FILTER_INT = {
	[0] = "", --Cualquier Categoría
	40, --Acción
	53, --Adulto
	52, --Artes Marciales
	41, --Aventura
	59, --Ciencia Ficción
	43, --Comedia
	44, --Drama
	45, --Ecchi
	46, --Fantasía
	48, --Harem
	49, --Histórico
	50, --Horror
	54, --Mechas (Robots Gigantes)
	55, --Misterio
	56, --Psicológico
	66, --Recuentos de la Vida
	57, --Romance
	60, --Seinen
	64, --Shonen
	69, --Sobrenatural
	70, --Tragedia
	58, --Vida Escolar
	72, --Xianxia
	73, --Xuanhuan
}
local CATEGORIAS_FILTER_KEY = 4242

local ESTADO_FILTER_INT = {
	[0] = "", --Cualquiera --NovelStatus.UNKNOWN
	 16,     --En Proceso --NovelStatus.PUBLISHING
	 17,     --Pausado    --NovelStatus.PAUSED
	407,    --Completado --NovelStatus.COMPLETED
}
local ESTADO_FILTER_KEY = 407

local TIPO_FILTER_INT = {
	[0] = "", --Cualquier
	23, --Novela Ligera
	24, --Novela Web
}
local TIPO_FILTER_KEY = 2324

local PAIS_FILTER_INT = {
	[0] = "", --Cualquiera
	  20, --China
	  22, --Corea
	  21, --Japón
}
local PAIS_FILTER_KEY = 2121
local searchHasOperId = 2323

local ADBLOCK_SETTING_KEY = 0
local SUBSCRIBEBLOCK_SETTING_KEY = 1
local settings = {
--	[ADBLOCK_SETTING_KEY] = false,
--	[SUBSCRIBEBLOCK_SETTING_KEY] = false,
}

local function safeFetch(url)
	local ok, document = pcall(GETDocument, url)

	if not ok then
		local errMsg = tostring(document)
		local code = errMsg:match("(%d%d%d)")

		if code == "429" then
			error("Limite de llamadas alcanzado. Intentalo más tarde.")
		elseif code == "403" then
			error("CAPTCHA detectado. Usa WebView para completarlo."
				.. "\nSi se queda en bucle, instala WebView Tester:"
				.. "\nhttps://github.com/lsrom/webview-tester/releases/tag/2.2"
				.. "\nColoca cualquier página y luego cambia el User Agent en opciones avanzadas con el de WebView Tester.")
		else
			error("HTTP error: " .. (code or errMsg))
		end
	end

	local title = document:selectFirst("title"):text()
	if title == "Just a moment..." then
		error("CAPTCHA detectado. Usa WebView para completarlo.")
	end

	return document
end

local text = function(v)
	return v:text()
end

local function getImageURL(img)
	local srcset = img:attr("data-srcset")
	if srcset and srcset ~= "" then
		local max_url, max_size = "", 0
		for url, size in srcset:gmatch("(http.-) (%d+)w") do
			local num = tonumber(size)
			if num and num > max_size then
				max_size = num
				max_url = url
			end
		end
		return max_url
	end

	return img:attr("data-src") ~= "" and img:attr("data-src")
	    or img:attr("src") ~= "" and img:attr("src")
	    or ""
end

local function shrinkURL(url)
    return url:gsub("^https?://[^/]+/index%.php/", ""):gsub("^producto/", ""):gsub("/$", "")
end

local function expandURL(url, type)
	if type == 1 then -- it's a novel URL
		url = "index.php/producto/" .. url
	elseif type == 2 then
		url = "index.php/".. url
	end

	return baseURL .. "/" .. url
end

local function createFilterString(data)
	--ixwpst[product_cat] is fine being a sparse array, so no need to count up from 0

	local function MultiQuery(ints)
		local arr = {}
		for i=1,#ints do
			if data[ints[i]] then
				arr[#arr+1] = ints[i]
			end
		end
		return arr
	end

	local orderby = ORDER_BY_FILTER_INT[data[ORDER_BY_FILTER_KEY]]
	if data[ORDER_FILTER_KEY] then
		orderby =orderby.. "-desc"
	end

	local pa_tipo
	if data[TIPO_FILTER_KEY] ~= 0 then
		pa_tipo = TIPO_FILTER_INT[data[TIPO_FILTER_KEY]]
	end

	local op
	if data[searchHasOperId] ~= 0 then
		op = data[searchHasOperId]
	end

	return decode(qs({
		orderby = orderby,
		['ixwpst[product_cat][]'] = MultiQuery(CATEGORIAS_FILTER_INT),
		['ixwpst[pa_estado][]'] = MultiQuery(ESTADO_FILTER_INT),
		['ixwpst[pa_tipo][]'] = pa_tipo,
		['ixwpst[pa_pais][]'] = MultiQuery(PAIS_FILTER_INT),
		['ixwpst[op][]'] = op,
	}))

	--https://novelasligeras.net/?product_tag[0]=guerras&product_tag[1]=Asesinatos
	--other than orderby, filters in url must not be empty
	--Logic is (cat1 OR cat2) AND (tag1 OR tag2)
end

local function createSearchString(data)
	return expandURL("?s=" .. encode(data[QUERY]) .. "&post_type=product&" .. createFilterString(data))
end

local totalPages = 1
local function parseListing(listingURL, page)
    if page > totalPages then return {} end

	local doc = safeFetch(listingURL)
	local results = doc:selectFirst(".dt-css-grid")

    local lastPage = doc:select("div.woocommerce-pagination.paginator > a.page-numbers:not(.nav-next):not(.nav-prev):not(.act)")
    lastPage = lastPage and lastPage:last()
    totalPages = tonumber(lastPage and lastPage:text()) or 1

    -- Single‐result page (no listing = product page)
    if not results then
        local titleEl = doc:selectFirst(".content .entry-summary .entry-title")
        local linkEl  = doc:selectFirst('link[href*="/producto/"]')
        local imgEl   = doc:selectFirst(".content .wp-post-image")

        local title = titleEl and titleEl:text() or ""
        local link  = linkEl and shrinkURL(linkEl:attr("href"))
        local imageURL = getImageURL(imgEl)

		if not title ~= "" then -- This could be a problem if the CSS changes in the future
			return {}
		end

        return { Novel { title = title, link = link, imageURL = imageURL } }
    end

	if results then
		return map(results:children(), function(v)
			local a = v:selectFirst(".entry-title a")
			return Novel {
				title = a:text(),
				link = shrinkURL(a:attr("href")),
				imageURL = getImageURL(v:selectFirst("img")),
			}
		end)
	end
	return {}
end

local function parseNovel(novelURL, loadChapters)
	local url = expandURL(novelURL, 1)
	local doc = safeFetch(url)

	local page = doc:selectFirst(".content")
	local header = page:selectFirst(".entry-summary")
	local title = header:selectFirst(".entry-title"):text()
	local info = page:selectFirst(".woocommerce-product-details__short-description")
	local artists = map(page:select(".woocommerce-product-attributes-item--attribute_pa_ilustrador td p a"), text)
	artists = (artists[1] ~= "N/A") and artists or nil
	local genres = header:selectFirst(".posted_in")
	local tags = header:selectFirst(".tagged_as")
	local status = page:selectFirst(".woocommerce-product-attributes-item--attribute_pa_estado td p a")
	and page:selectFirst(".woocommerce-product-attributes-item--attribute_pa_estado td p a"):text() or ""

	local imgEl = page:selectFirst(".wp-post-image")
	local imageURL = getImageURL(imgEl)

	local novel = NovelInfo {
		imageURL = imageURL,
		title = title,
		authors = map(page:select(".woocommerce-product-attributes-item--attribute_pa_escritor td p a"), text),
		artists = artists,
		status = ({
			Completado = NovelStatus.COMPLETED,
			["En Proceso"] = NovelStatus.PUBLISHING,
			Pausado = NovelStatus.PAUSED,
			Cancelado = NovelStatus.COMPLETED
		})[status] or NovelStatus.UNKNOWN,
		genres = map(genres:select("a"), text),
		tags = map(tags:select("a"), text),
		description = HTMLToString(info),
	}
	-- '.wpb_wrapper' has left column whole chapters '.wpb_tabs_nav a' and right column chapter parts '.post-content a'
	if loadChapters then
		local i = 0
		novel:setChapters(AsList(map(doc:select(".wpb_tab a"), function(v) --each volume has multiple tabs, each tab has one or more a, each a is a chapter title/link/before time
			local a = v
			local a_time = a:lastElementSibling() --it's possible this isn't the <time> element
			i = i + 1
			return NovelChapter {
				order = i,
				title = a and a:text() or nil,
				link = shrinkURL((a and a:attr("href"))) or nil,
				--release = (v:selectFirst("time") and (v:selectFirst("time"):attr("datetime") or v:selectFirst("time"):text())) or nil
				release = (a_time and (a_time:attr("datetime") or a_time:text())) or ""
			}
		end)))
	end

	return novel
end

local function getPassage(passageURL)
	local url = expandURL(passageURL, 2)
	local doc = safeFetch(url)
	local chapter = doc:selectFirst(".wpb_text_column .wpb_wrapper")

	--leave any other possible <center> tags alone
	if not settings[ADBLOCK_SETTING_KEY] then --block Publicidad Y-AR, Publicidad M-M4, etc.
		chapter:select("div center:matchesOwn(^Publicidad [A-Z0-9]-[A-Z0-9][A-Z0-9])"):remove()
	end
	if not settings[SUBSCRIBEBLOCK_SETTING_KEY] then --hide "¡Ayudanos! A traducir novelas del japones ¡Suscribete! A NOVA" (86)
		chapter:select("div center a[href*=index.php/nuestras-suscripciones/]"):remove()
	end

	chapter:selectFirst("h1"):remove() -- Delete novel's title

	local customCSS =
	[[
	img.wp-smiley, img.emoji {
		height: 1em !important;
	}
	p:has(img) {
		text-indent: 0em;
	}
	]]..css

	--emoji svg is too big without css from head https://novelasligeras.net/index.php/2018/05/15/a-monster-who-levels-up-capitulo-2-novela-ligera/
	return pageOfElem(chapter, true, customCSS)
end

local function search(data)
    local url = createSearchString(data)
	local page = data[PAGE]
    return parseListing(url, page)
end

local function getListing(name, inc, listingURL)
	local url = expandURL(listingURL)
	return Listing(name, inc, function(data)
		local page = data[PAGE]
		return parseListing(inc and (url .. "/page/" .. data[PAGE] .. "/?" .. createFilterString(data)) or url, page)
	end)
end

return {
	id = 28505740,
	name = "NOVA",
	baseURL = baseURL,
	imageURL = "https://shosetsuorg.gitlab.io/extensions/icons/NOVA.png",
	hasCloudFlare = true,
	hasSearch = true,
	chapterType = ChapterType.HTML,
	startIndex = 1,

	listings = {
		getListing("Todas las Novelas", true, "index.php/lista-de-novela-ligera-novela-web"),
		getListing("Novelas Exclusivas", true, "index.php/etiqueta-novela/novela-exclusiva"),
		getListing("Novelas Completadas", true, "index.php/filtro/estado/completado"),
		getListing("Novelas En Proceso", true, "index.php/filtro/estado/en-proceso")
	},

	shrinkURL = shrinkURL,
	expandURL = expandURL,

	parseNovel = parseNovel,
	getPassage = getPassage,

	searchFilters = {
		DropdownFilter(ORDER_BY_FILTER_KEY, "Pedido de la tienda", ORDER_BY_FILTER_EXT),
		SwitchFilter(ORDER_FILTER_KEY, "Ascendiendo / Descendiendo"),
		FilterGroup("Géneros", {
			CheckboxFilter(CATEGORIAS_FILTER_INT[01], "Acción"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[02], "Adulto"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[03], "Artes Marciales"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[04], "Aventura"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[05], "Ciencia Ficción"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[06], "Comedia"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[07], "Drama"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[08], "Ecchi"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[09], "Fantasía"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[10], "Harem"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[11], "Histórico"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[12], "Horror"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[13], "Mechas (Robots Gigantes)"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[14], "Misterio"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[15], "Psicológico"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[16], "Recuentos de la Vida"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[17], "Romance"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[18], "Seinen"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[19], "Shonen"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[20], "Sobrenatural"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[21], "Tragedia"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[22], "Vida Escolar"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[23], "Xianxia"),
			CheckboxFilter(CATEGORIAS_FILTER_INT[24], "Xuanhuan"),
		}),
		DropdownFilter(searchHasOperId, "Condición de géneros", {"O (cualquiera de los seleccionados)", "Y (todos los seleccionados)"}),
		DropdownFilter(TIPO_FILTER_KEY, "Tipo", {"Cualquiera","Novela Ligera","Novela Web"}),
		FilterGroup("Estado", {
			CheckboxFilter(ESTADO_FILTER_INT[1], "▶️ En Proceso"),
			CheckboxFilter(ESTADO_FILTER_INT[2], "⏸️ Pausado"),
			CheckboxFilter(ESTADO_FILTER_INT[3], "⏹️ Completado"),
		}),
		FilterGroup("País", {
			CheckboxFilter(PAIS_FILTER_INT[01], "🇨🇳 China"),
			CheckboxFilter(PAIS_FILTER_INT[02], "🇰🇷 Corea"),
			CheckboxFilter(PAIS_FILTER_INT[03], "🇯🇵 Japón"),
		}),
	},

	isSearchIncrementing = true,
	search = search,

	settings = {
		SwitchFilter(ADBLOCK_SETTING_KEY, "Mostrar publicidades"),
		SwitchFilter(SUBSCRIBEBLOCK_SETTING_KEY, "Mostrar imagen de suscripción"),
	},
	setSettings = function(s)
		settings = s
	end,
	updateSetting = function(id, value)
		settings[id] = value
	end,
}
