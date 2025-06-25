import os
import json
import redis
import boto3

# Initialize Redis client
redis_client = redis.Redis(host=os.environ['REDIS_ENDPOINT'], port=6379)
# HTTP client
import requests

TRIGGER_API_URL = os.environ['TRIGGER_API_URL']


def lambda_handler(event, context):
    # Parse incoming webhook payload from EvolutionAPI
    payload = json.loads(event['body'])
    user_phone = payload['from']
    message    = payload['message']

    # Store raw message
    redis_client.rpush(f"messages:{user_phone}", message)

    # Call trigger-api
    resp = requests.post(f"https://{TRIGGER_API_URL}/route_times", json={
        'user_phone': user_phone,
        'message': message
    })

    return {
        'statusCode': resp.status_code,
        'body': resp.text
    }