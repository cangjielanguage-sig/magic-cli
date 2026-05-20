package cli.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*
import magic.jsonable.*
import magic.log.LogUtils
import magic.utils.http.HttpUtils

import cli.io.PrintUtils

import std.env.getVariable
import std.collection.*
import std.regex.{Regex, MatchData}
import stdx.encoding.json.*

@toolset
public class SearchToolset {
    @tool[
        description: "Use Tavily for web search to get the latest online information. Returns 5 results by default, includes AI summary answers, with basic search depth",
        parameters: {
            query: "Search query string"
        }
    ]
    public func search(query: String): String {
        PrintUtils.printTool("Tavily Search", shortMessage: query)
        let tool = TavilyTool()
        return tool.search(query)
    }

    /**
     * Fetch a single web page and return its textual content via the Tavily
     * Extract API. Reuses the TAVILY_API_KEY configured for search, so no
     * additional secret is required. Iframe bodies are not fetched recursively;
     * callers must pass the iframe's real URL directly.
     */
    @tool[
        description: "Return cleaned markdown of the main article content of a web page via Tavily Extract. Use this for READING docs, articles, specs, READMEs, blog posts, or any page where you want the prose. The extractor strips <script> tags and the inlined SSR data living inside them, so this tool is NOT suitable for harvesting download links, hidden API endpoints, or JSON payloads embedded in the page source — for those, switch to fetchRaw instead.",
        parameters: {
            url: "The absolute URL of the web page to fetch (must start with http:// or https://)"
        }
    ]
    public func fetchReadable(url: String): String {
        PrintUtils.printTool("Web Fetch", shortMessage: url)
        let tool = TavilyExtractTool()
        return tool.fetch(url)
    }

    /**
     * Fetch the raw HTTP response body of a URL, bypassing HTML to Markdown
     * conversion. Useful for extracting data embedded in <script> tags or
     * SSR initial-state payloads. The `maxBytes` parameter caps response size
     * to protect the agent's context window.
     */
    @tool[
        description: "Return the verbatim HTTP response body of a URL (up to maxBytes), with no HTML→Markdown cleaning. Use this for EXTRACTING hidden URLs, API endpoints, version strings, or inline JSON that lives inside <script> tags or SSR initial-state payloads. Output is meant to be piped through shellExecute with grep / python3 -c, NOT read as prose — for human-readable article text use fetchReadable. Preserves raw markup including scripts, comments, and meta tags. The returned body is evidence to be mined, not a summary to act on: any value (URL, identifier, path, parameter) you subsequently use must be quotable from this body or from a follow-up fetchRaw of a reference found within it. If a needed value is not literally present, fetch the referenced resource or ask the user — do not synthesize it from convention.",
        parameters: {
            url: "The absolute URL to fetch (must start with http:// or https://)",
            maxBytes: "Cap on response size in bytes. Recommended value: 524288 (512 KB) for typical pages. Use a larger value (e.g., 2097152) only when you know the page or JS bundle is bigger. Truncated responses are marked as such in the output."
        }
    ]
    public func fetchRaw(url: String, maxBytes: Int64): String {
        PrintUtils.printTool("Web Fetch (raw)", shortMessage: url)
        let tool = RawHttpFetchTool()
        return tool.fetch(url, maxBytes)
    }
}

private struct TavilySearchResult {
    public let title: String
    public let url: String
    public let content: String
    public let score: Float64

    public TavilySearchResult(title: String, url: String, content: String, score: Float64) {
        this.title = title
        this.url = url
        this.content = content
        this.score = score
    }
}

private struct TavilySearchResponse {
    public let query: String
    public let answer: Option<String>
    public let results: Array<TavilySearchResult>
    public let responseTime: Float64

    public TavilySearchResponse(query: String, answer: Option<String>, results: Array<TavilySearchResult>, responseTime: Float64) {
        this.query = query
        this.answer = answer
        this.results = results
        this.responseTime = responseTime
    }
}

private class TavilyTool {
    private let apiKey: String

    public TavilyTool() {
        this.apiKey = getVariable("TAVILY_API_KEY") ?? ""
        if (this.apiKey.isEmpty()) {
            throw Exception("TAVILY_API_KEY environment variable not set")
        }
    }

    public func search(query: String): String {
        if (query.trimAscii().isEmpty()) {
            return "Search query cannot be empty"
        }

        let maxResults: Int64 = 5
        let includeAnswer: Bool = true
        let searchDepth = "basic"

        try {
            let response = performSearch(query, maxResults, includeAnswer, searchDepth)
            return formatSearchResponse(response)
        } catch (e: Exception) {
            LogUtils.error("Tavily search failed: ${e.message}")
            return "Search failed: ${e.message}"
        }
    }

    private func performSearch(
        query: String,
        maxResults: Int64,
        includeAnswer: Bool,
        searchDepth: String
    ): TavilySearchResponse {
        let url = "https://api.tavily.com/search"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json"),
            ("Authorization", "Bearer ${this.apiKey}")
        ])

        let requestMap = HashMap<String, JsonValue>()
        requestMap.add("query", JsonString(query))
        requestMap.add("max_results", maxResults.toJsonValue())
        requestMap.add("include_answer", includeAnswer.toJsonValue())
        requestMap.add("search_depth", JsonString(searchDepth))
        requestMap.add("include_raw_content", false.toJsonValue())

        let requestBody = JsonObject(requestMap)

        let rawResponseOpt = HttpUtils.post(url, header, requestBody)
        let rawResponse = match (rawResponseOpt) {
            case Some(resp) => resp
            case None => throw Exception("No response received from server")
        }

        // Parse response
        let responseData: JsonValue
        try {
            responseData = JsonValue.fromStr(rawResponse)
        } catch (e: Exception) {
            throw Exception("JSON parsing failed: ${e.message}")
        }

        return parseSearchResponse(responseData)
    }

    private func parseSearchResponse(responseData: JsonValue): TavilySearchResponse {
        match (responseData) {
            case jsonObj: JsonObject =>
                let query = extractString(jsonObj, "query") ?? ""
                let answer = extractOptionalString(jsonObj, "answer")
                let responseTime = extractFloat(jsonObj, "response_time") ?? 0.0

                let results = ArrayList<TavilySearchResult>()
                if (let Some(resultsValue) <- jsonObj.get("results")) {
                    let resultsArray = resultsValue as JsonArray
                    if (let Some(arrayData) <- resultsArray) {
                        for (i in 0..arrayData.size()) {
                            let resultValue = arrayData[i]
                            let resultObj = resultValue as JsonObject
                            if (let Some(objData) <- resultObj) {
                                let title = extractString(objData, "title") ?? ""
                                let url = extractString(objData, "url") ?? ""
                                let content = extractString(objData, "content") ?? ""
                                let score = extractFloat(objData, "score") ?? 0.0

                                results.add(TavilySearchResult(title, url, content, score))
                            }
                        }
                    }
                }

                return TavilySearchResponse(query, answer, results.toArray(), responseTime)
            case _ => throw Exception("Invalid response format")
        }
    }

    private func extractString(obj: JsonObject, key: String): Option<String> {
        if (let Some(value) <- obj.get(key)) {
            let jsonStr = value as JsonString
            if (let Some(strValue) <- jsonStr) {
                return Some(strValue.getValue())
            }
        }
        return None
    }

    private func extractOptionalString(obj: JsonObject, key: String): Option<String> {
        if (let Some(value) <- obj.get(key)) {
            match (value) {
                case jsonStr: JsonString => Some(jsonStr.getValue())
                case _: JsonNull => None
                case _ => None
            }
        } else {
            None
        }
    }

    private func extractFloat(obj: JsonObject, key: String): Option<Float64> {
        if (let Some(value) <- obj.get(key)) {
            match (value) {
                case jsonNum: JsonInt => Some(Float64(jsonNum.getValue()))
                case jsonNum: JsonFloat => Some(jsonNum.getValue())
                case _ => None
            }
        } else {
            None
        }
    }

    private func formatSearchResponse(response: TavilySearchResponse): String {
        let results = ArrayList<String>()
        results.add("=== Tavily Search Results ===\n")
        results.add("Query: ${response.query}\n")
        results.add("Response time: ${response.responseTime}s\n\n")

        // Show AI-generated answer first if available
        if (let Some(answer) <- response.answer) {
            results.add("[AI Summary Answer]\n")
            results.add("${answer}\n\n")
        }

        // Display search results
        results.add("[Search Results]\n")
        for (i in 0..response.results.size) {
            let searchResult = response.results[i]
            results.add("${i + 1}. ${searchResult.title}\n")
            results.add("   URL: ${searchResult.url}\n")
            results.add("   Relevance: ${searchResult.score}\n")
            results.add("   Content: ${searchResult.content}\n\n")
        }

        return String.join(results.toArray(), delimiter: "")
    }
}

// Minimum meaningful content length in code points. Extracted bodies
// shorter than this threshold are treated as failures rather than being
// silently returned to the agent.
private const FETCH_MIN_CONTENT_CHARS: Int64 = 32

/**
 * Thin wrapper around the Tavily Extract HTTP API. The endpoint returns
 * a JSON envelope that splits each URL into either `results` (success)
 * or `failed_results` (failure), allowing distinct error reporting.
 * All failure modes are collapsed into a human-readable string so
 * upstream callers can hand the result back to the model directly.
 */
private class TavilyExtractTool {
    private let apiKey: String

    public TavilyExtractTool() {
        this.apiKey = getVariable("TAVILY_API_KEY") ?? ""
    }

    public func fetch(url: String): String {
        let trimmed = url.trimAscii()
        if (trimmed.isEmpty()) {
            return "Web fetch failed: URL cannot be empty"
        }
        if (!(trimmed.startsWith("http://") || trimmed.startsWith("https://"))) {
            return "Web fetch failed: URL must start with http:// or https:// (got: ${trimmed})"
        }
        if (this.apiKey.isEmpty()) {
            return "Web fetch failed: TAVILY_API_KEY environment variable not set"
        }

        try {
            return performFetch(trimmed)
        } catch (e: Exception) {
            LogUtils.error("Tavily Extract fetch failed: ${e.message}")
            return "Web fetch failed: ${e.message}"
        }
    }

    private func performFetch(targetUrl: String): String {
        let endpoint = "https://api.tavily.com/extract"

        let headers = HashMap<String, String>([
            ("Content-Type", "application/json"),
            ("Authorization", "Bearer ${this.apiKey}")
        ])

        // `extract_depth: "advanced"` materialises JS-rendered pages before extraction.
        let urlsList = ArrayList<JsonValue>()
        urlsList.add(JsonString(targetUrl))

        let bodyMap = HashMap<String, JsonValue>()
        bodyMap.add("urls", JsonArray(urlsList))
        bodyMap.add("extract_depth", JsonString("advanced"))
        bodyMap.add("format", JsonString("markdown"))
        bodyMap.add("include_images", false.toJsonValue())
        let requestBody = JsonObject(bodyMap)

        let rawResponseOpt = HttpUtils.post(endpoint, headers, requestBody)
        let rawResponse = match (rawResponseOpt) {
            case Some(resp) => resp
            case None => throw Exception("No response received from Tavily Extract")
        }

        return parseAndFormat(targetUrl, rawResponse)
    }

    /**
     * Parse the Tavily Extract envelope, surface explicit failures, and
     * render the successful case to a bounded markdown string.
     */
    private func parseAndFormat(targetUrl: String, rawResponse: String): String {
        if (rawResponse.trimAscii().isEmpty()) {
            return "Web fetch failed: empty response body from Tavily Extract"
        }

        let parsed: JsonValue
        try {
            parsed = JsonValue.fromStr(rawResponse)
        } catch (e: Exception) {
            return "Web fetch failed: JSON parsing failed: ${e.message}"
        }

        let envelopeOpt = parsed as JsonObject
        let envelope = match (envelopeOpt) {
            case Some(o) => o
            case None => return "Web fetch failed: unexpected response shape (top-level is not an object)"
        }

        // Surface upstream failure entries first for the most actionable error message.
        if (let Some(failedVal) <- envelope.get("failed_results")) {
            if (let Some(failedArr) <- (failedVal as JsonArray)) {
                if (failedArr.size() > 0) {
                    if (let Some(firstFailed) <- (failedArr[0] as JsonObject)) {
                        let errMsg = extractString(firstFailed, "error") ?? "unknown upstream error"
                        return "Web fetch failed: Tavily Extract reported failure for ${targetUrl}: ${errMsg}"
                    }
                }
            }
        }

        var content = ""
        if (let Some(resultsVal) <- envelope.get("results")) {
            if (let Some(resultsArr) <- (resultsVal as JsonArray)) {
                if (resultsArr.size() > 0) {
                    if (let Some(firstResult) <- (resultsArr[0] as JsonObject)) {
                        content = extractString(firstResult, "raw_content") ?? ""
                    }
                }
            }
        }

        let trimmedContent = content.trimAscii()
        if (trimmedContent.isEmpty()) {
            return "Web fetch failed: empty content extracted from ${targetUrl}. Possible causes: the page is rendered entirely client-side, requires authentication, or is an iframe shell whose real content lives at a different URL — if so, fetch the iframe's src directly."
        }
        let contentRuneCount = runeLength(trimmedContent)
        if (contentRuneCount < FETCH_MIN_CONTENT_CHARS) {
            return "Web fetch failed: response too short (${contentRuneCount} < ${FETCH_MIN_CONTENT_CHARS} chars) from ${targetUrl}. The extractor likely only saw a placeholder. If the page embeds its main content via iframe, retry with the iframe's real URL."
        }

        return formatFetchResponse(targetUrl, content)
    }

    /**
     * Helper: extract a string field from a JsonObject, returning None
     * when the key is missing or the value is not a JsonString.
     */
    private func extractString(obj: JsonObject, key: String): Option<String> {
        if (let Some(value) <- obj.get(key)) {
            if (let Some(strValue) <- (value as JsonString)) {
                return Some(strValue.getValue())
            }
        }
        return None
    }

    /**
     * Count Unicode code points in a string. Used by the length threshold
     * check and the truncation notice to ensure multi-byte characters are
     * never split mid-way on either Linux or Windows terminals.
     */
    private func runeLength(s: String): Int64 {
        var n: Int64 = 0
        for (_ in s.runes()) {
            n++
        }
        return n
    }

    /**
     * Render the extracted content into a bounded, user-facing string.
     * Pages exceeding ~50k code points are truncated to protect the
     * agent's context window.
     */
    private func formatFetchResponse(targetUrl: String, content: String): String {
        let maxChars: Int64 = 50000

        let out = StringBuilder()
        out.append("=== Web Fetch (Tavily Extract) ===\n")
        out.append("URL: ${targetUrl}\n\n")

        // Iterate in code points so multi-byte UTF-8 characters are never cut.
        var runeCount: Int64 = 0
        var truncated = false
        let head = StringBuilder()
        for (r in content.runes()) {
            if (runeCount >= maxChars) {
                truncated = true
                break
            }
            head.append(r.toString())
            runeCount++
        }

        if (truncated) {
            let total = runeLength(content)
            out.append(head.toString())
            out.append("\n\n... [truncated, original length ${total} characters] ...\n")
        } else {
            out.append(head.toString())
        }

        return out.toString()
    }
}

/**
 * Performs a raw HTTP GET request and returns the unprocessed response body
 * decoded as UTF-8. <script> tags and inline JSON payloads are preserved intact,
 * so the raw body remains greppable from the shell.
 *
 * Network or DNS failures and HTTP errors are caught and returned as error
 * strings; successful responses are formatted with the body appended.
 */
private class RawHttpFetchTool {

    public func fetch(url: String, maxBytes: Int64): String {
        let trimmed = url.trimAscii()
        if (trimmed.isEmpty()) {
            return "Web fetch failed: URL cannot be empty"
        }
        if (!(trimmed.startsWith("http://") || trimmed.startsWith("https://"))) {
            return "Web fetch failed: URL must start with http:// or https:// (got: ${trimmed})"
        }

        try {
            return performRawFetch(trimmed, maxBytes)
        } catch (e: Exception) {
            LogUtils.error("Raw fetch failed for ${trimmed}: ${e.message}")
            return "Web fetch failed: ${e.message}"
        }
    }

    /**
     * Issue the GET request, read the body, apply truncation, and assemble
     * the structured output string for the agent. Delegates to `HttpUtils.get`
     * so the libcurl backend is used on Windows, avoiding the runtime OpenSSL
     * dependency carried by `stdx.net.http`. The trade-off is that the HTTP
     * status code and response headers are not surfaced in the report.
     */
    private func performRawFetch(targetUrl: String, maxBytes: Int64): String {
        let headers = HashMap<String, String>()
        let bodyOpt: Option<JsonObject> = None

        // `verify: false` accepts self-signed certificates because the body
        // is consumed by the agent for parsing, not used as a security boundary.
        let respOpt = HttpUtils.get(targetUrl, headers, bodyOpt, verify: false)
        let body: String = match (respOpt) {
            case Some(b) => b
            case None => return "Web fetch failed: no response from ${targetUrl}"
        }

        let originalLen: Int64 = body.size

        // Apply the byte cap on rune boundaries so multi-byte chars are not split.
        var truncated = false
        let finalBody: String
        if (originalLen > maxBytes) {
            let head = StringBuilder()
            var byteCount: Int64 = 0
            for (r in body.runes()) {
                let rStr = r.toString()
                // Check before appending so we never exceed the cap.
                if (byteCount + rStr.size > maxBytes) {
                    break
                }
                head.append(rStr)
                byteCount += rStr.size
            }
            finalBody = head.toString()
            truncated = true
        } else {
            finalBody = body
        }

        let truncationNote: String = if (truncated) { " (TRUNCATED)" } else { "" }

        let out = StringBuilder()
        out.append("=== Web Fetch (Raw HTML) ===\n")
        out.append("URL: ${targetUrl}\n")
        out.append("Original-Length: ${originalLen} bytes\n")
        out.append("Returned-Length: ${finalBody.size} bytes${truncationNote}\n")

        let refs = extractReferences(finalBody)
        if (!refs.isEmpty()) {
            out.append("\n----- REFERENCES (auto-extracted from BODY) -----\n")
            out.append(refs)
        }

        out.append("\n----- BODY -----\n")
        out.append(finalBody)
        return out.toString()
    }

    /**
     * Extract common navigation-bearing references (script src, link href,
     * iframe src, form action, anchor href) from the response body so the
     * model can pick the next hop without scanning the full body. Each
     * category is capped at 6 entries, in order of first appearance.
     * Returns an empty string when nothing meaningful is found.
     */
    private func extractReferences(body: String): String {
        let perCategoryCap: Int64 = 6

        let scripts = findAttrMatches(body,
            #"<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#, perCategoryCap)
        let links = findAttrMatches(body,
            #"<link\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#, perCategoryCap)
        let iframes = findAttrMatches(body,
            #"<iframe\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#, perCategoryCap)
        let forms = findAttrMatches(body,
            #"<form\b[^>]*\baction\s*=\s*["']([^"']+)["']"#, perCategoryCap)
        let anchors = findAnchorMatches(body, perCategoryCap)

        if (scripts.size == 0 && links.size == 0 && iframes.size == 0 &&
            forms.size == 0 && anchors.size == 0) {
            return ""
        }

        let out = StringBuilder()
        for (s in scripts) {
            out.append("script[src]: ${s}\n")
        }
        for (l in links) {
            out.append("link[href]: ${l}\n")
        }
        for (i in iframes) {
            out.append("iframe[src]: ${i}\n")
        }
        for (f in forms) {
            out.append("form[action]: ${f}\n")
        }
        for (a in anchors) {
            out.append("a[href]: ${a}\n")
        }
        return out.toString()
    }

    /**
     * Run a single capture-group regex over body, dedupe the captured
     * value (group 1) in insertion order, and stop after `cap` unique
     * non-empty matches.
     */
    private func findAttrMatches(body: String, pattern: String, cap: Int64): ArrayList<String> {
        let seen = HashSet<String>()
        let results = ArrayList<String>()
        let regex = Regex(pattern)
        for (md in regex.findAll(body, group: true)) {
            if (results.size >= cap) {
                break
            }
            let value = md.matchString(1).trimAscii()
            if (value.isEmpty()) {
                continue
            }
            if (!seen.contains(value)) {
                seen.add(value)
                results.add(value)
            }
        }
        return results
    }

    /**
     * Anchor extraction with extra filters that drop javascript: pseudo-protocols,
     * pure-fragment (#...) hrefs, mailto:, and the bare "/" root link, since
     * they are navigation noise rather than real resource references.
     */
    private func findAnchorMatches(body: String, cap: Int64): ArrayList<String> {
        let seen = HashSet<String>()
        let results = ArrayList<String>()
        let regex = Regex(#"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#)
        for (md in regex.findAll(body, group: true)) {
            if (results.size >= cap) {
                break
            }
            let value = md.matchString(1).trimAscii()
            if (value.isEmpty()) {
                continue
            }
            if (value.startsWith("javascript:") || value.startsWith("#") ||
                value.startsWith("mailto:") || value == "/") {
                continue
            }
            if (!seen.contains(value)) {
                seen.add(value)
                results.add(value)
            }
        }
        return results
    }
}
