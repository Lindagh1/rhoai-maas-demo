"""
Knowledge Advisor — Document Ingestion
=======================================
Chunks the four company documents, embeds each chunk with the
all-minilm-l6-v2 model (served via KServe/vLLM in the my-first-model
project), and stores the vectors in the pgvector-backed PostgreSQL
database provisioned for the knowledge-advisor project.

Run this from inside the knowledge-advisor-workbench (it relies on the
`vector-database` and `company-documents` Connections already attached to
the workbench as env vars: URI, AWS_*).
"""
import glob
import os
import re

import psycopg
import requests

EMBED_URL = "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings"
EMBED_MODEL = "all-minilm-l6-v2"
EMBED_DIM = 384
DOCS_DIR = "/opt/app-root/src/documents"


def chunk_markdown(text: str, source: str, max_chars: int = 600):
    """Header-aware chunking: split on markdown '## ' section boundaries so
    each policy section (e.g. "## Eligible days") becomes its own retrievable
    chunk, prefixed with the document title for context. Sections longer than
    max_chars are further packed paragraph-by-paragraph."""
    title_match = re.match(r"#\s+(.+)", text.strip())
    title = title_match.group(1).strip() if title_match else source

    sections = re.split(r"\n(?=##\s)", text)
    chunks = []
    for section in sections:
        section = section.strip()
        if not section:
            continue
        # Strip the leading '# Title ...' front-matter block if present
        if section.startswith("#") and not section.startswith("##"):
            # This is the doc header/front-matter section; keep it short.
            section = section.strip()
        header_match = re.match(r"##\s+(.+)", section)
        heading = header_match.group(1).strip() if header_match else None

        if len(section) <= max_chars:
            content = f"{title} — {heading}\n{section}" if heading else section
            chunks.append(content)
            continue

        # Long section: pack paragraphs, always prefixing with title/heading
        # so no chunk loses its context.
        paragraphs = [p.strip() for p in re.split(r"\n\s*\n", section) if p.strip()]
        current = ""
        for p in paragraphs:
            if len(current) + len(p) + 1 > max_chars and current:
                prefix = f"{title} — {heading}\n" if heading else ""
                chunks.append(prefix + current.strip())
                current = p
            else:
                current = (current + "\n" + p).strip()
        if current:
            prefix = f"{title} — {heading}\n" if heading else ""
            chunks.append(prefix + current.strip())

    return [{"source": source, "chunk_index": i, "content": c} for i, c in enumerate(chunks)]


def embed(texts):
    resp = requests.post(EMBED_URL, json={"model": EMBED_MODEL, "input": texts}, timeout=30)
    resp.raise_for_status()
    data = resp.json()["data"]
    data.sort(key=lambda d: d["index"])
    return [d["embedding"] for d in data]


def main():
    conn = psycopg.connect(os.environ["URI"])
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS document_chunks (
            id SERIAL PRIMARY KEY,
            source TEXT NOT NULL,
            chunk_index INT NOT NULL,
            content TEXT NOT NULL,
            embedding VECTOR({EMBED_DIM})
        );
        """
    )
    conn.execute("TRUNCATE document_chunks;")

    all_chunks = []
    for path in sorted(glob.glob(f"{DOCS_DIR}/*.md")):
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        all_chunks.extend(chunk_markdown(text, os.path.basename(path)))

    print(f"Prepared {len(all_chunks)} chunks from {len(glob.glob(f'{DOCS_DIR}/*.md'))} documents")

    batch = 16
    for i in range(0, len(all_chunks), batch):
        group = all_chunks[i : i + batch]
        vectors = embed([c["content"] for c in group])
        with conn.cursor() as cur:
            for c, v in zip(group, vectors):
                cur.execute(
                    "INSERT INTO document_chunks (source, chunk_index, content, embedding) "
                    "VALUES (%s, %s, %s, %s)",
                    (c["source"], c["chunk_index"], c["content"], str(v)),
                )
        conn.commit()
        print(f"  embedded + stored chunks {i}..{i+len(group)-1}")

    conn.execute("CREATE INDEX IF NOT EXISTS document_chunks_embedding_idx "
                 "ON document_chunks USING hnsw (embedding vector_cosine_ops);")
    conn.commit()

    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM document_chunks;")
        print(f"Total rows in document_chunks: {cur.fetchone()[0]}")

    conn.close()


if __name__ == "__main__":
    main()
