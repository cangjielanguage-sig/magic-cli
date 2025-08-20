# cj-rag

## 项目介绍
这是一个基于 Milvus 和 Embeddings 模型的向量检索项目，用于存储和检索 Cangjie 语言的文档。项目支持命令行参数区分构建向量数据库和启动服务器功能，并使用 Pydantic 模型提高代码可读性和数据验证能力。

## 功能特点
1. 读取 JSONL 格式的文档数据并使用 Pydantic 模型进行验证
2. 支持两种嵌入模型方式：
   - 使用 langchain-huggingface 中的 HuggingFaceEmbeddings
   - 直接使用 transformers 库加载模型
3. 将数据存储到 Milvus 向量数据库
4. 提供检索 API，根据查询返回最相关的文档
5. 支持命令行参数区分构建数据库和启动服务器功能

## 目录结构
```
.
├── main.py         # 主程序入口
├── README.md       # 项目说明
└── data/           # 数据目录
    └── cangjiedoc.jsonl # 文档数据
```

## 安装依赖
```bash
uv pip install .
```

## 使用方法
### 命令行参数
- `--embed`: 仅构建向量数据库，不启动服务器
- `--serve`: 仅启动服务器，不构建数据库（前提是数据库已存在）
- `--port`: 服务器端口（默认：8000）
- `--db`: 向量数据库路径（默认：milvus_cangjie_doc.db）
- `--doc`: 文档JSONL文件路径（默认：./data/cangjiedoc.jsonl）
- `--embed-model`: 嵌入模型路径（默认：./model/Conan-embedding-v1）

### 运行方式
1. **构建数据库并启动服务器（默认行为）**
   ```bash
   python main.py
   ```

2. **仅构建数据库**
   ```bash
   python main.py --embed
   ```

3. **仅启动服务器**
   ```bash
   python main.py --serve
   ```

### 检索示例
服务器启动后，可以通过 POST 请求访问 `/retrieve` 端点进行检索
```bash
curl -X POST "http://0.0.0.0:8000/retrieve" \
-H "Content-Type: application/json" \
-d '{"query": "function", "num2retrieve": 5}'
```

## API 说明
### POST /retrieve
根据查询内容从数据库中检索相关文档

**参数:**
- `query`: 检索查询内容（必填）
- `num2retrieve`: 要检索的文档数量（可选，默认值为 5）

**返回:**
- 包含检索结果的 JSON 数组，每个结果包含文档 ID、得分、文本内容等信息

## 注意事项
1. 首次运行时，建议使用 `--embed` 选项构建数据库
2. 确保有足够的内存来运行嵌入模型和 Milvus 数据库
3. 如果修改了数据文件，需要使用 `--embed` 选项重新构建数据库
4. 确保嵌入模型路径正确