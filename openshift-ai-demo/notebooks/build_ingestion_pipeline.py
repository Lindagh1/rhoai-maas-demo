"""
Knowledge Advisor — Ingestion Pipeline (compile-only script)
==============================================================
Builds and compiles a 4-step KFP v2 pipeline: Load -> Chunk -> Embed -> Store.
Run this from inside the knowledge-advisor-workbench; it writes
ingestion_pipeline.yaml which is then imported into the Data Science
Pipelines UI (or uploaded via the KFP client, as done by 04_run_pipeline.py).

All components use the same base image as the workbench itself
(s2i-generic-data-science-notebook:3.5) so no extra pip installs are
required at pipeline-run time (avoids any external network dependency
inside the cluster).

NOTE: inter-component data (documents / chunks / embeddings) is passed via
KFP Dataset ARTIFACTS (files on the pipeline's backing PVC), not via
inline parameters. The embeddings payload (26 chunks x 384-dim floats) is
large enough that passing it as a CLI parameter blows past the container
runtime's argv size limit ("Argument list too long"). Artifacts avoid that
entirely and are the standard KFP v2 pattern for anything beyond small
scalars/short lists.
"""
from kfp import dsl, compiler
from kfp.dsl import Input, Output, Dataset

BASE_IMAGE = "image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/s2i-generic-data-science-notebook:3.5"


@dsl.component(base_image=BASE_IMAGE)
def load_documents(bucket: str, endpoint: str, prefix: str, access_key: str, secret_key: str, docs_out: Output[Dataset]):
    import boto3
    import json

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )
    resp = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
    docs = []
    for obj in resp.get("Contents", []):
        body = s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read().decode("utf-8")
        docs.append({"source": obj["Key"].split("/")[-1], "text": body})
    print(f"Loaded {len(docs)} documents from s3://{bucket}/{prefix}")
    with open(docs_out.path, "w") as f:
        json.dump(docs, f)


@dsl.component(base_image=BASE_IMAGE)
def chunk_documents(docs_in: Input[Dataset], chunks_out: Output[Dataset], max_chars: int = 600):
    import re
    import json

    def chunk_markdown(text, source, max_chars):
        title_match = re.match(r"#\s+(.+)", text.strip())
        title = title_match.group(1).strip() if title_match else source
        sections = re.split(r"\n(?=##\s)", text)
        chunks = []
        for section in sections:
            section = section.strip()
            if not section:
                continue
            header_match = re.match(r"##\s+(.+)", section)
            heading = header_match.group(1).strip() if header_match else None
            if len(section) <= max_chars:
                content = f"{title} — {heading}\n{section}" if heading else section
                chunks.append(content)
                continue
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
        return chunks

    with open(docs_in.path) as f:
        docs = json.load(f)

    all_chunks = []
    for doc in docs:
        for i, c in enumerate(chunk_markdown(doc["text"], doc["source"], max_chars)):
            all_chunks.append({"source": doc["source"], "chunk_index": i, "content": c})
    print(f"Produced {len(all_chunks)} chunks from {len(docs)} documents")
    with open(chunks_out.path, "w") as f:
        json.dump(all_chunks, f)


@dsl.component(base_image=BASE_IMAGE)
def embed_chunks(chunks_in: Input[Dataset], embed_out: Output[Dataset], embed_url: str, embed_model: str):
    import requests
    import json

    with open(chunks_in.path) as f:
        chunks = json.load(f)

    batch = 16
    out = []
    for i in range(0, len(chunks), batch):
        group = chunks[i : i + batch]
        resp = requests.post(
            embed_url,
            json={"model": embed_model, "input": [c["content"] for c in group]},
            timeout=30,
        )
        resp.raise_for_status()
        data = sorted(resp.json()["data"], key=lambda d: d["index"])
        for c, d in zip(group, data):
            out.append({**c, "embedding": d["embedding"]})
    print(f"Embedded {len(out)} chunks")
    with open(embed_out.path, "w") as f:
        json.dump(out, f)


@dsl.component(base_image=BASE_IMAGE)
def store_vectors(embedded_in: Input[Dataset], db_uri: str, embed_dim: int = 384) -> str:
    import psycopg
    import json

    with open(embedded_in.path) as f:
        embedded_chunks = json.load(f)

    conn = psycopg.connect(db_uri)
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS document_chunks (
            id SERIAL PRIMARY KEY,
            source TEXT NOT NULL,
            chunk_index INT NOT NULL,
            content TEXT NOT NULL,
            embedding VECTOR({embed_dim})
        );
        """
    )
    conn.execute("TRUNCATE document_chunks;")
    with conn.cursor() as cur:
        for c in embedded_chunks:
            cur.execute(
                "INSERT INTO document_chunks (source, chunk_index, content, embedding) "
                "VALUES (%s, %s, %s, %s)",
                (c["source"], c["chunk_index"], c["content"], str(c["embedding"])),
            )
    conn.commit()
    conn.execute(
        "CREATE INDEX IF NOT EXISTS document_chunks_embedding_idx "
        "ON document_chunks USING hnsw (embedding vector_cosine_ops);"
    )
    conn.commit()
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM document_chunks;")
        total = cur.fetchone()[0]
    conn.close()
    result = f"Stored {total} chunks in pgvector"
    print(result)
    return result


@dsl.pipeline(
    name="knowledge-advisor-ingestion",
    description="Load company documents from MinIO, chunk them, embed with all-minilm-l6-v2, and store vectors in pgvector.",
)
def ingestion_pipeline(
    bucket: str = "documents",
    endpoint: str = "http://minio.knowledge-advisor.svc.cluster.local:9000",
    prefix: str = "raw/",
    embed_url: str = "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings",
    embed_model: str = "all-minilm-l6-v2",
    db_uri: str = "postgresql://ragadmin:PLACEHOLDER@pgvector-db.knowledge-advisor.svc.cluster.local:5432/ragdb",
    access_key: str = "minioadmin",
    secret_key: str = "PLACEHOLDER",
):
    load_task = load_documents(bucket=bucket, endpoint=endpoint, prefix=prefix, access_key=access_key, secret_key=secret_key)
    chunk_task = chunk_documents(docs_in=load_task.outputs["docs_out"])
    embed_task = embed_chunks(chunks_in=chunk_task.outputs["chunks_out"], embed_url=embed_url, embed_model=embed_model)
    store_vectors(embedded_in=embed_task.outputs["embed_out"], db_uri=db_uri)


if __name__ == "__main__":
    compiler.Compiler().compile(ingestion_pipeline, "/opt/app-root/src/ingestion_pipeline.yaml")
    print("Compiled to /opt/app-root/src/ingestion_pipeline.yaml")
