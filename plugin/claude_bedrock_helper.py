#!/usr/bin/env python3

import argparse
import json
import sys
import boto3
from botocore.exceptions import ClientError

def parse_arguments():
    parser = argparse.ArgumentParser(description="Claude Bedrock Helper")
    parser.add_argument("--region", required=True, help="AWS region")
    parser.add_argument("--model-id", required=True, help="Bedrock model ID")
    parser.add_argument("--messages", required=True, help="JSON-encoded messages")
    parser.add_argument("--system-prompt", required=False, help="System prompt")
    parser.add_argument("--profile", required=False, help="AWS profile name")
    return parser.parse_args()

def create_bedrock_client(region, profile=None):
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    return session.client('bedrock-runtime', region_name=region)

def convert_to_bedrock_format(messages):
    bedrock_messages = []

    for msg in messages:
        if msg['role'] == 'user':
            bedrock_messages.append({"role": "user", "content": [{"text": msg['content']}]})
        elif msg['role'] == 'assistant':
            bedrock_messages.append({"role": "assistant", "content": [{"text": msg['content']}]})

    return bedrock_messages

def invoke_bedrock_model(client, model_id, messages, system_prompt):
    try:
        response = client.converse_stream(
            modelId=model_id,
            messages=messages,
            system=[{"text": system_prompt}] if system_prompt else None,
            inferenceConfig={
                "temperature": 0.7,
                "maxTokens": 2048,
            }
        )
        return response['stream']
    except ClientError as e:
        print(f"Error invoking Bedrock model: {e}", file=sys.stderr)
        sys.exit(1)

def stream_response(stream):
    for event in stream:
        if 'contentBlockDelta' in event:
            in_data = event['contentBlockDelta']
            content_delta_data = {"type": "content_block_delta", "index": in_data['contentBlockIndex'], "delta": {"type": "text_delta", "text": in_data['delta']['text']}}
            print(f"event: content_block_delta")
            print(f"data: {json.dumps(content_delta_data)}")

        elif 'messageStop' in event:
            print("event: message_stop")
            print('data: {"type": "message_stop"}')

        elif 'metadata' in event:
            usage = event['metadata'].get('usage', {})
            message_delta_data = {
                "type": "message_delta",
                "usage": {
                    "input_tokens": usage.get('inputTokens', 0),
                    "output_tokens": usage.get('outputTokens', 0),
                    "total_tokens": usage.get('totalTokens', 0)
                }
            }
            print(f"event: message_delta")
            print(f"data: {json.dumps(message_delta_data)}")
        sys.stdout.flush()

def main():
    args = parse_arguments()

    client = create_bedrock_client(args.region, args.profile)
    messages = json.loads(args.messages)
    bedrock_messages = convert_to_bedrock_format(messages)

    response_stream = invoke_bedrock_model(client, args.model_id, bedrock_messages, args.system_prompt)

    stream_response(response_stream)

if __name__ == "__main__":
    main()
