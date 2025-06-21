import * as cdk from 'aws-cdk-lib';
import { Stack, StackProps, Duration } from 'aws-cdk-lib';
import { Queue } from 'aws-cdk-lib/aws-sqs';
import { Table, AttributeType, BillingMode } from 'aws-cdk-lib/aws-dynamodb';
import { Function, Runtime, Code, EventSourceMapping } from 'aws-cdk-lib/aws-lambda';
import { SqsEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import { LambdaRestApi, AuthorizationType } from 'aws-cdk-lib/aws-apigateway';
import { Construct } from 'constructs';

export class InfraStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // 1. Queues
    const inboundQ  = new Queue(this, 'InboundQueue');
    const classifyQ = new Queue(this, 'ClassifyQueue');
    const routeQ    = new Queue(this, 'RouteQueue');
    const postalQ   = new Queue(this, 'PostalQueue');
    const replyQ    = new Queue(this, 'ReplyQueue');

    // 2. DynamoDB
    const db = new Table(this, 'Records', {
      partitionKey: { name: 'pk', type: AttributeType.STRING },
      sortKey:      { name: 'sk', type: AttributeType.STRING },
      billingMode:  BillingMode.PAY_PER_REQUEST,
    });

    // 3. Lambdas
    const classifyFn = new Function(this, 'ClassifyFn', {
      runtime:     Runtime.PYTHON_3_11,
      handler:     'lambda_function.handler',
      code:        Code.fromAsset('lib/lambdas/classify'),
      timeout:     Duration.seconds(15),
      environment:{
        INBOUND_Q:    inboundQ.queueName,
        CLASSIFY_Q:   classifyQ.queueName,
        GEMINI_API_KEY: process.env.GEMINI_API_KEY!,
      }
    });
    inboundQ.grantConsumeMessages(classifyFn);
    classifyQ.grantSendMessages(classifyFn);

    const routeFn = new Function(this, 'RouteFn', {
      runtime: Runtime.PYTHON_3_11,
      handler: 'lambda_function.handler',
      code:    Code.fromAsset('lib/lambdas/route_times'),
      environment:{ QUEUE_URL: replyQ.queueUrl, TABLE_NAME: db.tableName }
    });
    classifyQ.grantConsumeMessages(routeFn);
    replyQ.grantSendMessages(routeFn);
    db.grantReadWriteData(routeFn);

    const postalFn = new Function(this, 'PostalFn', {
      runtime: Runtime.PYTHON_3_11,
      handler: 'lambda_function.handler',
      code:    Code.fromAsset('lib/lambdas/postal_lookup'),
      environment:{ QUEUE_URL: replyQ.queueUrl, TABLE_NAME: db.tableName }
    });
    classifyQ.grantConsumeMessages(postalFn);
    replyQ.grantSendMessages(postalFn);
    db.grantReadWriteData(postalFn);

    // 4. Attach SQS triggers
    classifyFn.addEventSource(new SqsEventSource(inboundQ));
    routeFn.addEventSource(new SqsEventSource(routeQ));
    postalFn.addEventSource(new SqsEventSource(postalQ));

    // 5. API Gateway for read endpoints & admin annotate
    const api = new LambdaRestApi(this, 'ApiGateway', {
      restApiName: 'WhatsAppService',
      handler: new Function(this, 'ApiHandler', {
        runtime: Runtime.NODEJS_18_X,
        handler: 'index.handler',
        code: Code.fromAsset('lib/lambdas/api'),
        environment: { TABLE: db.tableName }
      }),
      defaultMethodOptions: { authorizationType: AuthorizationType.NONE }
    });
    db.grantReadWriteData(api.node.findChild('ApiHandler') as Function);

    // 6. Reply sender Lambda (pulled by container, optional)
    const replyFn = new Function(this, 'ReplyFn', {
      runtime: Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code:    Code.fromAsset('lib/lambdas/reply_sender'),
      environment: { QUEUE_URL: replyQ.queueUrl, EVOLUTION_API_URL: process.env.EVOLUTION_URL! }
    });
    replyQ.grantConsumeMessages(replyFn);
  }
}
