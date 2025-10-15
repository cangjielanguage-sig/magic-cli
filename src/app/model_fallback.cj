package cli.app

import magic.core.model.ChatModel

import cli.core.config.CliConfig

import std.collection.ArrayList

class ModelFallback {
    /**
     * Check if an exception should trigger model fallback
     */
    static func shouldFallback(ex: Exception): Bool {
        // Only fallback if we have fallback models configured
        if (CliConfig.fallbackModels.size == 0) {
            return false
        }
        let message = ex.message.toAsciiLower()

        // HTTP and model errors that should trigger fallback
        return message.contains("timeout") ||
               message.contains("5") ||  // 5xx server errors
               message.contains("connection") ||
               message.contains("network") ||
               message.contains("429") ||  // Rate limiting
               message.contains("401") ||  // Unauthorized
               message.contains("rate limit") ||
               message.contains("quota") ||
               message.contains("api key") ||
               message.contains("unauthorized") ||
               message.contains("authentication")
    }

    // Session-level successful model memory (resets on restart)
    static var lastAvailableModel: Option<ChatModel> = None

    static func getAllModels(): Array<ChatModel> {
        let models = ArrayList<ChatModel>()
        if (let Some(model) <- lastAvailableModel) {
            // Use last successful model first
            models.add(model)
            if (model.fullName != CliConfig.model.fullName) {
                models.add(CliConfig.model)
            }
            for (model in CliConfig.fallbackModels) {
                if (model.fullName != model.fullName) {
                    models.add(model)
                }
            }
        } else {
            // First execution, use original order
            models.add(CliConfig.model)
            models.add(all: CliConfig.fallbackModels)
        }
        return models.toArray()
    }
}