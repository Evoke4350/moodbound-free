#!/usr/bin/env python3
"""
Smoke test for Moodbound's NVC rephraser pipeline on AWS:
1) Bedrock streaming rephrase (cheap non-Anthropic model by default).

Usage:
  export AWS_BEARER_TOKEN_BEDROCK=...
  python3 Scripts/bedrock_nvc_stream_test.py \
    --text "You never listen to me."
"""

from __future__ import annotations

import argparse
import os
import sys

import boto3
from botocore.config import Config


SYSTEM_PROMPT = (
    "You are an NVC rephraser. Rewrite user text using this structure: "
    "Observation, Feeling, Need, Request. "
    "Keep original intent, reduce blame, be concise, and avoid diagnosis."
)


def build_clients(region: str):
    cfg = Config(connect_timeout=3600, read_timeout=3600)
    bedrock = boto3.client("bedrock-runtime", region_name=region, config=cfg)
    return bedrock


def stream_rephrase(bedrock, model_id: str, user_text: str) -> str:
    response = bedrock.converse_stream(
        modelId=model_id,
        messages=[
            {
                "role": "user",
                "content": [{"text": user_text}],
            }
        ],
        system=[{"text": SYSTEM_PROMPT}],
        inferenceConfig={
            "maxTokens": 320,
            "temperature": 0.2,
            "topP": 0.9,
        },
    )

    out = []
    print("Streaming NVC rephrase:")
    for event in response["stream"]:
        if "contentBlockDelta" in event:
            delta = event["contentBlockDelta"]["delta"]
            text = delta.get("text")
            if text:
                out.append(text)
                print(text, end="", flush=True)
    print()
    return "".join(out).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Bedrock NVC streaming smoke test.")
    parser.add_argument("--text", required=True, help="Input text to rephrase.")
    parser.add_argument("--region", default="us-east-1", help="AWS region.")
    parser.add_argument(
        "--model-id",
        default="us.amazon.nova-2-lite-v1:0",
        help="Bedrock model ID (cheap non-Anthropic default).",
    )
    args = parser.parse_args()

    # Bedrock API-key auth path expects this env var.
    if not os.getenv("AWS_BEARER_TOKEN_BEDROCK"):
        print("ERROR: AWS_BEARER_TOKEN_BEDROCK is not set.", file=sys.stderr)
        return 2

    bedrock = build_clients(args.region)
    rewritten = stream_rephrase(bedrock, args.model_id, args.text)
    if not rewritten:
        print("ERROR: empty model output.", file=sys.stderr)
        return 3

    print("\nFinal rewritten text:\n")
    print(rewritten)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
