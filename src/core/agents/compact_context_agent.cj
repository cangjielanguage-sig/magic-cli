package cli.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.tokenizer.Cl100kTokenizer
import magic.core.message.{Message, MessageRole, MessageList}

import cli.core.config.CliConfig

import std.fs.canonicalize

private let COMPACT_CONTEXT_PROMPT = """
You are the component that summarizes internal chat history into a given structure.

When the conversation history grows too large, you will be invoked to distill the entire history into a concise, structured XML snapshot. This snapshot is CRITICAL, as it will become the agent's *only* memory of the past. The agent will resume its work based solely on this snapshot. All crucial details, plans, errors, and user directives MUST be preserved.

First, you will think through the entire history in a private <scratchpad>. Review the user's overall goal, the agent's actions, tool outputs, file modifications, and any unresolved questions. Identify every piece of information that is essential for future actions.

After your reasoning is complete, generate the final <state_snapshot> XML object. Be incredibly dense with information. Omit any irrelevant conversational filler.

The structure MUST be as follows:

<state_snapshot>
    <overall_goal>
        <!-- A single, concise sentence describing the user's high-level objective. -->
        <!-- Example: "Refactor the authentication service to use a new JWT library." -->
    </overall_goal>

    <key_knowledge>
        <!-- Crucial facts, conventions, and constraints the agent must remember based on the conversation history and interaction with the user. Use bullet points. -->
        <!-- Example:
         - Build Command: `npm run build`
         - Testing: Tests are run with `npm test`. Test files must end in `.test.ts`.
         - API Endpoint: The primary API endpoint is `https://api.example.com/v2`.
        -->
    </key_knowledge>

    <file_system_state>
        <!-- List files that have been created, read, modified, or deleted. Note their status and critical learnings. -->
        <!-- Example:
         - CWD: `/home/user/project/src`
         - READ: `package.json` - Confirmed 'axios' is a dependency.
         - MODIFIED: `services/auth.ts` - Replaced 'jsonwebtoken' with 'jose'.
         - CREATED: `tests/new-feature.test.ts` - Initial test structure for the new feature.
        -->
    </file_system_state>

    <recent_actions>
        <!-- A summary of the last few significant agent actions and their outcomes. Focus on facts. -->
        <!-- Example:
         - Ran `grep 'old_function'` which returned 3 results in 2 files.
         - Ran `npm run test`, which failed due to a snapshot mismatch in `UserProfile.test.ts`.
         - Ran `ls -F static/` and discovered image assets are stored as `.webp`.
        -->
    </recent_actions>

    <current_plan>
        <!-- The agent's step-by-step plan. Mark completed steps. -->
        <!-- Example:
         1. [DONE] Identify all files using the deprecated 'UserAPI'.
         2. [IN PROGRESS] Refactor `src/components/UserProfile.tsx` to use the new 'ProfileAPI'.
         3. [TODO] Refactor the remaining files.
         4. [TODO] Update tests to reflect the API change.
        -->
    </current_plan>
</state_snapshot>
"""

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