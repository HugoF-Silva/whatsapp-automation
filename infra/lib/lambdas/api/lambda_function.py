import os
import json
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamo = boto3.resource('dynamodb')
TABLE_NAME = os.environ['TABLE_NAME']
table = dynamo.Table(TABLE_NAME)

def handler(event, context):
    method = event['httpMethod']
    path   = event['resource']    # e.g. "/route_times/{user_phone}"
    params = event.get('pathParameters') or {}
    body   = json.loads(event.get('body') or '{}')

    try:
        if method == 'GET' and path == '/route_times/{user_phone}':
            return get_route_times(params['user_phone'])

        if method == 'GET' and path == '/all_estimates':
            # implement your custom filters via queryStringParameters
            filters = event.get('queryStringParameters') or {}
            return get_all_estimates(filters)

        if method == 'POST' and path == '/annotate':
            return post_annotate(body)

        return response(404, {"error": "Not Found"})
    except Exception as e:
        logger.error(f"API error: {e}", exc_info=True)
        return response(500, {"error": "Internal Server Error"})

def get_route_times(user_phone):
    # Query for items with pk="route#<user_phone>"
    key = f"route#{user_phone}"
    resp = table.query(
        KeyConditionExpression="pk = :pk",
        ExpressionAttributeValues={":pk": key}
    )
    return response(200, {"items": resp.get('Items', [])})

def get_all_estimates(filters):
    # Simplest: scan whole table—it’s on-demand mode, so it's okay for moderate volume.
    # Or apply filters if you have GSIs.
    scan_kwargs = {}
    for k, v in filters.items():
        # example filter on sk prefix
        scan_kwargs.setdefault('ExpressionAttributeValues', {})[f":{k}"] = v
        scan_kwargs['FilterExpression'] = f"contains({k}, :{k})"
    resp = table.scan(**scan_kwargs) if scan_kwargs else table.scan()
    # Here you’d run your custom algo on resp['Items']
    estimates = your_estimation_algorithm(resp['Items'])
    return response(200, {"estimates": estimates})

def post_annotate(data):
    # data must include: user_phone, timestamp, wait_time, etc.
    timestamp = data.get('timestamp') or datetime.utcnow().isoformat()
    item = {
        'pk': f"annotate#{data['user_phone']}",
        'sk': timestamp,
        'wait_time': data['wait_time'],
        'metadata': data.get('metadata', {})
    }
    table.put_item(Item=item)
    return response(201, {"status": "ok"})

def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }

def your_estimation_algorithm(items):
    # placeholder: group by center, average wait_time, etc.
    centers = {}
    for it in items:
        c = it['metadata'].get('center_id','unknown')
        centers.setdefault(c, []).append(it['wait_time'])
    return [
        {"center_id": c, "avg_wait": sum(ws)/len(ws)}
        for c, ws in centers.items()
    ]
