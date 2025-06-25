import os
import json
import boto3
import redis

# Initialize DynamoDB table
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
# Local cache (ElastiCache)
redis_client = redis.Redis(host=os.environ['REDIS_ENDPOINT'], port=6379)


def lambda_handler(event, context):
    body = json.loads(event['body'])
    user_phone = body['user_phone']
    message    = body['message']

    cache_key = f"response:{user_phone}:{message}"
    # Check cache
    cached = redis_client.get(cache_key)
    if cached:
        return {'statusCode': 200, 'body': cached.decode()}

    # Compute route times & wait estimates (placeholder)
    # ... call Waze API, compute wait times, store in DynamoDB ...
    result = { 'eta': 15, 'wait_estimate': 30 }

    # Store in DynamoDB
    table.put_item(Item={
        'user_phone': user_phone,
        'timestamp': int(time.time()),
        'eta': result['eta'],
        'wait_estimate': result['wait_estimate']
    })

    # Cache the response
    redis_client.setex(cache_key, 600, json.dumps(result))

    return { 'statusCode': 200, 'body': json.dumps(result) }
