package com.hon.reader.hon

import com.hon.reader.hon.shosetsu.ShosetsuKotlinEngine
import com.hon.reader.hon.shosetsu.SourceHttpClient
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class SourceControlsTest {
    private val script = """
        local settings={}
        return {
          baseURL='https://source.test',
          settings={TextFilter(2,'Account name'),DropdownFilter(3,'Language',{'English','Japanese'}),SwitchFilter(4,'Feature')},
          setSettings=function(values) settings=values end,
          searchFilters={FilterGroup('Genre',{TextFilter(10,'Tag'),TriStateFilter(11,'Fantasy')})},
          search=function(data) return {{title=settings[2]..'/'..settings[3]..'/'..data[10]..'/'..data[11],link='novel'}} end,
          parseNovel=function() return {title=settings[2],chapters={}} end,
          getPassage=function() return '<p>'..settings[2]..'</p>' end
        }
    """.trimIndent()
    @Test fun exposesTypedControlsAndAppliesSettingsAndSearchFilters() = runBlocking {
        val engine=ShosetsuKotlinEngine()
        val info=engine.describeExtension(script)
        assertEquals("https://source.test",info["baseUrl"])
        assertEquals(3,(info["settings"] as List<*>).size)
        val filter=(info["filters"] as List<*>).first() as Map<*,*>
        assertEquals("Genre",filter["group"])
        val settings=mapOf("2" to "Alice","3" to 1,"4" to true)
        assertEquals("Alice/1/forest/2",engine.search(script,"story",0,null,settings,mapOf("10" to "forest","11" to 2)).single()["title"])
        assertEquals("<p>Alice</p>",engine.getPassage(script,"chapter",settings))
    }
    @Test fun rejectsInvalidControlTypesAndOptionIndices() = runBlocking {
        val engine=ShosetsuKotlinEngine()
        for (settings in listOf(mapOf("3" to 99),mapOf("4" to "true"))) {
            try { engine.search(script,"story",0,null,settings); fail("Invalid control was accepted") }
            catch (_:IllegalArgumentException) {}
        }
    }
    @Test fun sessionCookiesAreRestrictedToTheChosenSecureWebsite() {
        assertTrue(SourceHttpClient.allowsCookies("https://www.source.test", "https://source.test/novel".toHttpUrl()))
        assertTrue(SourceHttpClient.allowsCookies("https://source.test", "https://api.source.test/novel".toHttpUrl()))
        assertFalse(SourceHttpClient.allowsCookies("http://source.test", "https://source.test/".toHttpUrl()))
        assertFalse(SourceHttpClient.allowsCookies("https://co.uk", "https://another.co.uk/".toHttpUrl()))
        for(url in listOf("https://source.test.evil.test/","https://other-source.test/","http://source.test/")) {
            assertFalse(SourceHttpClient.allowsCookies("https://source.test",url.toHttpUrl()))
        }
    }
}
