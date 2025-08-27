package cli.core.tools

import magic.dsl.*
import magic.prelude.*

@toolset
public class SearchToolset {
    @tool[
        description: "Use Tavily for web search to get the latest online information. Returns 5 results by default, includes AI summary answers, with basic search depth",
        parameters: {
            query: "Search query string"
        }
    ]
    public func search(query: String): String {
        let tool = TavilyTool()
        return tool.search(query)
    }
}
