package cli.telemetry

import cli.core.tools.cj_utils.FixSummary

import magic.utils.http.HttpUtils
import magic.core.message.ChatRound
import magic.log.LogUtils
import cli.core.config.CliConfig

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}
import magic.jsonable.*
import std.collection.HashMap

protected class DataCollector {
    private static let HOST = "http://localhost:8000"

    protected static func collectFixSummary(fixSummary: String): Unit {
        if (!CliConfig.collectData) {
            return
        }
        LogUtils.debug("Collecting fix summary")
        try {
            for (item in ("\n" + fixSummary).split("\n### ")) {
                if (item.trimAscii().isEmpty()) {
                    continue
                }
                let jo = FixSummary.fromMarkdown("### " + item).map{x => x.toJsonValue()}.getOrThrow().asObject()  // ?? JsonString(fixSummary))
                HttpUtils.post(
                    "${HOST}/api/fix-summary",
                    HashMap([("Content-Type", "application/json")]),
                    jo
                )
            }
            
        } catch (ex: Exception) {
            LogUtils.error("Failed to collect fix summary: ${ex}")
        }
    }

    protected static func collectChatRound(chatRound: ChatRound): Unit {
        if (!CliConfig.collectData) {
            return
        }
        LogUtils.debug("Collecting chat round")
        try {
            HttpUtils.post(
                "${HOST}/api/agent-chat-round",
                HashMap([("Content-Type", "application/json")]),
                chatRound.toJsonValue().asObject()
            )
        } catch (ex: Exception) {
            LogUtils.error("Failed to collect chat round: ${ex}")
        }
    }

    protected static func queryFixSummary(error_message: String): Array<FixSummary> {
        try {
            LogUtils.info("querry fix summary with error message: ${error_message}")
            let jo = JsonObject()
            jo.put("query", JsonString(error_message))
            let response = HttpUtils.post(
                "${HOST}/api/query-fix-summary",
                HashMap([("Content-Type", "application/json")]),
                jo
            ).getOrThrow()
            Array<FixSummary>.fromJsonValue(JsonValue.fromStr(response))
        } catch (ex: Exception) {
            LogUtils.error("Failed to query fix summary: ${ex}")
            []
        }
    }
}