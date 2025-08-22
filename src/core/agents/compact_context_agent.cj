package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.tokenizer.Cl100kTokenizer
import magic.core.message.{Message, MessageRole, MessageList}

import cli.core.config.CliConfig

import std.fs.canonicalize

@agent[
    model: "${CliConfig.model}",
    executor: "naive"
]
public class CompactContextAgent {
    @prompt(
        """
        ${COMPACT_CONTEXT_PROMPT}
        """
    )
}
// default model (ark:kimi-k2) context token limit
const DEFAULT_TOKEN_LIMIT = 131072
// If the total token of conversation is less than 70% of the model context token limit, then no need to compact
const COMPACT_TOKEN_THRESHOLD = 0.7
// The last 30% of the conversation will be preserved during compact
const COMPACT_PRESERVE_THRESHOLD = 0.3

public class Compactor {
    private let tokenizer: Cl100kTokenizer = Cl100kTokenizer(canonicalize("./src/libs/cl100k_base.tiktoken").toString())

    public func compact(conversation: Conversation): (Conversation, Bool) {
        if (conversation.isEmpty()) {
            println("Conversation is empty, nothing to compact.")
            return (Conversation(), false)
        }
        let (totalTokens, roundTokens) = this.calculateToken(conversation)
        // If the total token of conversation is less than 70% of the model context token limit, then no need to compact
        if (totalTokens <= Int64(Float64(DEFAULT_TOKEN_LIMIT) * COMPACT_TOKEN_THRESHOLD)) {
           println("Conversation tokens: ${totalTokens}, not need to compact.")
           return (conversation, false)
        }
        // Calculate the number of chat rounds to be compacted based on the token count
        var compactTokens = totalTokens - Int64(Float64(DEFAULT_TOKEN_LIMIT) * COMPACT_PRESERVE_THRESHOLD)
        var compactRounds = 0
        for (i in 0..roundTokens.size) {
            if (compactTokens <= 0) {
                break
            }
            compactTokens -= roundTokens[i]
            compactRounds++
        }
        var toBeCompactedContent = StringBuilder()
        for(i in 0..compactRounds){
            toBeCompactedContent.append(conversation[i].toString())
        }
        let agent = CompactContextAgent()
        let response = agent.chat(toBeCompactedContent.toString())
        // Add the compacted conversation history to the new conversation
        let newConversation = Conversation()
        newConversation.addChatRound(ChatRound(
            Message.user("Compact the conversation history of the previous round"),
            Message.assistant(response),
            MessageList()
        ))
        // Add the preserved conversation history to the new conversation
        for(i in compactRounds..conversation.size){
            newConversation.addChatRound(conversation[i])
        }
        return (newConversation, true)
    }

    public func autoCompact(conversation: Conversation): (Conversation, Bool) {
        let (totalTokens, _) = this.calculateToken(conversation)
        let threshold = Int64(Float64(DEFAULT_TOKEN_LIMIT) * COMPACT_TOKEN_THRESHOLD)
        if (totalTokens > threshold) {
            return this.compact(conversation)
        } else {
            return (conversation, false)
        }
    }

    private func calculateToken(conversation: Conversation): (Int64, ArrayList<Int64>) {
        // TODO: Based on language mode(cj/other lang) to count different system prompt tokens
        let systemPromptTokens = this.tokenizer.countToken("${CANGJIE_CODE_AGENT_PROMPT}")
        var totalTokens: Int64 = systemPromptTokens
        let roundTokens = ArrayList<Int64>()
        // Calculate the total token of the current conversation and token consumption for each ChatRound
        for (chatRound in conversation) {
            let tokens = this.tokenizer.countToken(chatRound.toString())
            roundTokens.add(tokens)
            totalTokens += tokens
        }
        return (totalTokens, roundTokens)
    }
}