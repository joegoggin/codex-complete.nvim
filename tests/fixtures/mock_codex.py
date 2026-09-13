#!/usr/bin/env python3
"""Small JSONL app-server double used by the headless Neovim tests."""

import json
import sys
import time


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


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
    elif method == "thread/start":
        send({"id": request_id, "result": {"thread": {"id": "thread-test"}}})
    elif method == "turn/start":
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
