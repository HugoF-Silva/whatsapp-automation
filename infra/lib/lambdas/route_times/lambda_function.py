import os, json, boto3
from WazeRouteCalculator import WazeRouteCalculator
dynamo = boto3.resource('dynamodb').Table(os.getenv('TABLE_NAME'))
sqs   = boto3.client('sqs')
def handler(event, ctx):
    for r in event['Records']:
        msg = json.loads(r['body'])
        loc = msg['data']['location']
        est = WazeRouteCalculator.WazeRouteCalculator(loc['lat'], loc['lon'], HEALTH_CENTER).calc_route_info()
        # Persist
        dynamo.put_item(Item={'pk':msg['user'],'sk':'route#'+str(ctx.aws_request_id),'eta':est})
        # Enqueue reply
        sqs.send_message(QueueUrl=os.getenv('QUEUE_URL'),
            MessageBody=json.dumps({'to':msg['user'],'text':f"ETA is {est}"}))
