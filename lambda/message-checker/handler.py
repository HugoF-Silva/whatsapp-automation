import os
import json
import redis
import requests

from your_classifier_module import IntentionClassifier  # adjust import path

# Environment
REDIS_ENDPOINT   = os.environ['REDIS_ENDPOINT']
TRIGGER_API_URL  = os.environ['TRIGGER_API_URL']

# Clients & classifier (cold start)
# redis_client = redis.Redis(host=REDIS_ENDPOINT, port=6379)
classifier   = IntentionClassifier()

def lambda_handler(event, context):
    # 1. Parse incoming webhook payload
    payload     = json.loads(event['body'])
    user_phone  = payload['from']
    message     = payload['message']

    # 2. Persist raw message
    # redis_client.rpush(f"messages:{user_phone}", message)

    # 3. Classify intent
    try:
        intent_json = classifier.execute(message)  # returns a JSON string
    except Exception as e:
        # In case of LLM errors, capture them as intent
        intent_json = json.dumps({"error": str(e)}, ensure_ascii=False)
    # Store classification
    # redis_client.rpush(f"intents:{user_phone}", intent_json)

    # 4. Forward to trigger-API
    post_body = {
        'user_phone': user_phone,
        'message':    message,
        'intent':     json.loads(intent_json)
    }
    resp = requests.post(
        f"https://{TRIGGER_API_URL}/route_times1",
        json=post_body,
        timeout=5
    )

    return {
        'statusCode': resp.status_code,
        'body':       resp.text
    }
