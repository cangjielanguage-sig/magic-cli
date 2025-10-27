package cli.core.agents.subagents

/**
 * SubAgents Package
 * 
 * 专业化的SubAgent集合，用于多Agent协作系统。
 * 
 * 对标世界级AI编程助手（Codebuff、Claude Code、Codex）的Agent架构。
 * 
 * ## 架构设计
 * 
 * 采用LeaderGroup模式（CangjieMagic提供）：
 * - 主Agent作为Leader协调所有SubAgent
 * - SubAgent作为专业工具被主Agent调用
 * - 通过AgentAsTool机制实现无缝集成
 * 
 * ## SubAgent列表
 * 
 * ### Phase 1 (Week 1-2): 核心SubAgent
 * 1. **PlannerAgent** - 任务规划专家
 *    - 将复杂任务分解为可执行步骤
 *    - 识别依赖关系和执行顺序
 *    - 评估复杂度和风险
 * 
 * 2. **ExplorerAgent** - 代码探索专家
 *    - 快速理解项目结构
 *    - 分析依赖关系
 *    - 识别关键文件和模式
 * 
 * 3. **EditorAgent** - 精确编辑专家
 *    - 外科手术式代码修改
 *    - 保持代码风格一致
 *    - 确保最小化改动
 * 
 * 4. **ReviewerAgent** - 代码审查专家
 *    - 质量保证和错误检查
 *    - 编译验证
 *    - 最佳实践强制
 * 
 * ### Phase 2 (Week 3): 高级SubAgent
 * 5. **TestGeneratorAgent** - 测试生成专家
 *    - 生成全面的测试用例
 *    - 覆盖率分析
 *    - 适配各种测试框架
 * 
 * 6. **RefactoringAgent** - 重构建议专家
 *    - 代码异味检测
 *    - 重构建议和模式推荐
 *    - 代码质量提升
 * 
 * ## 使用示例
 * 
 * Example:
 * import cli.core.agents.subagents.*
 * import magic.agent_group.LeaderGroup
 * 
 * // 创建主Agent和SubAgent
 * let mainAgent = CangjieCodeAgent()
 * let plannerAgent = PlannerAgent()
 * let explorerAgent = ExplorerAgent()
 * let editorAgent = EditorAgent()
 * let reviewerAgent = ReviewerAgent()
 * 
 * // 使用LeaderGroup集成
 * let agent = LeaderGroup(
 *     leader: mainAgent,
 *     members: [plannerAgent, explorerAgent, editorAgent, reviewerAgent]
 * )
 * 
 * // 现在mainAgent可以调用所有SubAgent作为工具
 * let response = agent.chat(AgentRequest("Add authentication to this app"))
 * 
 * 
 * ## 设计原则
 * 
 * 1. **专业化**: 每个SubAgent专注于特定领域
 * 2. **简洁**: 利用CangjieMagic的LeaderGroup，避免重复造轮子
 * 3. **质量**: 详细的Prompt确保高质量输出
 * 4. **可扩展**: 易于添加新的专业SubAgent
 * 
 * ## 参考资料
 * 
 * - plan4.md - 完整实施计划
 * - Codebuff Agent架构
 * - CangjieMagic LeaderGroup文档
 */

// SubAgents导出说明
// 注意：Cangjie需要在每个.cj文件中使用public class来导出
// pkg.cj 只需要声明package即可，类的public修饰符已经在各自文件中声明

// Phase 1 SubAgents (已完成)
// - PlannerAgent
// - ExplorerAgent
// - EditorAgent
// - ReviewerAgent

// Phase 2 SubAgents (已完成)
// - TestGeneratorAgent
// - RefactoringAgent

