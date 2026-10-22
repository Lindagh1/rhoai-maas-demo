"""Import the compiled ingestion pipeline into the knowledge-advisor Data
Science Pipeline server and launch a real run."""
import os
import time

import kfp

KFP_HOST = "https://ds-pipeline-dspa.knowledge-advisor.svc.cluster.local:8443"


def get_token():
    with open("/var/run/secrets/kubernetes.io/serviceaccount/token") as f:
        return f.read().strip()


def main():
    client = kfp.Client(host=KFP_HOST, existing_token=get_token(), verify_ssl=False)

    pipeline_name = "knowledge-advisor-ingestion"
    pipeline_id = None
    for p in client.list_pipelines(page_size=50).pipelines or []:
        if p.display_name == pipeline_name:
            pipeline_id = p.pipeline_id
            break
    if pipeline_id:
        print(f"Pipeline '{pipeline_name}' already exists: {pipeline_id}")
    else:
        upload = client.upload_pipeline(
            pipeline_package_path="/opt/app-root/src/ingestion_pipeline.yaml",
            pipeline_name=pipeline_name,
            description="Load company documents from MinIO, chunk, embed with all-minilm-l6-v2, store vectors in pgvector.",
        )
        pipeline_id = upload.pipeline_id
        print(f"Uploaded pipeline: {pipeline_id}")

    db_uri = os.environ["URI"]
    run = client.create_run_from_pipeline_package(
        pipeline_file="/opt/app-root/src/ingestion_pipeline.yaml",
        arguments={
            "bucket": "documents",
            "endpoint": "http://minio.knowledge-advisor.svc.cluster.local:9000",
            "prefix": "raw/",
            "embed_url": "http://all-minilm-l6-v2-predictor.my-first-model.svc.cluster.local:8080/v1/embeddings",
            "embed_model": "all-minilm-l6-v2",
            "db_uri": db_uri,
            "access_key": os.environ["AWS_ACCESS_KEY_ID"],
            "secret_key": os.environ["AWS_SECRET_ACCESS_KEY"],
        },
        run_name="knowledge-advisor-ingestion-run",
        experiment_name="knowledge-advisor",
    )
    print(f"Started run: {run.run_id}")

    # Poll for completion
    for _ in range(60):
        status = client.get_run(run.run_id)
        state = status.state
        print(f"  run state: {state}")
        if state in ("SUCCEEDED", "FAILED", "ERROR", "SKIPPED"):
            break
        time.sleep(5)

    print(f"FINAL STATE: {state}")


if __name__ == "__main__":
    main()
