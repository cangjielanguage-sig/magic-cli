package cli.context

import magic.agent.ConversationAgent
import std.fs.Path

protected enum CliMode {
    | AGENTIC
    | TERMINAL
    | CHATTING
    | CONFIRM
}

protected interface Context {
    prop workspace: Path

    prop mode: CliMode

    prop agent: ConversationAgent

    prop workingThread: Int64

    func changeMode(mode: CliMode): Unit

    func startConversation(threadNum: Int64): Bool 

    func endConversation(threadNum: Int64): Unit

    func interrupted(threadNum: Int64): Bool

    func interrupt(): Unit
}

protected var CLI_CONTEXT: Box<Option<Context>> = Box(None)

protected func getContext(): Context {
    CLI_CONTEXT.value.getOrThrow()
}

protected func setContext(context: Context): Unit {
    CLI_CONTEXT.value = context
}