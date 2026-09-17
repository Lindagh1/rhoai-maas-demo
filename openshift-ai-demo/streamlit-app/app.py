"""
Knowledge Advisor — Streamlit RAG application
==============================================
End-user facing app for the OpenShift AI 3.5 demo. Reuses the exact same
backend as the workbench notebooks:
  - all-minilm-l6-v2 predictor for query embedding
  - pgvector (document_chunks table, populated by the Data Science Pipeline)
    for semantic retrieval
  - llama-32-3b-instruct predictor for answer generation

Shows the retrieved context BEFORE the generated answer, so the RAG
mechanism is visible to the audience during the live demo.
"""
import os

import psycopg
import requests
import streamlit as st

EMBED_URL = os.environ.get(
    "EMBED_URL",
    "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings",
)
EMBED_MODEL = os.environ.get("EMBED_MODEL", "all-minilm-l6-v2")
LLM_URL = os.environ.get(
    "LLM_URL",
    "http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1/chat/completions",
)
LLM_MODEL = os.environ.get("LLM_MODEL", "llama-32-3b-instruct")
DB_URI = os.environ["DB_URI"]
TOP_K = int(os.environ.get("TOP_K", "3"))

st.set_page_config(page_title="Knowledge Advisor", page_icon="🧠", layout="centered")

st.markdown(
    """
    <style>
    .stApp { background-color: #f5f6fa; }
    .chunk-card {
        background: white; border-radius: 8px; padding: 12px 16px;
        margin-bottom: 8px; border-left: 4px solid #c00; font-size: 0.85em;
    }
    .answer-card {
        background: #ffffff; border-radius: 10px; padding: 20px 24px;
        border-left: 6px solid #0066cc; font-size: 1.1em;
    }
    </style>
    """,
    unsafe_allow_html=True,
)

st.title("🧠 Acme Corp — Knowledge Advisor")
st.caption(
    "Retrieval-Augmented Generation demo — Red Hat OpenShift AI 3.5 "
    "· embedding: all-minilm-l6-v2 · LLM: llama-32-3b-instruct · vector store: pgvector"
)

default_question = "Which days can employees work remotely?"
question = st.text_input("Ask a question about company policy:", value=default_question)
ask = st.button("Ask Knowledge Advisor", type="primary")


def embed_query(text: str) -> list[float]:
    resp = requests.post(EMBED_URL, json={"model": EMBED_MODEL, "input": [text]}, timeout=30)
    resp.raise_for_status()
    return resp.json()["data"][0]["embedding"]


def retrieve(embedding: list[float], k: int):
    conn = psycopg.connect(DB_URI)
    with conn.cursor() as cur:
        cur.execute(
            "SELECT source, chunk_index, content, 1 - (embedding <=> %s::vector) AS score "
            "FROM document_chunks ORDER BY embedding <=> %s::vector LIMIT %s;",
            (str(embedding), str(embedding), k),
        )
        rows = cur.fetchall()
    conn.close()
    return [{"source": r[0], "chunk_index": r[1], "content": r[2], "score": r[3]} for r in rows]


def generate_answer(question: str, chunks: list[dict]) -> str:
    context = "\n\n".join(f"[{c['source']}]\n{c['content']}" for c in chunks)
    prompt = (
        "You are the Acme Corp Knowledge Advisor. Answer the employee's question "
        "using ONLY the context below. Be concise and cite the source document.\n\n"
        f"CONTEXT:\n{context}\n\n"
        f"QUESTION: {question}\n\nANSWER:"
    )
    resp = requests.post(
        LLM_URL,
        json={
            "model": LLM_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 200,
            "temperature": 0.1,
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


if ask and question.strip():
    with st.spinner("Embedding query..."):
        try:
            query_embedding = embed_query(question)
        except Exception as e:
            st.error(f"Embedding call failed: {e}")
            st.stop()

    with st.spinner("Retrieving relevant company documents (pgvector)..."):
        try:
            chunks = retrieve(query_embedding, TOP_K)
        except Exception as e:
            st.error(f"pgvector retrieval failed: {e}")
            st.stop()

    st.subheader("📄 Retrieved context (before generation)")
    if not chunks:
        st.warning("No relevant chunks found.")
    for c in chunks:
        st.markdown(
            f"<div class='chunk-card'><b>{c['source']}</b> — chunk #{c['chunk_index']} "
            f"(similarity {c['score']:.3f})<br>{c['content'][:280]}"
            f"{'...' if len(c['content']) > 280 else ''}</div>",
            unsafe_allow_html=True,
        )

    with st.spinner("Generating answer with llama-32-3b-instruct..."):
        try:
            answer = generate_answer(question, chunks)
        except Exception as e:
            st.error(f"LLM call failed: {e}")
            st.stop()

    st.subheader("✅ Answer")
    st.markdown(f"<div class='answer-card'>{answer}</div>", unsafe_allow_html=True)

st.divider()
with st.expander("How this works (architecture)"):
    st.markdown(
        """
        1. **Embed** — your question is sent to the `all-minilm-l6-v2` model
           (served by KServe/vLLM on a CPU node) to get a 384-dimension vector.
        2. **Retrieve** — that vector is compared against the `document_chunks`
           table in the `pgvector-db` PostgreSQL instance using cosine
           similarity (HNSW index) to find the most relevant policy excerpts.
        3. **Augment + Generate** — the retrieved excerpts are inserted into a
           prompt sent to `llama-32-3b-instruct` (served by KServe/vLLM on an
           NVIDIA L4 GPU), which writes the final, grounded answer.
        """
    )
