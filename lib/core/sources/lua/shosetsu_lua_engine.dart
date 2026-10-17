import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:lua_dardo_plus/lua.dart';

import '../../models/novel_source.dart';

class SourceNetworkException implements Exception {
  final String message;
  final String? url;
  final int? statusCode;

  const SourceNetworkException(this.message, {this.url, this.statusCode});

  @override
  String toString() => 'SourceNetworkException: $message${url != null ? ' ($url)' : ''}';
}

class SourceParseException implements Exception {
  final String message;
  const SourceParseException(this.message);

  @override
  String toString() => 'SourceParseException: $message';
}

/// Shosetsu-compatible Lua extension execution engine.
/// Executes upstream Shosetsu Lua extensions (e.g. Project Gutenberg, NovelFull)
/// by binding the Shosetsu runtime environment and DOM parsing layer.
class ShosetsuLuaEngine {
  static ShosetsuLuaEngine? _instance;
  static ShosetsuLuaEngine get instance => _instance ??= ShosetsuLuaEngine();

  http.Client? _httpClient;

  @visibleForTesting
  void setHttpClientForTesting(http.Client client) {
    _httpClient = client;
  }

  http.Client get _client => _httpClient ??= http.Client();

  /// Executes an upstream Shosetsu Lua extension search query
  Future<List<SourceNovelSummary>> search(
    String luaScript,
    String query, {
    int page = 0,
  }) async {
    final cache = <String, String>{};

    return _executeWithNetworkRetry<List<SourceNovelSummary>>(
      luaScript,
      cache,
      (ls) {
        ls.loadString('''
          local data = { [_G.QUERY] = "$query", [_G.PAGE] = $page }
          return Extension.search(data)
        ''');
        ls.call(0, 1);

        final novels = <SourceNovelSummary>[];
        if (!ls.isTable(-1)) return novels;

        final len = ls.rawLen(-1);
        for (int i = 1; i <= len; i++) {
          ls.rawGetI(-1, i);
          if (ls.isTable(-1)) {
            ls.getField(-1, 'title');
            final title = ls.toStr(-1) ?? '';
            ls.pop(1);

            ls.getField(-1, 'link');
            final link = ls.toStr(-1) ?? '';
            ls.pop(1);

            ls.getField(-1, 'imageURL');
            final imageURL = ls.toStr(-1);
            ls.pop(1);

            if (title.isNotEmpty) {
              novels.add(SourceNovelSummary(
                id: link.isNotEmpty ? link : 'novel_$i',
                title: title,
                coverUrl: imageURL?.isNotEmpty == true ? imageURL : null,
              ));
            }
          }
          ls.pop(1); // pop novel table
        }
        return novels;
      },
    );
  }

  /// Parses novel metadata and chapter list via the upstream extension's `parseNovel` method
  Future<NovelDetails> parseNovel(
    String luaScript,
    String novelUrl, {
    bool loadChapters = true,
  }) async {
    final cache = <String, String>{};

    return _executeWithNetworkRetry<NovelDetails>(
      luaScript,
      cache,
      (ls) {
        ls.loadString('''
          return Extension.parseNovel("$novelUrl", $loadChapters)
        ''');
        ls.call(0, 1);

        if (!ls.isTable(-1)) {
          throw const SourceParseException('Extension parseNovel returned non-table value');
        }

        ls.getField(-1, 'title');
        final title = ls.toStr(-1) ?? 'Unknown Title';
        ls.pop(1);

        ls.getField(-1, 'description');
        final description = ls.toStr(-1) ?? '';
        ls.pop(1);

        ls.getField(-1, 'imageURL');
        final imageURL = ls.toStr(-1);
        ls.pop(1);

        final authors = <String>[];
        ls.getField(-1, 'authors');
        if (ls.isTable(-1)) {
          final nAuthors = ls.rawLen(-1);
          for (int i = 1; i <= nAuthors; i++) {
            ls.rawGetI(-1, i);
            final a = ls.toStr(-1);
            if (a != null && a.isNotEmpty) authors.add(a);
            ls.pop(1);
          }
        }
        ls.pop(1); // pop authors

        final genres = <String>[];
        ls.getField(-1, 'genres');
        if (ls.isTable(-1)) {
          final nGenres = ls.rawLen(-1);
          for (int i = 1; i <= nGenres; i++) {
            ls.rawGetI(-1, i);
            final g = ls.toStr(-1);
            if (g != null && g.isNotEmpty) genres.add(g);
            ls.pop(1);
          }
        }
        ls.pop(1); // pop genres

        final chapters = <SourceChapter>[];
        ls.getField(-1, 'chapters');
        if (ls.isTable(-1)) {
          final nCh = ls.rawLen(-1);
          for (int i = 1; i <= nCh; i++) {
            ls.rawGetI(-1, i);
            if (ls.isTable(-1)) {
              ls.getField(-1, 'title');
              final chTitle = ls.toStr(-1) ?? 'Chapter $i';
              ls.pop(1);

              ls.getField(-1, 'link');
              final chLink = ls.toStr(-1) ?? '';
              ls.pop(1);

              ls.getField(-1, 'release');
              final chRelease = ls.toStr(-1);
              ls.pop(1);

              DateTime? releaseDate;
              if (chRelease != null && chRelease.isNotEmpty) {
                try {
                  releaseDate = DateTime.tryParse(chRelease);
                } catch (_) {}
              }

              chapters.add(SourceChapter(
                id: chLink.isNotEmpty ? chLink : 'ch_$i',
                title: chTitle,
                index: i.toDouble(),
                releaseDate: releaseDate,
                url: chLink,
              ));
            }
            ls.pop(1); // pop chapter table
          }
        }
        ls.pop(1); // pop chapters

        return NovelDetails(
          id: novelUrl,
          title: title,
          author: authors.isNotEmpty ? authors.join(', ') : 'Unknown Author',
          description: description,
          coverUrl: imageURL?.isNotEmpty == true ? imageURL : null,
          genres: genres,
          chapters: chapters,
        );
      },
    );
  }

  /// Fetches readable HTML passage via the upstream extension's `getPassage` method
  Future<String> getPassage(
    String luaScript,
    String chapterUrl,
  ) async {
    final cache = <String, String>{};

    return _executeWithNetworkRetry<String>(
      luaScript,
      cache,
      (ls) {
        ls.loadString('''
          return Extension.getPassage("$chapterUrl")
        ''');
        ls.call(0, 1);

        final passage = ls.toStr(-1);
        if (passage == null || passage.isEmpty) {
          throw const SourceParseException('Extension returned empty chapter passage');
        }
        return passage;
      },
    );
  }

  /// Internal execution loop: Handles live network requests required by Lua scripts
  /// by caching responses and re-running pure script functions until complete.
  Future<T> _executeWithNetworkRetry<T>(
    String luaScript,
    Map<String, String> cache,
    T Function(LuaState ls) runner,
  ) async {
    const maxRetries = 10;
    int retries = 0;

    while (retries < maxRetries) {
      retries++;
      final ls = LuaState.newState();
      ls.openLibs();

      _bindShosetsuEnvironment(ls, cache);

      // Load upstream extension script
      ls.loadString(luaScript);
      ls.call(0, 1);
      ls.setGlobal('Extension');

      try {
        final result = runner(ls);
        return result;
      } catch (e) {
        final msg = e.toString();
        const prefix = 'NEED_FETCH:';
        final idx = msg.indexOf(prefix);
        if (idx >= 0) {
          final url = msg.substring(idx + prefix.length).trim().split('\n').first;

          try {
            final uri = Uri.parse(url);
            final response = await _client.get(
              uri,
              headers: {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile; Hon/1.0)',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              },
            ).timeout(const Duration(seconds: 25));

            if (response.statusCode >= 400) {
              throw SourceNetworkException(
                'HTTP server error ${response.statusCode}',
                url: url,
                statusCode: response.statusCode,
              );
            }
            cache[url] = response.body;
            continue; // Retry with populated cache
          } on SocketException catch (se) {
            throw SourceNetworkException(
              'Network connection error: ${se.message}',
              url: url,
            );
          } on TimeoutException {
            throw SourceNetworkException(
              'Request timed out while connecting to source',
              url: url,
            );
          } on http.ClientException catch (ce) {
            throw SourceNetworkException(
              'HTTP client failure: ${ce.message}',
              url: url,
            );
          }
        }
        rethrow;
      }
    }

    throw const SourceNetworkException('Exceeded maximum network fetch redirects');
  }

  /// Binds the Shosetsu runtime, DOM parser, and utility functions to the Lua state
  void _bindShosetsuEnvironment(LuaState ls, Map<String, String> networkCache) {
    int nextId = 1;
    final docs = <int, dom.Document>{};
    final elements = <int, dom.Element>{};

    ls.register('__create_doc', (state) {
      final htmlStr = state.toStr(1) ?? '';
      final doc = html_parser.parse(htmlStr);
      final id = nextId++;
      docs[id] = doc;
      state.pushInteger(id);
      return 1;
    });

    ls.register('__doc_html', (state) {
      final docId = state.toInteger(1);
      final doc = docs[docId];
      final body = doc?.body?.innerHtml ?? doc?.outerHtml ?? '';
      state.pushString(body);
      return 1;
    });

    ls.register('__doc_select', (state) {
      final docId = state.toInteger(1);
      final sel = state.toStr(2) ?? '';
      final doc = docs[docId];
      state.newTable();
      if (doc != null) {
        final results = doc.querySelectorAll(sel);
        for (int i = 0; i < results.length; i++) {
          final elId = nextId++;
          elements[elId] = results[i];
          state.pushInteger(elId);
          state.rawSetI(-2, i + 1);
        }
      }
      return 1;
    });

    ls.register('__doc_select_first', (state) {
      final docId = state.toInteger(1);
      final sel = state.toStr(2) ?? '';
      final doc = docs[docId];
      final el = doc?.querySelector(sel);
      if (el == null) {
        state.pushNil();
        return 1;
      }
      final elId = nextId++;
      elements[elId] = el;
      state.pushInteger(elId);
      return 1;
    });

    ls.register('__elem_select', (state) {
      final elId = state.toInteger(1);
      final sel = state.toStr(2) ?? '';
      final el = elements[elId];
      state.newTable();
      if (el != null) {
        final results = el.querySelectorAll(sel);
        for (int i = 0; i < results.length; i++) {
          final childId = nextId++;
          elements[childId] = results[i];
          state.pushInteger(childId);
          state.rawSetI(-2, i + 1);
        }
      }
      return 1;
    });

    ls.register('__elem_select_first', (state) {
      final elId = state.toInteger(1);
      final sel = state.toStr(2) ?? '';
      final el = elements[elId];
      final child = el?.querySelector(sel);
      if (child == null) {
        state.pushNil();
        return 1;
      }
      final childId = nextId++;
      elements[childId] = child;
      state.pushInteger(childId);
      return 1;
    });

    ls.register('__elem_text', (state) {
      final elId = state.toInteger(1);
      final el = elements[elId];
      state.pushString(el?.text.trim() ?? '');
      return 1;
    });

    ls.register('__elem_own_text', (state) {
      final elId = state.toInteger(1);
      final el = elements[elId];
      if (el == null) {
        state.pushString('');
        return 1;
      }
      final own = el.nodes
          .where((n) => n.nodeType == dom.Node.TEXT_NODE)
          .map((n) => n.text?.trim() ?? '')
          .join(' ');
      state.pushString(own.trim());
      return 1;
    });

    ls.register('__elem_attr', (state) {
      final elId = state.toInteger(1);
      final attrName = state.toStr(2) ?? '';
      final el = elements[elId];
      final val = el?.attributes[attrName];
      state.pushString(val ?? '');
      return 1;
    });

    ls.register('__elem_set_attr', (state) {
      final elId = state.toInteger(1);
      final attrName = state.toStr(2) ?? '';
      final attrVal = state.toStr(3) ?? '';
      final el = elements[elId];
      if (el != null) {
        el.attributes[attrName] = attrVal;
      }
      return 0;
    });

    ls.register('__fetch_get', (state) {
      final url = state.toStr(1) ?? '';
      if (!networkCache.containsKey(url)) {
        return state.error2('NEED_FETCH:$url');
      }
      state.pushString(networkCache[url]!);
      return 1;
    });

    // Lua runtime support scripts
    ls.loadString(r'''
      _G.QUERY = 0
      _G.PAGE = 1

      NovelStatus = { UNKNOWN = 0, PUBLISHING = 1, COMPLETED = 2, PAUSED = 3, DROPPED = 4 }
      ChapterType = { HTML = 1, TEXT = 2 }

      function createElement(id)
        if id == nil then return nil end
        local el = { _id = id, _type = "Element" }
        function el:select(sel)
          local ids = __elem_select(self._id, sel)
          return createElements(ids)
        end
        function el:selectFirst(sel)
          local childId = __elem_select_first(self._id, sel)
          if childId == nil then return nil end
          return createElement(childId)
        end
        function el:text() return __elem_text(self._id) end
        function el:ownText() return __elem_own_text(self._id) end
        function el:attr(name, val)
          if val ~= nil then
            __elem_set_attr(self._id, name, val)
            return self
          else
            return __elem_attr(self._id, name)
          end
        end
        function el:prependElement(tag)
          return self
        end
        return el
      end

      function createElements(ids)
        local list = {}
        for i, id in ipairs(ids) do
          list[i] = createElement(id)
        end
        function list:size() return #self end
        function list:get(idx) return self[idx + 1] end
        function list:attr(name)
          if #self > 0 then return self[1]:attr(name) else return "" end
        end
        function list:text()
          local s = ""
          for _, it in ipairs(self) do s = s .. it:text() .. " " end
          return s:gsub("%s+$", "")
        end
        return list
      end

      function Document(html)
        local docId = __create_doc(html)
        local doc = { _id = docId, _type = "Document" }
        function doc:select(sel)
          local ids = __doc_select(self._id, sel)
          return createElements(ids)
        end
        function doc:selectFirst(sel)
          local childId = __doc_select_first(self._id, sel)
          if childId == nil then return nil end
          return createElement(childId)
        end
        function doc:text() return __doc_text(self._id) end
        function doc:head()
          local h = self:selectFirst("head")
          if h == nil then h = createElement(self._id) end
          return h
        end
        return doc
      end

      function GETDocument(url)
        local html = __fetch_get(url)
        return Document(html)
      end

      function map(list, fn)
        local res = {}
        if list.size ~= nil then
          for i = 0, list:size() - 1 do
            local item = list:get(i)
            local val = fn(item, i)
            if val ~= nil then table.insert(res, val) end
          end
        else
          for i, v in ipairs(list) do
            local val = fn(v, i)
            if val ~= nil then table.insert(res, val) end
          end
        end
        return res
      end

      function AsList(tbl) return tbl end
      function List() return {} end

      function Novel(tbl)
        tbl = tbl or {}
        return tbl
      end

      function NovelInfo(tbl)
        tbl = tbl or {}
        function tbl:setChapters(ch) self.chapters = ch end
        return tbl
      end

      function NovelChapter(tbl)
        tbl = tbl or {}
        return tbl
      end

      function Listing(name, inc, fn)
        return { name = name, increments = inc, fn = fn }
      end

      function DropdownFilter(id, name, options) return { id = id, name = name } end
      function SwitchFilter(id, name) return { id = id, name = name } end

      function Require(name)
        if name == "FilterOptions" then
          return function(opts, default)
            local fo = { _opts = opts, _default = default }
            function fo:valueOfOrFirst(val) return default end
            function fo:labels() return {} end
            return fo
          end
        elseif name == "url" then
          return {
            querystring = function(params, base)
              local qs = ""
              for k, v in pairs(params) do
                if qs == "" then qs = "?" else qs = qs .. "&" end
                qs = qs .. tostring(k) .. "=" .. tostring(v)
              end
              return (base or "") .. qs
            end
          }
        end
        return {}
      end

      function pageOfElem(doc, removeStyles)
        return __doc_html(doc._id)
      end
    ''');
    ls.call(0, 0);
  }
}
