import json
import os
import sys
import argparse
from typing import List, Optional, Dict, Any

from fastapi import FastAPI
from pydantic import BaseModel
from pymilvus import MilvusClient
import uvicorn

# Try importing different embedding model packages
use_langchain = True
try:
    from langchain_huggingface import HuggingFaceEmbeddings
except ImportError:
    use_langchain = False
    try:
        from transformers import AutoModel, AutoTokenizer
    except ImportError:
        raise ImportError("Either langchain-huggingface or transformers package is required.")


# Pydantic model definitions
class DocumentModel(BaseModel):
    id: str
    text: str
    parent_ids: List[str]
    source: str
    short: str
    long: Optional[str] = None  # Make long field optional
    example_code: Optional[str] = None
    example_coding_problem: Optional[str] = None
    text_w_example_code: Optional[str] = None
    url: str


# Init embedding model
embedding_model = None

# Init Milvus client with default path
# Will be updated by command line argument if provided
client = None

# Define collection name globally
collection_name = "cangjiedoc"


def initialize_milvus_client(db_path):
    """Initialize Milvus client with specified database path"""
    global client
    client = MilvusClient(uri=db_path)
    print(f"Connected to Milvus database at: {db_path}")


def initialize_embedding_model(model_path: str):
    global embedding_model
    if use_langchain:
        print("Using HuggingFaceEmbeddings from langchain-huggingface")
        embedding_model = HuggingFaceEmbeddings(
            model_name=model_path,
            model_kwargs={'device': 'cpu'},
            encode_kwargs={'normalize_embeddings': True}
        )
    else:
        print("Using transformers directly")
        tokenizer = AutoTokenizer.from_pretrained(model_path)
        model = AutoModel.from_pretrained(model_path)

        def embed_text(text: str) -> List[float]:
            inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
            outputs = model(**inputs)
            return outputs.last_hidden_state.mean(dim=1).squeeze().detach().numpy().tolist()

        embedding_model = embed_text


# Create collection (table) - moved to embed_data function
def create_collection_if_not_exists():
    if use_langchain:
        test_vector = embedding_model.embed_query("test")
    else:
        test_vector = embedding_model("test")

    """Create collection if it doesn't exist"""
    if not client.has_collection(collection_name=collection_name):
        client.create_collection(
            collection_name=collection_name,
            dimension=len(test_vector),
            metric_type="COSINE"
        )
        print(f"Created collection: {collection_name}")
    else:
        print(f"Collection {collection_name} already exists")


def load_data(file_path: str) -> List[DocumentModel]:
    """Read JSONL file and return data list"""
    data = []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            try:
                json_obj = json.loads(line)
                # Validate data with Pydantic model
                doc = DocumentModel(**json_obj)
                data.append(doc)
            except json.JSONDecodeError as e:
                print(f"Error decoding JSON: {e}")
            except Exception as e:
                print(f"Error validating data: {e}")
                print(f"Problematic data: {json_obj}")  # Print the problematic data
                # Try to create DocumentModel with fallback for missing 'long'
                if 'long' not in json_obj:
                    json_obj['long'] = json_obj.get('text', '')  # Use 'text' as fallback
                    try:
                        doc = DocumentModel(**json_obj)
                        data.append(doc)
                    except Exception as e2:
                        print(f"Error after fallback: {e2}")
    return data


def add_data_to_db(data: List[DocumentModel]):
    """Add data to Milvus database"""
    # Create collection if it doesn't exist
    create_collection_if_not_exists()

    # Prepare new data
    new_data = []
    for idx, item in enumerate(data):
        # Generate embedding vector
        if use_langchain:
            embedding = embedding_model.embed_query(item.short)
        else:
            embedding = embedding_model(item.short)

        new_data.append({
            "id": idx,
            "vector": embedding,
            "text": item.text,
            "short": item.short,
            "example_code": item.example_code,
            "url": item.url,
            "example_coding_problem": item.example_coding_problem
        })

    # Insert new data
    if new_data:
        client.insert(
            collection_name=collection_name,
            data=new_data
        )
        print(f"Added {len(new_data)} new items to the database")
    else:
        print("No new items to add")


def embed_data(doc_path):
    """Only build vector database"""
    # Load data
    data = load_data(doc_path)
    print(f"Loaded {len(data)} items from {doc_path}")

    # Add data to database
    add_data_to_db(data)
    print("Vector database built successfully.")


class RetrieveRequest(BaseModel):
    query: str
    num2retrieve: int = 5


class RetrieveResult(BaseModel):
    id: int
    score: float
    text: str
    short: str
    example_code: Optional[str] = None
    example_coding_problem: Optional[str] = None
    # url: str


# Create FastAPI application
app = FastAPI()

@app.post("/retrieve", response_model=List[RetrieveResult])
def retrieve_handler(request: RetrieveRequest):
    """Retrieval API endpoint"""
    results = retrieve(request.query, request.num2retrieve)
    return results


def retrieve(query: str, num2retrieve: int = 5) -> List[RetrieveResult]:
    """Retrieve relevant content from database based on query"""
    # Generate query vector
    if use_langchain:
        query_vector = embedding_model.embed_query(query)
    else:
        query_vector = embedding_model(query)

    # Search for similar vectors
    results = client.search(
        collection_name=collection_name,
        data=[query_vector],
        limit=num2retrieve,
        output_fields=["id", "text", "short", "example_code", "url"]
    )

    print(len(results[0]))

    # Format results
    formatted_results = []
    for result in results[0]:
        formatted_results.append(RetrieveResult(
            id=result["entity"]["id"],
            score=result["distance"],
            text=result["entity"]["text"],
            short=result["entity"]["short"],
            example_code=result["entity"].get("example_code"),
            example_coding_problem=result["entity"].get("example_coding_problem"),
            # url=result["entity"]["url"]
        ))

    return formatted_results


def serve_api(port):
    """Only start API server"""
    # Check if collection exists
    if not client.has_collection(collection_name=collection_name):
        print(f"Collection {collection_name} does not exist. Please run with --embed first.")
        return

    # Start API server
    print(f"Starting API server on port {port}...")
    uvicorn.run(app, host="0.0.0.0", port=port)


def main():
    # Initialize Abseil logging to avoid warning
    try:
        from absl import logging
        logging.use_absl_handler()
        logging.initialize_absl()
    except ImportError:
        pass  # If absl is not installed, ignore

    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Cangjie RAG Service")
    parser.add_argument("--embed", action="store_true", help="Only build vector database")
    parser.add_argument("--serve", action="store_true", help="Only start API server")
    parser.add_argument("--port", type=int, default=8000, help="Server port (default: 8000)")
    parser.add_argument("--db", type=str, default="milvus_cangjie_doc.db", help="Vector database path (default: milvus_cangjie_doc.db)")
    parser.add_argument("--doc", type=str, default="./data/cangjiedoc.jsonl", help="Document JSONL file path (default: ./data/cangjiedoc.jsonl)")
    parser.add_argument("--embed-model", type=str, default="./model/Conan-embedding-v1", help="Embedding model path (default: ./model/Conan-embedding-v1)")

    args = parser.parse_args()

    # Ensure embedding model is initialized
    initialize_embedding_model(args.embed_model)

    # Initialize Milvus client with specified database path
    initialize_milvus_client(args.db)

    if args.embed and args.serve:
        print("Error: --embed and --serve cannot be used together.")
        return
    elif args.embed:
        embed_data(args.doc)
    elif args.serve:
        serve_api(args.port)
    else:
        # Default behavior: build database and start server
        embed_data(args.doc)
        serve_api(args.port)


if __name__ == "__main__":
    main()
