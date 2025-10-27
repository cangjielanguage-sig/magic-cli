package cli.core.context

import std.fs.{Path, File, exists}
import std.collection.{HashMap, ArrayList}
import magic.log.LogUtils

/**
 * 文件变更类型
 */
public enum ChangeType {
    | Modified
    | Deleted
}

/**
 * 文件变更信息
 */
public class FileChange {
    public let path: Path
    public let changeType: ChangeType
    
    public init(path: Path, changeType: ChangeType) {
        this.path = path
        this.changeType = changeType
    }
    
    public func toString(): String {
        let typeStr = match (this.changeType) {
            case ChangeType.Modified => "Modified"
            case ChangeType.Deleted => "Deleted"
        }
        return "${typeStr}: ${this.path.toString()}"
    }
}

/**
 * 文件监控器 - 简化版 v1.0
 * 
 * 功能：
 * - 监控已缓存文件的变更
 * - 基于内容哈希检测变更
 * - 按需检查（非实时）
 * - 自动同步 ContextEngine
 */
public class FileWatcher {
    // 文件内容哈希缓存：路径 -> 哈希值
    private var contentHashes: HashMap<String, Int64>
    
    // 关联的 ContextEngine
    private var contextEngine: ContextEngine
    
    public init(contextEngine: ContextEngine) {
        this.contentHashes = HashMap<String, Int64>()
        this.contextEngine = contextEngine
    }
    
    /**
     * 开始跟踪文件
     */
    public func track(path: Path): Unit {
        if (exists(path)) {
            try {
                let content = String.fromUtf8(File.readFrom(path))
                let hash = this.hashContent(content)
                this.contentHashes[path.toString()] = hash
                LogUtils.debug("Tracking file: ${path.toString()}")
            } catch (e: Exception) {
                LogUtils.error("Failed to track file ${path.toString()}: ${e.message}")
            }
        }
    }
    
    /**
     * 停止跟踪文件
     */
    public func untrack(path: Path): Unit {
        this.contentHashes.remove(path.toString())
        LogUtils.debug("Stopped tracking file: ${path.toString()}")
    }
    
    /**
     * 检查所有已跟踪文件的变更
     */
    public func checkChanges(): Array<FileChange> {
        let changes = ArrayList<FileChange>()
        
        // 检查 ContextEngine 中的所有文件
        for (cachedPath in this.contextEngine.getAllFiles()) {
            let pathKey = cachedPath.toString()
            
            // 获取记录的哈希
            let oldHash = this.contentHashes.get(pathKey)
            
            if (!exists(cachedPath)) {
                // 文件已删除
                if (oldHash != None) {
                    changes.add(FileChange(cachedPath, ChangeType.Deleted))
                }
            } else {
                // 检查内容是否修改
                try {
                    let content = String.fromUtf8(File.readFrom(cachedPath))
                    let newHash = this.hashContent(content)
                    
                    match (oldHash) {
                        case Some(oldH) =>
                            if (newHash != oldH) {
                                changes.add(FileChange(cachedPath, ChangeType.Modified))
                            }
                        case _ =>
                            // 第一次跟踪
                            this.contentHashes[pathKey] = newHash
                    }
                } catch (e: Exception) {
                    LogUtils.error("Failed to check file ${cachedPath.toString()}: ${e.message}")
                }
            }
        }
        
        return changes.toArray()
    }
    
    /**
     * 同步上下文：更新或移除变更的文件
     * 
     * ✨ P3-3: FileWatcher 深度集成
     * - 使用 updateFile() 保留元数据（relevanceScore, priority, isPinned）
     * - 自动更新缓存内容
     * - 详细日志记录
     */
    public func syncContext(): Array<FileChange> {
        let changes = this.checkChanges()
        
        for (change in changes) {
            match (change.changeType) {
                case ChangeType.Modified =>
                    // ✨ P3-3: 使用 updateFile() 而不是 addFile()，保留元数据
                    try {
                        let content = String.fromUtf8(File.readFrom(change.path))
                        
                        // 检查文件是否在缓存中
                        if (this.contextEngine.getFileContext(change.path).isSome()) {
                            // 文件在缓存中，使用 updateFile 保留元数据
                            this.contextEngine.updateFile(change.path, content)
                            LogUtils.info("[FileWatcher] Cache updated (metadata preserved): ${change.path.toString()}")
                        } else {
                            // 文件不在缓存中，使用 addFile
                            this.contextEngine.addFile(change.path, content)
                            LogUtils.info("[FileWatcher] Cache added for new file: ${change.path.toString()}")
                        }
                        
                        // 更新哈希
                        let newHash = this.hashContent(content)
                        this.contentHashes[change.path.toString()] = newHash
                    } catch (e: Exception) {
                        LogUtils.error("[FileWatcher] Failed to update cache: ${e.message}")
                    }
                
                case ChangeType.Deleted =>
                    // 从缓存中移除
                    this.contextEngine.removeFile(change.path)
                    this.contentHashes.remove(change.path.toString())
                    LogUtils.info("[FileWatcher] Removed deleted file from cache: ${change.path.toString()}")
            }
        }
        
        if (changes.size > 0) {
            LogUtils.info("[FileWatcher] Synced ${changes.size} file change(s)")
        }
        
        return changes
    }
    
    /**
     * 计算字符串内容的简单哈希
     * 使用 DJB2 哈希算法
     */
    private func hashContent(content: String): Int64 {
        var hash: Int64 = 5381
        
        for (ch in content.toRuneArray()) {
            hash = ((hash << 5) + hash) + Int64(UInt32(ch))
        }
        
        return hash
    }
    
    /**
     * 获取已跟踪的文件数量
     */
    public func getTrackedCount(): Int64 {
        return this.contentHashes.size
    }
    
    /**
     * 清空所有跟踪
     */
    public func clear(): Unit {
        this.contentHashes.clear()
        LogUtils.debug("Cleared all file tracking")
    }
    
    /**
     * 获取统计信息
     */
    public func getStats(): String {
        return "FileWatcher: tracking ${this.contentHashes.size} file(s)"
    }
}

