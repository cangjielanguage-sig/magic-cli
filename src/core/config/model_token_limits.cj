package cli.core.config

import std.collection.HashMap

protected class ModelTokenLimits {
    public static let DEFAULT_LIMIT: Int64 = 131072

    private static let CONTEXT_LIMITS = HashMap<String, Int64>([
        // Ark (ByteDance) models
        ("ark:kimi-k2-250711", 128 * 1024),
        ("ark:kimi-k2-250905", 256 * 1024),
        ("ark:doubao-seed-1-6-flash-250828", 256 * 1024),
        ("ark:doubao-1-5-pro-32k-250115", 32 * 1024),
        ("ark:deepseek-v3-1-250821", 128 * 1024),
        ("ark:deepseek-v3-250324", 128 * 1024),
        ("ark:deepseek-r1-250528", 128 * 1024),

        // Moonshot models
        ("moonshot:kimi-k2-0905-preview", 256 * 1024),

        // Zhipu AI models
        ("zhipuai:glm-4.5", 128 * 1024),
        ("zhipuai:glm-4.5-air", 128 * 1024),
        ("zhipuai:glm-4-plus", 128 * 1024),


        // Qwen models
        ("dashscope:qwen3-max-preview", 256 * 1024),
        ("dashscope:qwen-plus", 128 * 1024),
        ("dashscope:qwen-flash", 1024 * 1024),
        ("dashscope:qwen3-coder-plus", 1024 * 1024),
        ("dashscope:qwen3-coder-flash", 1024 * 1024),

        // DeepSeek models
        ("deepseek:deepseek-chat", 128 * 1024),
        ("deepseek:deepseek-reasoner", 128 * 1024),

        // OpenAI GPT models
        ("openai:gpt-4", 128 * 1024),
        ("openai:gpt-4-turbo", 128 * 1024),
        ("openai:gpt-4o", 128 * 1024),
        ("openai:gpt-3.5-turbo", 16 * 1024),

        // Google Gemini models
        ("google:gemini-1.5-flash", 1024 * 1024),
        ("google:gemini-2.5-pro-preview-05-06", 1024 * 1024),
        ("google:gemini-2.5-pro-preview-06-05", 1024 * 1024),
        ("google:gemini-2.5-pro", 1024 * 1024),
        ("google:gemini-2.5-flash-preview-05-20", 1024 * 1024),
        ("google:gemini-2.5-flash", 1024 * 1024),
        ("google:gemini-2.5-flash-lite", 1024 * 1024),
        ("google:gemini-2.0-flash", 1024 * 1024)
    ])

    public static func getContextLimit(model: String): Int64 {
        return CONTEXT_LIMITS.get(model).getOrDefault { DEFAULT_LIMIT }
    }
}