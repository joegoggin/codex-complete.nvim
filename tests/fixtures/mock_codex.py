#!/usr/bin/env python3
"""Small JSONL app-server double used by the headless Neovim tests."""

import json
import sys
import time


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def argument_value(flag):
    try:
        return sys.argv[sys.argv.index(flag) + 1]
    except (ValueError, IndexError):
        return None


def model_matches(params):
    expected = argument_value("--expect-model")
    if expected is not None and params.get("model") != expected:
        return False
    return "--expect-no-model" not in sys.argv or "model" not in params


def effort_matches(params):
    expected = argument_value("--expect-effort")
    return expected is None or params.get("effort") == expected


MODELS = [
    {
        "id": "gpt-5.6-luna",
        "model": "gpt-5.6-luna",
        "displayName": "GPT-5.6-Luna",
        "hidden": False,
        "defaultReasoningEffort": "low",
        "supportedReasoningEfforts": [
            {"reasoningEffort": "low", "description": "Fast"},
            {"reasoningEffort": "medium", "description": "Balanced"},
        ],
        "isDefault": True,
    },
    {
        "id": "gpt-test-fast",
        "model": "gpt-test-fast",
        "displayName": "GPT Test Fast",
        "hidden": False,
        "defaultReasoningEffort": "low",
        "supportedReasoningEfforts": [
            {"reasoningEffort": "low", "description": "Fast"},
        ],
        "isDefault": False,
    },
    {
        "id": "gpt-test-pro",
        "model": "gpt-test-pro",
        "displayName": "GPT Test Pro",
        "hidden": False,
        "defaultReasoningEffort": "high",
        "supportedReasoningEfforts": [
            {"reasoningEffort": "high", "description": "Thorough"},
            {"reasoningEffort": "xhigh", "description": "Most thorough"},
        ],
        "isDefault": False,
    },
    {
        "id": "gpt-test-hidden",
        "model": "gpt-test-hidden",
        "displayName": "GPT Test Hidden",
        "hidden": True,
        "defaultReasoningEffort": "medium",
        "supportedReasoningEfforts": [
            {"reasoningEffort": "medium", "description": "Balanced"},
        ],
        "isDefault": False,
    },
]


for raw_line in sys.stdin:
    message = json.loads(raw_line)
    method = message.get("method")
    request_id = message.get("id")
    params = message.get("params", {})

    if request_id is None:
        continue
    if method == "initialize":
        send({"id": request_id, "result": {"userAgent": "mock-codex"}})
    elif method == "account/read":
        send(
            {
                "id": request_id,
                "result": {
                    "account": {
                        "type": "chatgpt",
                        "email": "test@example.com",
                        "planType": "plus",
                    },
                    "requiresOpenaiAuth": True,
                },
            }
        )
    elif method == "model/list":
        if "--delay-model-list" in sys.argv:
            time.sleep(0.2)
        if "--model-list-error" in sys.argv:
            send(
                {
                    "id": request_id,
                    "error": {"code": -32000, "message": "mock model list failure"},
                }
            )
        elif "--malformed-model-list" in sys.argv:
            send({"id": request_id, "result": {"data": "invalid"}})
        elif "--malformed-effort-list" in sys.argv:
            model = dict(MODELS[0])
            model["supportedReasoningEfforts"] = []
            send({"id": request_id, "result": {"data": [model], "nextCursor": None}})
        elif params.get("cursor") == "models-page-2":
            final_models = MODELS[2:] if params.get("includeHidden") else MODELS[2:3]
            send({"id": request_id, "result": {"data": final_models, "nextCursor": None}})
        else:
            send(
                {
                    "id": request_id,
                    "result": {"data": MODELS[:2], "nextCursor": "models-page-2"},
                }
            )
    elif method == "thread/start":
        if model_matches(params):
            send({"id": request_id, "result": {"thread": {"id": "thread-test"}}})
        else:
            send(
                {
                    "id": request_id,
                    "error": {"code": -32000, "message": "unexpected thread model"},
                }
            )
    elif method == "turn/start":
        if not model_matches(params) or not effort_matches(params):
            send(
                {
                    "id": request_id,
                    "error": {"code": -32000, "message": "unexpected turn model"},
                }
            )
            continue
        if not effort_matches(params):
            send(
                {
                    "id": request_id,
                    "error": {"code": -32000, "message": "unexpected turn effort"},
                }
            )
            continue
        if "--turn-error" in sys.argv:
            send(
                {
                    "id": request_id,
                    "error": {"code": -32000, "message": "mock turn failure"},
                }
            )
            continue
        if "--hang" in sys.argv:
            time.sleep(2)
        if "--delay" in sys.argv:
            time.sleep(0.2)
        send(
            {
                "id": request_id,
                "result": {"turn": {"id": "turn-test", "status": "inProgress"}},
            }
        )
        send(
            {
                "method": "item/completed",
                "params": {
                    "threadId": params["threadId"],
                    "item": {
                        "type": "agentMessage",
                        "text": '{"completion":" world\\nnext_line()"}',
                    },
                },
            }
        )
        send(
            {
                "method": "turn/completed",
                "params": {
                    "threadId": params["threadId"],
                    "turn": {"id": "turn-test", "status": "completed"},
                },
            }
        )
    elif method == "turn/interrupt":
        send({"id": request_id, "result": {}})
    else:
        send(
            {
                "id": request_id,
                "error": {"code": -32601, "message": "unsupported in mock"},
            }
        )
