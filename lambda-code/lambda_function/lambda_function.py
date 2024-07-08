import boto3
import json
from decimal import Decimal
from datetime import datetime
from statistics import median
import urllib3

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

def fetch_weather_data(lat, lon, start_date, end_date):
    url = f"https://archive-api.open-meteo.com/v1/archive?latitude={lat}&longitude={lon}&start_date={start_date}&end_date={end_date}&hourly=temperature_2m,relative_humidity_2m"
    http = urllib3.PoolManager()
    response = http.request('GET', url)
    data = json.loads(response.data.decode('utf-8'))
    return data['hourly']

def aggregate_data(hourly_data):
    daily_data = {}
    for i in range(len(hourly_data['time'])):
        date = hourly_data['time'][i][:10]
        temperature = hourly_data['temperature_2m'][i]
        humidity = hourly_data['relative_humidity_2m'][i]
        if date not in daily_data:
            daily_data[date] = {'temperatures': [], 'humidities': []}
        daily_data[date]['temperatures'].append(temperature)
        daily_data[date]['humidities'].append(humidity)
    
    aggregated_data = []
    for date, values in daily_data.items():
        aggregated_data.append({
            'date': date,
            'median_temperature': median(values['temperatures']),
            'median_humidity': median(values['humidities'])
        })
    return aggregated_data

def save_to_dynamodb(property_id, aggregated_data):
    table = dynamodb.Table('HistoricalWeatherData')
    for data in aggregated_data:
        item = {
            'property_id': property_id,
            'date': data['date'],
            'median_temperature': Decimal(str(data['median_temperature'])),
            'median_humidity': Decimal(str(data['median_humidity']))
        }
        table.put_item(Item=item)

def lambda_handler(event, context):
    for record in event['Records']:
        message = json.loads(record['body'])
        property_id = message['property_id']
        lat = message['lat']
        lon = message['lon']
        start_date = message['start_date']
        end_date = message['end_date']
        
        hourly_data = fetch_weather_data(lat, lon, start_date, end_date)
        aggregated_data = aggregate_data(hourly_data)
        save_to_dynamodb(property_id, aggregated_data)

    return {'statusCode': 200, 'body': json.dumps('Success')}