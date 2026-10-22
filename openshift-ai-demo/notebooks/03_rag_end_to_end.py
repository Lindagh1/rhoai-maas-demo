"""
Knowledge Advisor — End-to-end RAG test
========================================
1. Embed the user question with all-minilm-l6-v2.
2. Retrieve the top-k relevant chunks from pgvector.
3. Build an augmented prompt.
4. Send it to the governed MaaS endpoint for llama-32-3b-instruct.
5. Print the retrieved context and the final answer.
"""
import os

import psycopg
import requests

EMBED_URL = "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings"
EMBED_MODEL = "all-minilm-l6-v2"

# MaaS-governed endpoint for llama-32-3b-instruct (see MAAS_ENDPOINT / MAAS_API_KEY
# env vars documented in DEMO-CLICKBOOK.md — falls back to the direct in-cluster
# predictor endpoint if the MaaS gateway route/key is not set in this shell).
MAAS_ENDPOINT = os.environ.get("MAAS_ENDPOINT", "http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions")
MAAS_API_KEY = os.environ.get("MAAS_API_KEY", "")
LLM_MODEL = "llama-32-3b-instruct"


def embed(text: str):
    resp = requests.post(EMBED_URL, json={"model": EMBED_MODEL, "input": text}, timeout=30)
    resp.raise_for_status()
    return resp.json()["data"][0]["embedding"]


def retrieve(query: str, k: int = 3):
    vec = embed(query)
    conn = psycopg.connect(os.environ["URI"])
    with conn.cursor() as cur:
        cur.execute(
            "SELECT source, content, 1 - (embedding <=> %s) AS similarity "
            "FROM document_chunks ORDER BY embedding <=> %s LIMIT %s",
            (str(vec), str(vec), k),
        )
        rows = cur.fetchall()
    conn.close()
    return rows


def ask_llm(question: str, context_chunks):
    context = "\n\n---\n\n".join(f"(source: {src})\n{content}" for src, content, _ in context_chunks)
    prompt = (
        "You are the Knowledge Advisor, an internal assistant that answers "
        "employee questions using ONLY the company documents provided below. "
        "Be concise and cite the source file when possible.\n\n"
        f"COMPANY DOCUMENTS:\n{context}\n\n"
        f"QUESTION: {question}\n\nANSWER:"
    )
    headers = {"Content-Type": "application/json"}
    if MAAS_API_KEY:
        headers["Authorization"] = f"Bearer {MAAS_API_KEY}"
    payload = {
        "model": LLM_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 200,
        "temperature": 0.1,
    }
    resp = requests.post(MAAS_ENDPOINT, json=payload, headers=headers, timeout=60)
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


if __name__ == "__main__":
    question = "Which days can employees work remotely?"
    chunks = retrieve(question)

    print("=" * 70)
    print("RETRIEVED CONTEXT (before LLM generation)")
    print("=" * 70)
    for src, content, sim in chunks:
        print(f"[{sim:.4f}] {src}")
        print("  ", content.replace("\n", " ")[:180])
        print()

    print("=" * 70)
    print("LLM ENDPOINT:", MAAS_ENDPOINT)
    print("=" * 70)
    answer = ask_llm(question, chunks)
    print("FINAL ANSWER:")
    print(answer)
