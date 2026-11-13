import json

def handle(event, context):
    # Decode bytes to string if needed
    input_data = event.body
    if isinstance(input_data, bytes):
        input_data = input_data.decode("utf-8")
    
    response_body = {
        "message": "Hello from my custom function",
        "input_received": input_data
    }
    
    return {
        "statusCode": 200,
        "body": json.dumps(response_body),
        "headers": {
            "Content-Type": "application/json"
        }
    }
