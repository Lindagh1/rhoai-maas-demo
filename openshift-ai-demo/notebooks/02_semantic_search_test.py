"""Validate semantic search over the pgvector store."""
import os

import psycopg
import requests

EMBED_URL = "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings"
EMBED_MODEL = "all-minilm-l6-v2"


def embed(text: str):
    resp = requests.post(EMBED_URL, json={"model": EMBED_MODEL, "input": text}, timeout=30)
    resp.raise_for_status()
    return resp.json()["data"][0]["embedding"]


def search(query: str, k: int = 3):
    vec = embed(query)
    conn = psycopg.connect(os.environ["URI"])
    with conn.cursor() as cur:
        cur.execute(
            "SELECT source, chunk_index, content, 1 - (embedding <=> %s) AS similarity "
            "FROM document_chunks ORDER BY embedding <=> %s LIMIT %s",
            (str(vec), str(vec), k),
        )
        rows = cur.fetchall()
    conn.close()
    return rows


if __name__ == "__main__":
    query = "Which days can employees work remotely?"
    print(f"QUERY: {query}\n")
    for source, idx, content, sim in search(query):
        print(f"[{sim:.4f}] {source} #{idx}")
        print("   ", content.replace("\n", " ")[:200])
        print()
