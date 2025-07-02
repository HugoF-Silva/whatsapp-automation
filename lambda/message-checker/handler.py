import os
import json
import urllib3
import re
from gemini import IntentionClassifier, AnswerMan, UnderstandableWaitTime  # adjust import path
from datetime import datetime, timedelta
import time
import logging
import boto3
from botocore.exceptions import ClientError
import hashlib
from upstash_redis import Redis
import base64

logger = logging.getLogger()
logger.setLevel(logging.INFO)

http = urllib3.PoolManager()

# Environment
EVO_API_URL = os.getenv("EVO_API_URL")
TRIGGER_API_URL  = os.getenv('TRIGGER_API_URL')
r = Redis.from_env()

def save_interaction(user_id: str, user_message: str, llm_answer: str, ttl: int = 14400) -> None:
    key = f"chat:{user_id}"
    pair = {"usuário": user_message, "você": llm_answer}
    r.lpush(key, json.dumps(pair))
    r.ltrim(key, 0, 14)  # Keep only the last 20 pairs (adjust as needed)
    r.expire(key, ttl) # 4h

def get_recent_history(user_id: str, limit: int = 3) -> list[dict]:
    key = f"chat:{user_id}"
    # Get last N items (most recent first)
    history_jsons = r.lrange(key, 0, limit - 1)
    # Convert back to Python dict
    lst = [json.loads(jso) for jso in history_jsons]
    return lst

def hash_pseudonym(pseudonym: str, salt: str) -> str:
    # Combine pseudonym and salt, encode, hash
    to_hash = f"{salt}{pseudonym}".encode("utf-8")
    return hashlib.sha256(to_hash).hexdigest()

def get_secret(secret_name: str):
    region_name = "us-east-1"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    secret = get_secret_value_response['SecretString']
    return json.loads(secret)


def merge_estimates_and_routes(all_estimates_obj, route_times_obj):
    # Map travel times by unit
    travel_time_by_unit = {
        rt['unit']: round(float(rt['travel_time_min']))
        for rt in route_times_obj
    }

    # List of units to exclude
    excluded_units = [
        "CAIS Cândida de Morais",
        "UPA Região Noroeste",
        "Cais Finsocial"
    ]

    # Filter and merge estimates
    merged = [
        {
            "unit": est['unit'],
            "travel_plus_green": round(est['green'] + travel_time_by_unit[est['unit']] + 10)
        }
        for est in all_estimates_obj['estimates']
        if est['unit'] in travel_time_by_unit and est['unit'] not in excluded_units
    ]

    # Sort by 'travel_plus_green'
    merged.sort(key=lambda x: x['travel_plus_green'])
    return merged

def lambda_handler(event, context):
    logger.info("Lambda started processing event: %s", event)
    logger.info("Lambda context: %s", context)
    event_body = json.loads(event['body'])
    
    date_time_string = event_body['date_time']

    date_time_string = '2025-07-01T17:05:10.891Z'
    date_time_string = date_time_string.rstrip('Z')  # Remove the 'Z'
    date_obj = datetime.fromisoformat(date_time_string)
    hour_int = date_obj.hour
    logger.info("Hours: %d", hour_int)

    if (hour_int < 5) or (hour_int >= 21):
        preset = "Não calculo tempo de espera entre 21:00 ~ 05:00, nem finais de semana...                                                                                    Um segredo que só quem é da comunidade Menos Tempo sabe: *eu conseguiria* se você dissesse que quer a Menos Tempo oficialmente pelo link bit.ly/quero-oficialmente 🤏 (não conta pra ninguém, é exclusivo 🤫)"
        logger.info("Entered preset clause")
        return preset
    
    type = event_body['data']['messageType']
    user_phone = event_body['data']['messageType']
    secret = get_secret("pseodonym/salt")['SALT']
    cripto_number = hash_pseudonym(user_phone, secret)

    history = get_recent_history(f"{cripto_number}", 3)
    content = ""
    if history:
        content = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history}
"""            
    classifier = IntentionClassifier(history=content)

    if (type == "conversation"):
        try:
            message = event_body['data']['message']['conversation']
            
            # Check message length
            if len(message) > 160000:
                raise Exception("Message too long = possible crash attempt")

            # Check for excessive emojis or special characters (zero-width & formatting)
            special_chars = re.compile(r'[\u200B-\u200D\uFEFF]')
            if len(special_chars.findall(message)) > 100:
                raise Exception("Suspicious number of formatting characters")

            # Optional: Detect Zalgo (overuse of diacritics)
            zalgo = re.compile(r'[\u0300-\u036f]{3,}')
            if zalgo.search(message):
                raise Exception("Zalgo-like text detected")
                            
        except:
            pass
            # block number with evo api

        pattern = r'^\d{5}-?\d{3}$'
        if re.match(pattern, message): # if cep
            clean_cep = message.replace("-", "")
            resp = http.request(method="GET", url=f"https://www.cepaberto.com/api/v3/cep?cep={clean_cep}", headers={"Authorization":"Token token=bf2a40be4391c25294e40a44317123a7"})
            resp_data = json.loads(resp.data)
            if (latitude:=resp_data.get("latitude", None)) and (longitude:=resp_data.get("longitude", None)):
                body = json.dumps({ "user_phone": user_phone, "latitude": latitude, "longitude": longitude }).encode('utf-8')
                print(f"TRIGGER_API_URL: {TRIGGER_API_URL}")
                # resp = http.request("POST", url=f"{TRIGGER_API_URL}/route_times", body=body, timeout=30)
                resp = {"message":"Route times stored."}
                resp_data = resp['message']
                # resp_data = json.loads(resp.data)
                if resp_data == "Route times stored.":
                    time.sleep(1)
                    # resp = http.request(url=f"{TRIGGER_API_URL}/route_times/{user_phone}", timeout=20)
                    resp = {"data": {"user_phone":"556296504306@s.whatsapp.net","results":[{"unit":"CAIS Cândida de Morais","travel_time_min":"29.216666666666665","timestamp":"2025-07-02T16:22:43.082107+00:00"},{"unit":"CIAMS Urias Magalhães","travel_time_min":"15.933333333333334","timestamp":"2025-07-02T16:22:43.082139+00:00"},{"unit":"Cais Finsocial","travel_time_min":"34.916666666666664","timestamp":"2025-07-02T16:22:43.082146+00:00"},{"unit":"UPA Campinas","travel_time_min":"19.616666666666667","timestamp":"2025-07-02T16:22:43.082152+00:00"},{"unit":"UPA Região Noroeste","travel_time_min":"32.95","timestamp":"2025-07-02T16:22:43.082131+00:00"}]}}
                    # resp = {"data": """{"user_phone":"556296504306@s.whatsapp.net","results":[{"unit":"CAIS Cândida de Morais","travel_time_min":"29.216666666666665","timestamp":"2025-07-02T16:22:43.082107+00:00"},{"unit":"CIAMS Urias Magalhães","travel_time_min":"15.933333333333334","timestamp":"2025-07-02T16:22:43.082139+00:00"},{"unit":"Cais Finsocial","travel_time_min":"34.916666666666664","timestamp":"2025-07-02T16:22:43.082146+00:00"},{"unit":"UPA Campinas","travel_time_min":"19.616666666666667","timestamp":"2025-07-02T16:22:43.082152+00:00"},{"unit":"UPA Região Noroeste","travel_time_min":"32.95","timestamp":"2025-07-02T16:22:43.082131+00:00"}]}"""}
                    if not resp['data']:
                        behind_the_courtains = "O USUÁRIO NÃO FORNECEU LOCALIZAÇÃO (OU CEP), E PORTANTO NÃO CONSEGUIMOS CALCALCULAR O TEMPO TOTAL A SER GASTO (O SISTEMA CALCULA A PARTIR DO PONTO DE PARTIDA, O QUAL É POSSÍVEL SER IDENTIFICADO A PARTIR DA LOCALIZAÇÃO OU DO CEP)."
                        classificacao = "erro"
                        history1 = get_recent_history(f"1_{cripto_number}", 3)
                        content1 = ""
                        if history1:
                            content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
                        answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
                        mensagem = answerman.execute(message)
                        save_interaction(f"1_{cripto_number}", message, mensagem)

                    else:
                        mensagem = estimate(date_time_string, cripto_number, message, resp)

                else:
                    behind_the_courtains = "ERRO DE ENVIO DE LOCALIZAÇÃO"
                    classificacao = "erro"

                    history1 = get_recent_history(f"1_{cripto_number}", 3)
                    content1 = ""
                    if history1:
                        content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
                    answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
                    mensagem = answerman.execute(message)
                    save_interaction(f"1_{cripto_number}", message, mensagem)
            else:
                behind_the_courtains = "ERRO DE ENVIO DE LOCALIZAÇÃO"
                classificacao = "erro"
                history1 = get_recent_history(f"1_{cripto_number}", 3)
                content1 = ""
                if history1:
                    content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
                answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
                mensagem = answerman.execute(message)
        else: # not cep
            intent_json = classifier.execute(message)
            save_interaction(f"{cripto_number}", message, json.dumps(intent_json))
            if intent_json['classificacao'] == "tempo":
                # resp = http.request("GET", url=f"{TRIGGER_API_URL}/route_times/{user_phone}", timeout=20)
                resp = {"data": {"user_phone":"556296504306@s.whatsapp.net","results":[{"unit":"CAIS Cândida de Morais","travel_time_min":"29.216666666666665","timestamp":"2025-07-02T16:22:43.082107+00:00"},{"unit":"CIAMS Urias Magalhães","travel_time_min":"15.933333333333334","timestamp":"2025-07-02T16:22:43.082139+00:00"},{"unit":"Cais Finsocial","travel_time_min":"34.916666666666664","timestamp":"2025-07-02T16:22:43.082146+00:00"},{"unit":"UPA Campinas","travel_time_min":"19.616666666666667","timestamp":"2025-07-02T16:22:43.082152+00:00"},{"unit":"UPA Região Noroeste","travel_time_min":"32.95","timestamp":"2025-07-02T16:22:43.082131+00:00"}]}}
                if not resp['data']:
                    behind_the_courtains = "O USUÁRIO NÃO FORNECEU LOCALIZAÇÃO (OU CEP), E PORTANTO NÃO CONSEGUIMOS CALCALCULAR O TEMPO TOTAL A SER GASTO (O SISTEMA CALCULA A PARTIR DO PONTO DE PARTIDA, O QUAL É POSSÍVEL SER IDENTIFICADO A PARTIR DA LOCALIZAÇÃO OU DO CEP)."
                    classificacao = "erro"
                    history1 = get_recent_history(f"1_{cripto_number}", 3)
                    content1 = ""
                    if history1:
                        content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
                    answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
                    mensagem = answerman.execute(message)
                    save_interaction(f"1_{cripto_number}", message, mensagem)
                else:
                    mensagem = estimate(date_time_string, cripto_number, message, resp)

            elif intent_json['classificacao'] == "ajudar" or intent_json['classificacao'] == "outro":
                behind_the_courtains = intent_json['raciocinio']
                classificacao = intent_json['classificacao']
                history1 = get_recent_history(f"1_{cripto_number}", 3)
                content1 = ""
                if history1:
                    content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
                answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
                mensagem = answerman.execute(message)
                save_interaction(f"1_{cripto_number}", message, mensagem)

    elif (type == "locationMessage"):
        latitude = event_body['data']['message']['locationMessage']['degreesLatitude']
        longitude = event_body['data']['message']['logationMessage']['degreesLongitude']
        body = json.dumps({ "user_phone": user_phone, "latitude": latitude, "longitude": longitude })
        # resp = http.request("POST", url=f"{TRIGGER_API_URL}/route_times", json=body, timeout=30)
        resp = {"message":"Route times stored."}

        if json.loads(resp['message']) == "Route times stored":
            time.sleep(1)
            resp = {"data": {"user_phone":"556296504306@s.whatsapp.net","results":[{"unit":"CAIS Cândida de Morais","travel_time_min":"29.216666666666665","timestamp":"2025-07-02T16:22:43.082107+00:00"},{"unit":"CIAMS Urias Magalhães","travel_time_min":"15.933333333333334","timestamp":"2025-07-02T16:22:43.082139+00:00"},{"unit":"Cais Finsocial","travel_time_min":"34.916666666666664","timestamp":"2025-07-02T16:22:43.082146+00:00"},{"unit":"UPA Campinas","travel_time_min":"19.616666666666667","timestamp":"2025-07-02T16:22:43.082152+00:00"},{"unit":"UPA Região Noroeste","travel_time_min":"32.95","timestamp":"2025-07-02T16:22:43.082131+00:00"}]}}
            # resp = {"data": """{"user_phone":"556296504306@s.whatsapp.net","results":[{"unit":"CAIS Cândida de Morais","travel_time_min":"29.216666666666665","timestamp":"2025-07-02T16:22:43.082107+00:00"},{"unit":"CIAMS Urias Magalhães","travel_time_min":"15.933333333333334","timestamp":"2025-07-02T16:22:43.082139+00:00"},{"unit":"Cais Finsocial","travel_time_min":"34.916666666666664","timestamp":"2025-07-02T16:22:43.082146+00:00"},{"unit":"UPA Campinas","travel_time_min":"19.616666666666667","timestamp":"2025-07-02T16:22:43.082152+00:00"},{"unit":"UPA Região Noroeste","travel_time_min":"32.95","timestamp":"2025-07-02T16:22:43.082131+00:00"}]}"""}
            # resp = http.request(url=f"{TRIGGER_API_URL}/route_times/{user_phone}", timeout=20)
            if not resp['data']:
                behind_the_courtains = "O USUÁRIO NÃO FORNECEU LOCALIZAÇÃO (OU CEP), E PORTANTO NÃO CONSEGUIMOS CALCALCULAR O TEMPO TOTAL A SER GASTO (O SISTEMA CALCULA A PARTIR DO PONTO DE PARTIDA, O QUAL É POSSÍVEL SER IDENTIFICADO A PARTIR DA LOCALIZAÇÃO OU DO CEP)."
                classificacao = "erro"
                history1 = get_recent_history(f"1_{cripto_number}", 3)
                content1 = ""
                if history1:
                    content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
                answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
                mensagem = answerman.execute(message)
                save_interaction(f"1_{cripto_number}", message, mensagem)
            else:
                mensagem = estimate(date_time_string, cripto_number, message, resp)


        else:
            behind_the_courtains = "ERRO DE ENVIO DE LOCALIZAÇÃO"
            classificacao = "erro"

            history1 = get_recent_history(f"1_{cripto_number}", 3)
            content1 = ""
            if history1:
                content1 = f"""
    ## Histórico de mensagens
    Interações mais recentes entre o usuário e você.
    {history1}
    """        
            answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
            mensagem = answerman.execute(message)
            save_interaction(f"1_{cripto_number}", message, mensagem)

    else:
        preset = "Sinto muito, tenho dificuldade com mensagens que não são texto nem localização. 😓"
        return preset
    

    return mensagem

def estimate(date_time_string, cripto_number, message, resp):
    route_times_obj = resp["data"]["results"]
    
    time.sleep(1)

    # Parse the date string (assume it's in ISO format)
    date = datetime.fromisoformat(date_time_string.replace('Z', '+00:00'))  # Handles UTC "Z" format

    # Add 3 hours
    date_plus_3 = date + timedelta(hours=3)

    # Get ISO string in local time (remove the 'Z' at the end)
    local_iso = date_plus_3.isoformat()
    # resp = http.request("GET", url=f"{TRIGGER_API_URL}/all_estimates?query_time={local_iso}", timeout=10)
    resp = {"estimates":[{"unit":"CAIS Cândida de Morais","blue":0.0,"green":94.02893463311297,"yellow":0.0,"orange":0.0,"red":0.0},{"unit":"Cais Finsocial","blue":0.0,"green":94.02893463311297,"yellow":0.0,"orange":0.0,"red":0.0},{"unit":"UPA Região Noroeste","blue":0.0,"green":94.02893463311297,"yellow":0.0,"orange":0.0,"red":0.0},{"unit":"CIAMS Urias Magalhães","blue":0.0,"green":104.43382078017407,"yellow":0.0,"orange":0.0,"red":0.0},{"unit":"UPA Campinas","blue":0.0,"green":167.78984738678312,"yellow":0.0,"orange":0.0,"red":0.0}],"query_time":"2025-07-02T20:05:10.891000Z"}
    if all_estimates_obj := resp:
        merged = merge_estimates_and_routes(all_estimates_obj, route_times_obj)
        understand = UnderstandableWaitTime(merged=merged)
        mensagem = understand.execute("De forma direta e simples, me diga o total da estimativa de tempo gasto caso eu saia daqui agora, até eu ser atendido por um médico (só o total ida + espera na recepção).")
    
    else:
        behind_the_courtains = "O USUÁRIO BUSCOU SABER O TEMPO NUM HORÁRIO QUE O SISTEMA NÃO ESTÁ DISPONÍVEL. PORTANTO NÃO É POSSÍVEL CALCULAR TEMPO. HORÁRIOS QUE O SISTEMA ESTÁ INDISPONÍVEI: HORÁRIOS DE BAIXA MOVIMENTAÇÃO (FINAIS DE SEMANA, E 21:00 DA NOITE AS 05:00 DA MANHÃ). O USUÁRIO DEVERIA TENTAR INTERAGIR NOVAMENTE MAIS TARDE. INFORME O "
        classificacao = "erro"
        history1 = get_recent_history(f"1_{cripto_number}", 3)
        content1 = ""
        if history1:
            content1 = f"""
## Histórico de mensagens
Interações mais recentes entre o usuário e você.
{history1}
"""        
        answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao, sect_history=content1)
        mensagem = answerman.execute(message)
        save_interaction(f"1_{cripto_number}", message, mensagem)
        print(f"return: {mensagem}")
    return mensagem
