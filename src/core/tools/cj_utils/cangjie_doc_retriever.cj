package cli.core.tools.cj_utils

import magic.dsl.*
import magic.prelude.*

import cli.core.model.CliModelManager
import cli.core.config.CliConfig
import cli.utils.ApiClient

import std.collection.HashMap
import stdx.encoding.json.*

@agent[
    executor: "naive",
    model: CliModelManager.fastModel ?? CliModelManager.model
]
private class DocSummaryAssistant {
    @prompt("""
        You are an expert programming assistant.
        Your task is to distill technical documentation for another AI agent that will write Cangjie code.
        Based on the user's original query, extract ONLY the most relevant information from the provided documents.
        Focus on code examples, function signatures, class/struct definitions, and explanations directly related to the query.
        Remove all irrelevant information, long narrative paragraphs, and formatting noise.
        The output must be concise and directly usable for code generation.
    """)
}

protected func retrieveCangjieDocumentsInternal(query: String, numToRetrieve: Option<Int64>): String {
    let url = "http://119.3.125.66:5384/retrieve"
    let header = HashMap<String, String>([
        ("Content-Type", "application/json")
    ])
    let requestMap = HashMap<String, JsonValue>()
    requestMap.add("query", JsonString(query))
    requestMap.add("nums_docs_to_retrive", (numToRetrieve ?? 5).toJsonValue())
    let requestBody = JsonObject(requestMap)
    let rawResponseOpt = ApiClient.post(url, header, requestBody)
    let rawResponse = match (rawResponseOpt) {
        case Some(resp) => resp
        case None => return "Request failed, no server response received"
    }
    let responseData: JsonValue
    try {
        responseData = JsonValue.fromStr(rawResponse)
    } catch (e: Exception) {
        return "JSON parsing failed: ${e.message}. Server raw response: ${rawResponse}"
    }
    let resultJson = match (responseData) {
        case jsonObj: JsonObject =>
            filterChunks(jsonObj).toJsonString()
        case _ =>
            responseData.toJsonString()
    }
    let docSummaryAssistant = DocSummaryAssistant()
    let promptForSummarizer = """
        Original User Query: "${query}"

        --- Retrieved Documents ---
        ${resultJson}
        --- End of Documents ---
    """
    let summary = docSummaryAssistant.chat(promptForSummarizer)
    return summary
}

private func filterChunks(jsonObj: JsonObject): JsonObject {
    let filteredChunks = ArrayList<JsonValue>()

    if (let Some(docsValue) <- jsonObj.get("docs")) {
        let chunksArrays = docsValue as JsonArray

        if (let Some(chunksArray) <- chunksArrays) {
            for (i in 0..chunksArray.size()) {
                let chunk = chunksArray[i]
                match (chunk) {
                    case jsonStr: JsonString =>
                        if (jsonStr.getValue().contains("```cangjie")) {
                            filteredChunks.add(chunk)
                        }
                    case _ =>
                        ()
                }
            }
        }
    }

    let resultMap = HashMap<String, JsonValue>()
    resultMap.add("docs", JsonArray(filteredChunks))
    return JsonObject(resultMap)
}

