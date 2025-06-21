import os
import json
import logging
import boto3
import requests
from botocore.exceptions import ClientError

# Initialize clients outside handler for connection reuse
dynamo = boto3.resource('dynamodb')
sqs    = boto3.client('sqs')

TABLE_NAME    = os.environ['TABLE_NAME']
REPLY_QUEUE   = os.environ['QUEUE_URL']
POSTAL_API    = os.environ['POSTAL_API_URL']  # e.g. "https://api.zippopotam.us/us/{}"

table = dynamo.Table(TABLE_NAME)
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    for record in event.get('Records', []):
        try:
            body = json.loads(record['body'])
            user = body['user']
            postal = body['data'].get('postal_code')
            if not postal:
                raise ValueError("No postal_code in message")

            # 1. Call external postal code API
            resp = requests.get(POSTAL_API.format(postal), timeout=5)
            resp.raise_for_status()
            data = resp.json()

            # 2. Persist lookup result
            item = {
                'pk': f"postal#{user}",
                'sk': f"{postal}#{context.aws_request_id}",
                'data': data
            }
            table.put_item(Item=item)

            # 3. Enqueue WhatsApp reply
            message = {
                'to':   user,
                'text': f"Postal info for {postal}: {data.get('places', [{}])[0].get('place name','N/A')}, {data.get('country','N/A')}"
            }
            sqs.send_message(
                QueueUrl=REPLY_QUEUE,
                MessageBody=json.dumps(message)
            )
            logger.info(f"Processed postal {postal} for {user}")

        except (requests.RequestException, ClientError, ValueError) as e:
            logger.error(f"Error processing record {record}: {e}", exc_info=True)
            # Optionally: send an error reply or push to DLQ via SQS config
