import os
import json
import logging
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

EVOLUTION_API_URL = os.environ['EVOLUTION_API_URL'].rstrip('/')

def handler(event, context):
    for record in event.get('Records', []):
        try:
            # Message format: {'to': 'whatsapp_number', 'text': 'message to send'}
            message = json.loads(record['body'])
            to   = message['to']
            text = message['text']
            payload = {'to': to, 'text': text}
            url = f"{EVOLUTION_API_URL}/send"

            logger.info(f"Sending to {to}: {text}")

            r = requests.post(url, json=payload, timeout=5)
            r.raise_for_status()

            if r.status_code == 429:
                logger.warning(f"Rate limit from EvolutionAPI when sending to {to}. Message will retry.")
                raise Exception("Rate limited (429)")

            logger.info(f"Successfully sent to {to}")

        except Exception as e:
            logger.error(f"Failed to send message: {e}", exc_info=True)
            # If any error, do not delete from SQS. Lambda will automatically retry.
            # For permanent failures after maxReceiveCount, message will go to DLQ if configured.
            raise

# (No explicit SQS delete needed; Lambda + SQS event integration handles it.)
