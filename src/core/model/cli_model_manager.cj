package cli.core.model

import magic.core.model.ChatModel
import magic.model.ModelManager

import cli.core.config.CliConfig

import std.collection.{ArrayList, map, collectArray}

/**
 * Manage model fallback logic and selection
 * Avoid name confusion with Magic's ModelManager class
 */
protected class CliModelManager {
    /**
     * Check if an exception should trigger model fallback
     */
    protected static func shouldFallback(ex: Exception): Bool {
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

    private static func buildModel(model: String): ChatModel {
        let m = ModelManager.createChatModel(model)
        m.maxTokens = ModelTokenLimits.getMaxOutputTokensLimit(model)
        return m
    }

    private static var _model: Option<ChatModel> = None

    protected static prop model: ChatModel {
        get() {
            if (let Some(m) <- _model) {
                return m
            }
            let m = buildModel(CliConfig.model)
            _model = m
            return m
        }
    }

    private static var _fastModel: Option<ChatModel> = None
    protected static prop fastModel: Option<ChatModel> {
        get() {
            if (let Some(m) <- _fastModel) {
                return m
            }
            if (let Some(m) <- CliConfig.fastModel) {
                _fastModel = buildModel(m)
            }
            return _fastModel
        }
    }

    private static var _fallbackModels: Array<ChatModel> = []
    private static prop fallbackModels: Array<ChatModel> {
        get() {
            if (_fallbackModels.isEmpty()) {
                _fallbackModels = CliConfig.fallbackModels |>
                    map { model => buildModel(model) } |>
                    collectArray
            }
            return _fallbackModels
        }
    }

    // Session-level successful model memory (resets on restart)
    protected static var lastAvailableModel: Option<ChatModel> = None

    protected static func getAllModels(): Array<ChatModel> {
        let models = ArrayList<ChatModel>()
        if (let Some(model) <- lastAvailableModel) {
            // Use last successful model first
            models.add(model)
            if (model.fullName != CliModelManager.model.fullName) {
                models.add(CliModelManager.model)
            }
            for (model in CliModelManager.fallbackModels) {
                if (model.fullName != CliModelManager.model.fullName) {
                    models.add(model)
                }
            }
        } else {
            // First execution, use original order
            models.add(CliModelManager.model)
            models.add(all: CliModelManager.fallbackModels)
        }
        return models.toArray()
    }
}