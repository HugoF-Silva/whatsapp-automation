# lambda-orchestrator/handler.py

import os
import json
import logging
import boto3
import requests
from botocore.exceptions import ClientError

# Setup
logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs      = boto3.client("sqs")
sm       = boto3.client("secretsmanager")
in_q     = os.environ["WHATSAPP_INBOUND_QUEUE_URL"]
out_q    = os.environ["REPLY_OUTBOUND_QUEUE_URL"]
secret_arn = os.environ["GEMINI_SECRET_ARN"]
backend_url = os.environ["BACKEND_API_URL"].rstrip("/")

# Cache secret
def get_gemini_key():
    try:
        resp = sm.get_secret_value(SecretId=secret_arn)
        secret = json.loads(resp["SecretString"])
        return secret["api_key"]
    except ClientError as e:
        logger.error(f"SecretsManager error: {e}")
        raise

GEMINI_KEY = get_gemini_key()

# 1) Classify intent
def classify_with_gemini(text: str):
    prompt = (
        "Classify the user intent into one of: "
        "route_times, all_estimates, annotate. "
        f"Message: \"{text}\""
    )
    url = f"https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:predict?key={GEMINI_KEY}"
    payload = {
        "prompt": {"text": prompt},
        "temperature": 0.0,
        "candidateCount": 1,
    }
    r = requests.post(url, json=payload)
    r.raise_for_status()
    out = r.json()
    choice = out["candidates"][0]["output"].strip()
    # naive parse
    intent = choice.split()[0].lower()
    params = text
    return intent, params

# 2) Call backend if needed
def call_backend(intent: str, params: str):
    if intent == "route_times":
        endpoint = "/route_times"
        data = {"user_message": params}
        r = requests.post(f"{backend_url}{endpoint}", json=data, timeout=10)
        r.raise_for_status()
        return r.json()
    if intent == "all_estimates":
        endpoint = "/all_estimates"
        r = requests.get(f"{backend_url}{endpoint}", timeout=10)
        r.raise_for_status()
        return r.json()
    # annotate should never come from users
    return {}

# 3) Reword result with Gemini
def reword_with_gemini(result: dict):
    prompt = f"Rephrase this as a concise WhatsApp reply:\n\n{json.dumps(result)}"
    url = f"https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:predict?key={GEMINI_KEY}"
    payload = {
        "prompt": {"text": prompt},
        "temperature": 0.2,
        "candidateCount": 1,
    }
    r = requests.post(url, json=payload)
    r.raise_for_status()
    return r.json()["candidates"][0]["output"].strip()

# 4) Build WhatsApp payload
def build_whatsapp_payload(to: str, text: str):
    return {
        "to": to,
        "type": "text",
        "text": {"body": text}
    }

def handler(event, context):
    for rec in event.get("Records", []):
        try:
            body = json.loads(rec["body"])
            # adjust keys to match your EvolutionAPI webhook shape:
            user = body.get("from")
            text = body.get("text", {}).get("body") or body.get("body", "")

            logger.info(f"Received from {user}: {text}")

            intent, params = classify_with_gemini(text)
            logger.info(f"Classified intent={intent}")

            backend_res = call_backend(intent, params) if intent in ("route_times","all_estimates") else {}
            logger.info(f"Backend response: {backend_res}")

            final_text = reword_with_gemini(backend_res or {"message":"Done."})
            logger.info(f"Final reply: {final_text}")

            payload = build_whatsapp_payload(user, final_text)
            sqs.send_message(QueueUrl=out_q, MessageBody=json.dumps(payload))
        except Exception as e:
            logger.exception(f"Error processing record: {e}")
            # Let Lambda retry or send to DLQ
            raise
    return {"status": "ok"}
