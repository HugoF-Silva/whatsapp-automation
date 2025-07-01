import os
import json
import requests
import re
from gemini import IntentionClassifier, AnswerMan, UnderstandableWaitTime  # adjust import path
from datetime import datetime, timedelta
import time

# Environment
EVO_API_URL = os.environ["EVO_API_URL"]
TRIGGER_API_URL  = os.environ['TRIGGER_API_URL']

classifier = IntentionClassifier()
answerman = AnswerMan()

def merge_estimates_and_routes(all_estimates_obj, route_times_obj):
    # Map travel times by unit
    travel_time_by_unit = {
        rt['unit']: round(float(rt['travel_time_min']))
        for rt in route_times_obj['results']
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
    print(f">>>>>>>EVENT: {event}")
    print(f">>>>>>>CONTEXT: {context}")
    date_time_string = event[0]['json']['body']['date_time']
    # Parse the date and extract just the hour (as an integer)
    date_obj = datetime.fromisoformat(date_time_string)
    hour_int = date_obj.hour

    if (hour_int <= 5) or (hour_int >= 21):
        preset = "Não calculo tempo de espera entre 21:00 ~ 05:00, nem finais de semana...                                                                                    Um segredo que só quem é da comunidade Menos Tempo sabe: *eu conseguiria* se você dissesse que quer a Menos Tempo oficialmente pelo link bit.ly/quero-oficialmente 🤏 (não conta pra ninguém, é exclusivo 🤫)"
        return preset
    
    type = event['item']['json']['body']['data']['messageType']
    user_phone = event['item']['json']['body']['data']['messageType']

    if (type == "conversation"):
        try:
            message = event['item']['json']['body']['data']['message']['conversation']
            
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
            resp = requests.get(url=f"https://www.cepaberto.com/api/v3/cep?cep={clean_cep}", headers={"Authorization":"Token token=bf2a40be4391c25294e40a44317123a7"})
            if (latitude:=resp.get("latitude", None)) and (longitude:=resp.get("longitude", None)):
                body = json.dump({ "user_phone": user_phone, "latitude": latitude, "longitude": longitude })
                resp = requests.post(url=f"{TRIGGER_API_URL}/route_times", json=body, timeout=30000)
            else:
                behind_the_courtains = "ERRO DE ENVIO DE LOCALIZAÇÃO"
                classificacao = "erro"
                answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao)
                mensagem = answerman.execute(message)
        else:
            body = json.dump({ "user_phone": user_phone, "latitude": latitude, "longitude": longitude })
            intent_json = classifier.execute(message)
            if intent_json['classificacao'] == "tempo":
                resp = requests.get(url=f"{TRIGGER_API_URL}/route_times/{user_phone}", timeout=20000)
                if not resp.answer:
                    behind_the_courtains = "O USUÁRIO NÃO FORNECEU LOCALIZAÇÃO (OU CEP), E PORTANTO NÃO CONSEGUIMOS CALCALCULAR O TEMPO TOTAL A SER GASTO (O SISTEMA CALCULA A PARTIR DO PONTO DE PARTIDA, O QUAL É POSSÍVEL SER IDENTIFICADO A PARTIR DA LOCALIZAÇÃO OU DO CEP)."
                    classificacao = "erro"
                    answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao)
                    mensagem = answerman.execute(message)
                else:
                    route_times_obj = resp.answer

                    time.sleep(1)
                    # Replace this with your actual input extraction
                    date_str = event['item']['json']['body']['date_time']

                    # Parse the date string (assume it's in ISO format)
                    date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))  # Handles UTC "Z" format

                    # Add 3 hours
                    date_plus_3 = date + timedelta(hours=3)

                    # Get ISO string in local time (remove the 'Z' at the end)
                    local_iso = date_plus_3.isoformat()
                    resp = requests.get(f"{TRIGGER_API_URL}/all_estimates?query_time={local_iso}", timeout=10000)

                    if all_estimates_obj := resp.answer:
                        merged = merge_estimates_and_routes(all_estimates_obj, route_times_obj)
                        understand = UnderstandableWaitTime(merged=merged)
                        mensagem = understand.execute("De forma direta e simples, me diga o total da estimativa de tempo gasto caso eu saia daqui agora, até eu ser atendido por um médico (só o total ida + espera na recepção).")
                    
                    else:
                        behind_the_courtains = "O USUÁRIO BUSCOU SABER O TEMPO NUM HORÁRIO QUE O SISTEMA NÃO ESTÁ DISPONÍVEL. PORTANTO NÃO É POSSÍVEL CALCULAR TEMPO. HORÁRIOS QUE O SISTEMA ESTÁ INDISPONÍVEI: HORÁRIOS DE BAIXA MOVIMENTAÇÃO (FINAIS DE SEMANA, E 21:00 DA NOITE AS 05:00 DA MANHÃ). O USUÁRIO DEVERIA TENTAR INTERAGIR NOVAMENTE MAIS TARDE. INFORME O "
                        classificacao = "erro"
                        answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao)
                        mensagem = answerman.execute(message)

            elif intent_json['classificacao'] == "ajudar" or intent_json == "outro":
                behind_the_courtains = intent_json['raciocinio']
                classificacao = intent_json['classificacao']

    elif (type == "locationMessage"):
        latitude = event['item']['json']['body']['data']['message']['locationMessage']['degreesLatitude']
        longitude = event['item']['json']['body']['data']['message']['logationMessage']['degreesLongitude']
        body = json.dumps({ "user_phone": user_phone, "latitude": latitude, "longitude": longitude })
        resp = requests.post(url=f"{TRIGGER_API_URL}/route_times", json=body, timeout=30000)

    else:
        preset = "Sinto muito, tenho dificuldade com mensagens que não são texto nem localização. 😓"
        return preset
    
    if resp.answer == "Route times stored":
        time.sleep(1)
        resp = requests.get(url=f"{TRIGGER_API_URL}/route_times/{user_phone}", timeout=20000)
        if not resp.answer:
            behind_the_courtains = "O USUÁRIO NÃO FORNECEU LOCALIZAÇÃO (OU CEP), E PORTANTO NÃO CONSEGUIMOS CALCALCULAR O TEMPO TOTAL A SER GASTO (O SISTEMA CALCULA A PARTIR DO PONTO DE PARTIDA, O QUAL É POSSÍVEL SER IDENTIFICADO A PARTIR DA LOCALIZAÇÃO OU DO CEP)."
            classificacao = "erro"
            answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao)
            mensagem = answerman.execute(message)

    else:
        behind_the_courtains = "ERRO DE ENVIO DE LOCALIZAÇÃO"
        classificacao = "erro"
        answerman = AnswerMan(behind_the_courtains=behind_the_courtains, classificacao=classificacao)
        mensagem = answerman.execute(message)
    
    return mensagem
