Goal: to launch a simple aws application with auto-scaling

### My application is:
- WhatsApp chatbot for a city.

### How the user interacts with it:
- Save phone number
- Send message
- Gets answer

### How the application CURRENTLY works
- So far, only as MVP
* Users can send message to my whatsapp number (eSIM),
* there's an unnoficial whatsapp api (a api built over WhiskeySockets/Baileys) deployed with easypanel in my hostinger kvm, it is called EvolutionAPI.
* EvolutionAPI is linked to my whatsapp number, so it receives what the number receives
* a webhook base64 (created with n8n) is set at evolotion api so it listens to some whatsapp events. events which are classified by evolutionapi
* the webhook send the evolutionapi filtered events to my n8n workflow (since it is a n8n webhook)
* the n8n workflow make calls to a third party postal code api or to my aws ECS service (the request classified which must be done is based on what was the user message)
* the user message is natural language, so I use a Gemini (third party google api) to classify what the user message is about
* the third party postal code api is called from n8n directly if the user message is their postal code.
* my ECS service launched with fargate launchtype sits behind an EC2 ALB (which I'm not sure if it is properly configured)
* the ECS service is a single container with some endpoints, all built with FastAPI (python)
* there are 4 (four) main endpoints: @app.post("/annotate"), @app.get("/all_estimates", response_model=AllEstimatesResponse), @app.post("/route_times"), @app.get("/route_times/{user_phone}", response_model=RouteTimeResponse), 
* @app.post("/annotate") and @app.post("/route_times") insert data into Dynamo DB
* @app.get("/all_estimates", response_model=AllEstimatesResponse) and @app.get("/route_times/{user_phone} scans Dynamo DB (fetch data)
* user messages can only trigger @app.post("/route_times"), @app.get("/route_times/{user_phone}, or @app.get("/all_estimates", response_model=AllEstimatesResponse) 
* @app.post("/annotate") can be only triggered by a data annotator user (admin user).
* there aren't a lot of admin users, so I'm not worried about auto scaling the vercel app which runs the frontend through where the admin users can annotate.
* @app.post("/route_times") uses WazeRouterCalculator to estimate user travel time (from user location to a health center unit), and store this info at dynamo table
* @app.get("/route_times/{user_phone} fetch data (scanning it), and return the user travel time
* @app.get("/all_estimates", response_model=AllEstimatesResponse) fetch data based on different filters (there are multiple fetches which are done), and run an algorithm to estimate wait time in nearby health center units based temporal data of these units.
* temporal data is stored through @app.post("/annotate"), which has info about wait time of a patient in a given circumstance of a day time.
* domain were bought through hostinger but they are currently registered in cloudflare, there's a subdomain for n8n, for evolution api, for easy panel and for the api already as ecs service.
 

### Simple overview of how it currently is 
- Let's call the ECS service already deployed as trigger-api
- EvolutionAPI listen to what happens to number
- N8N webhook is set at EvolutionAPI, so anything that happens to number is redirected to N8N workflow
- Gemini node classifies user intent
- Stores user message through Redis node
- Based on what the user intent was, triggers a certain trigger-api endpoint.
- Based on response, Gemini answers user.


### How the second version must be
- No more VPS.
- No more EasyPanel
- No more N8N.
- EvolutionAPI as ECS service and as Api Gateway, it doesn't need to auto scale. 
- Gemini with LangGraph implemented in Lambda (let's call it message-checker).
- message-checker listen EvolutionAPI.
- message is stored in Redis - Target tracking auto scale.
- based on message, request trigger-api endpoint.
- Trigger-api is now another Lambda too.
- AWS Dynamo DB keeps the same.
- Trigger-api answer is stored in an external cache (TTL 10 minutes) so if anoter message-checker process call trigger lambda, it will get from cache if available (so trigger doesn't need to process it again, avoiding slow).


### What you must do
- Define infrastructure ensuring github actions is used
- Make the repository with EvolutionAPI
- Make it simple

### What you should know
- EvolutionAPI docker-compose has Redis image as service too.