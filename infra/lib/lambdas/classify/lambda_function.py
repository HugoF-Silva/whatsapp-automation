import os, json, boto3, requests
sqs = boto3.client('sqs')
GEMINI = 'https://api.google.com/gen/v1'
CLASSIFY_Q = os.getenv('CLASSIFY_Q')
def handler(event, ctx):
    for rec in event['Records']:
        body = json.loads(rec['body'])
        text = body['message']
        # Call Gemini
        res = requests.post(GEMINI, json={'prompt': text, 'key': os.getenv('GEMINI_API_KEY')}, timeout=10)
        intent = res.json()['intent']
        # Route to queue
        target_q = {'route_times':os.getenv('ROUTE_Q'), 'postal':os.getenv('POSTAL_Q')}[intent]
        sqs.send_message(QueueUrl=target_q, MessageBody=json.dumps({'user': body['from'], 'data': body}))
