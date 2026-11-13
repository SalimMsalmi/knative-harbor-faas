import json
import statistics

def handle(event, context):
    try:
        input_data = event.body
        if isinstance(input_data, bytes):
            input_data = input_data.decode('utf-8')
        
        payload = json.loads(input_data)
        numbers = payload.get('numbers', [])
        
        if not numbers:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Please provide a "numbers" array'}),
                'headers': {'Content-Type': 'application/json'}
            }
        
        result = {
            'count': len(numbers),
            'sum': sum(numbers),
            'average': statistics.mean(numbers),
            'min': min(numbers),
            'max': max(numbers),
            'sorted': sorted(numbers)
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({'input': numbers, 'stats': result}),
            'headers': {'Content-Type': 'application/json'}
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)}),
            'headers': {'Content-Type': 'application/json'}
        }