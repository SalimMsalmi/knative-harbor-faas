#!/usr/bin/env python3
"""
Flask wrapper for user-submitted function code.
Handles HTTP requests and routes them to user's handle(event, context).
"""
import json
from flask import Flask, request, jsonify
import sys
import os

app = Flask(__name__)

# Import user's handler function
sys.path.insert(0, '/home/app/function')
from handler import handle

class Event:
    """Event object passed to user's handle function"""
    def __init__(self, body, headers, method, path):
        self.body = body
        self.headers = headers
        self.method = method
        self.path = path

class Context:
    """Context object passed to user's handle function"""
    def __init__(self):
        self.function_name = os.environ.get('FUNCTION_NAME', 'unknown')

@app.route('/', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def handler_route():
    """Main route that invokes user's handle function"""
    try:
        # Get request body - try multiple methods
        if request.data:
            body = request.data
        elif request.form:
            # Form data (application/x-www-form-urlencoded)
            body = next(iter(request.form.keys())).encode('utf-8') if request.form else b''
        else:
            body = b''
        
        # Create event and context objects
        event = Event(
            body=body,
            headers=dict(request.headers),
            method=request.method,
            path=request.path
        )
        context = Context()
        
        # Call user's handle function
        result = handle(event, context)
        
        # Handle response format
        if isinstance(result, dict):
            status_code = result.get('statusCode', 200)
            body = result.get('body', '')
            headers = result.get('headers', {})
            
            # If body is already a string, use it directly
            if isinstance(body, str):
                response = app.response_class(
                    response=body,
                    status=status_code,
                    headers=headers
                )
            else:
                response = jsonify(body)
                response.status_code = status_code
                for key, value in headers.items():
                    response.headers[key] = value
            
            return response
        else:
            # If result is not a dict, return it as JSON
            return jsonify(result)
            
    except Exception as e:
        return jsonify({
            'error': str(e),
            'type': type(e).__name__
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
