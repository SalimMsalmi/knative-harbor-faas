import json

def handle(event, context):
    input_data = event.body
    if isinstance(input_data, bytes):
        input_data = input_data.decode("utf-8")
    result = input_data.upper()
    return {
        "statusCode": 200,
        "body": json.dumps({"result": result, "message": "Portal test successful"}),
        "headers": {"Content-Type": "application/json"}
    }