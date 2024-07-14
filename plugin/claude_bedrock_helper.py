#!/usr/bin/env python3
#
# Translating AWS Bedrock API to the Claude API to enable (Streaming) Claude API
# code to work seamlessly on AWS Bedrock.
#
# (c) Petr Baudis <pasky@ucw.cz>, MIT licence.

import argparse
import json
import sys
import boto3
from botocore.exceptions import ClientError

def parse_arguments():
    parser = argparse.ArgumentParser(description="AWS Bedrock Claude API provider")
    parser.add_argument("--region", required=True, help="AWS region")
    parser.add_argument("--model-id", required=True, help="Bedrock model ID")
    parser.add_argument("--messages", required=True, help="JSON-encoded messages")
    parser.add_argument("--system-prompt", required=False, help="System prompt")
    parser.add_argument("--profile", required=False, help="AWS profile name")
    parser.add_argument("--tools", required=False, help="JSON-encoded tools configuration")
    return parser.parse_args()

def create_bedrock_client(region, profile=None):
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    return session.client('bedrock-runtime', region_name=region)

def convert_to_bedrock_tool_format(claude_tools):
    bedrock_tools = {
        "tools": [
            {
                "toolSpec": {
                    "name": tool["name"],
                    "description": tool["description"],
                    "inputSchema": {
                        "json": tool["input_schema"]
                    }
                }
            }
            for tool in claude_tools
        ]
    }
    return bedrock_tools

def convert_from_bedrock_tool_format(bedrock_tool_call):
    result = {
        "type": "tool_use",
        "id": bedrock_tool_call.get("toolUseId", ""),
        "name": bedrock_tool_call.get("name", ""),
        "input": bedrock_tool_call.get("input", {})
    }
    return result

def convert_to_bedrock_format(messages, tools=None):
    bedrock_messages = []

    for msg in messages:
        content = msg["content"]
        # print(f"DEBUG: tool_result: {content}", file=sys.stderr)
        if not isinstance(content, list):
            content = [{"type": "text", "text": content}]

        bedrock_content = []
        for content_one in content:
            if content_one['type'] == 'text':
                bedrock_content.append({"text": content_one['text']})
            elif content_one['type'] == 'tool_use':
                bedrock_content.append({"toolUse": {
                            "toolUseId": content_one["id"],
                            "name": content_one["name"],
                            "input": content_one["input"],
                        }})
            elif content_one['type'] == 'tool_result':
                bedrock_content.append({"toolResult": {
                            "toolUseId": content_one["tool_use_id"],
                            "content": [{"text": content_one["content"]}],
                        }})

        bedrock_messages.append({"role": msg["role"], "content": bedrock_content})

    return bedrock_messages

def invoke_bedrock_model(client, model_id, messages, system_prompt, tools=None):
    try:
        request = {
            "modelId": model_id,
            "messages": messages,
            "system": [{"text": system_prompt}] if system_prompt else None,
            "inferenceConfig": {
                "temperature": 0.7,
                "maxTokens": 2048,
            }
        }

        if tools:
            request["toolConfig"] = convert_to_bedrock_tool_format(tools)

        response = client.converse_stream(**request)
        return response['stream']
    except ClientError as e:
        print(f"Error invoking Bedrock model: {e}", file=sys.stderr)
        sys.exit(1)

def stream_response(stream):
    for event in stream:
        # print(f"DEBUG: event: {event}", file=sys.stderr)
        if 'contentBlockStart' in event:
            in_data = event['contentBlockStart']
            print(f"event: content_block_start")
            tool_call = convert_from_bedrock_tool_format(in_data['start']['toolUse'])
            print(f"data: {json.dumps({'type': 'content_block_start', 'content_block_index': in_data['contentBlockIndex'], 'content_block': tool_call})}")

        elif 'contentBlockDelta' in event:
            in_data = event['contentBlockDelta']
            content_delta_data = {"type": "content_block_delta", "index": in_data['contentBlockIndex']}
            if 'toolUse' in in_data['delta']:
                content_delta_data["delta"] = {"type": "input_json_delta", "partial_json": in_data['delta']['toolUse']['input']}
            else:
                content_delta_data["delta"] = {"type": "text_delta", "text": in_data['delta']['text']}
            print(f"event: content_block_delta")
            print(f"data: {json.dumps(content_delta_data)}")

        elif 'contentBlockStop' in event:
            print("event: content_block_stop")
            content_stop_data = {"type": "content_block_stop", "content_block_index": event["contentBlockStop"]["contentBlockIndex"]}
            print(f"data: {json.dumps(content_stop_data)}")

        elif 'messageStop' in event:  # and event['messageStop']['stopReason'] != 'tool_use':
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
        else:
            if False:
                print(f"WARNING: Unexpected event: {event}", file=sys.stderr)
        sys.stdout.flush()

def main():
    args = parse_arguments()

    client = create_bedrock_client(args.region, args.profile)
    messages = json.loads(args.messages)
    tools = json.loads(args.tools) if args.tools else None
    bedrock_messages = convert_to_bedrock_format(messages)

    response_stream = invoke_bedrock_model(client, args.model_id, bedrock_messages, args.system_prompt, tools)

    stream_response(response_stream)

if __name__ == "__main__":
    main()
