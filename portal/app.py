#!/usr/bin/env python3
"""
FaaS Portal Backend - Flask API for deploying and invoking functions
"""
from flask import Flask, request, jsonify, send_from_directory
import subprocess
import os
import re
import time
import shutil
from pathlib import Path

app = Flask(__name__)

# Configuration
BASE_DIR = Path(__file__).resolve().parent
HARBOR_REGISTRY = os.environ.get("HARBOR_REGISTRY", "192.168.1.5")
HARBOR_PROJECT = os.environ.get("HARBOR_PROJECT", "client-demo")
KOURIER_NODEPORT = os.environ.get("KOURIER_NODEPORT", "32491")
TEMPLATE_DIR = os.environ.get("TEMPLATE_DIR", str(BASE_DIR / "templates"))
BUILD_DIR = os.environ.get("BUILD_DIR", str(BASE_DIR / "builds"))
DOMAIN_SUFFIX = os.environ.get("DOMAIN_SUFFIX", f"{HARBOR_REGISTRY}.sslip.io")
IMAGE_PULL_SECRET = os.environ.get("IMAGE_PULL_SECRET", "harbor-registry")
PORTAL_PORT = int(os.environ.get("PORTAL_PORT", "5000"))

def is_valid_k8s_name(name):
    """Validate Kubernetes resource name"""
    pattern = r'^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
    return bool(re.match(pattern, name)) and len(name) <= 63

def run_command(cmd, cwd=None):
    """Run shell command and return output"""
    result = subprocess.run(
        cmd,
        shell=True,
        cwd=cwd,
        capture_output=True,
        text=True
    )
    return result.returncode, result.stdout, result.stderr

@app.route('/')
def index():
    """Serve the frontend HTML page"""
    return send_from_directory(str(BASE_DIR / 'static'), 'index.html')

@app.route('/deploy', methods=['POST'])
def deploy():
    """Deploy a new function"""
    try:
        data = request.json
        function_name = data.get('name', '').strip()
        function_code = data.get('code', '').strip()
        
        # Validate inputs
        if not function_name:
            return jsonify({'error': 'Function name is required'}), 400
        
        if not is_valid_k8s_name(function_name):
            return jsonify({
                'error': 'Invalid function name. Must be lowercase alphanumeric with hyphens, max 63 chars'
            }), 400
        
        if not function_code:
            return jsonify({'error': 'Function code is required'}), 400
        
        # Create build directory
        build_path = os.path.join(BUILD_DIR, function_name)
        if os.path.exists(build_path):
            shutil.rmtree(build_path)
        os.makedirs(build_path)
        
        # Create function subdirectory
        function_dir = os.path.join(build_path, 'function')
        os.makedirs(function_dir)
        
        # Write user's handler code
        handler_path = os.path.join(function_dir, 'handler.py')
        with open(handler_path, 'w') as f:
            f.write(function_code)
        
        # Copy template files
        shutil.copy(os.path.join(TEMPLATE_DIR, 'Dockerfile'), build_path)
        shutil.copy(os.path.join(TEMPLATE_DIR, 'index.py'), build_path)
        shutil.copy(os.path.join(TEMPLATE_DIR, 'requirements.txt'), build_path)
        
        # Build Docker image
        image_tag = f"{HARBOR_REGISTRY}/{HARBOR_PROJECT}/{function_name}:latest"
        
        returncode, stdout, stderr = run_command(
            f"docker build -t {image_tag} .",
            cwd=build_path
        )
        
        if returncode != 0:
            return jsonify({
                'error': 'Docker build failed',
                'details': stderr or stdout
            }), 500
        
        # Push to Harbor
        returncode, stdout, stderr = run_command(
            f"docker push {image_tag}"
        )
        
        if returncode != 0:
            return jsonify({
                'error': 'Docker push failed',
                'details': stderr or stdout
            }), 500
        
        # Create Knative Service YAML
        ksvc_yaml = f"""apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: {function_name}
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: "0"
        autoscaling.knative.dev/max-scale: "10"
    spec:
      imagePullSecrets:
        - name: {IMAGE_PULL_SECRET}
      containers:
      - image: {image_tag}
        ports:
        - containerPort: 8080
          protocol: TCP
"""
        
        ksvc_path = os.path.join(build_path, 'service.yaml')
        with open(ksvc_path, 'w') as f:
            f.write(ksvc_yaml)
        
        # Apply Knative Service
        returncode, stdout, stderr = run_command(
            f"kubectl apply -f {ksvc_path}"
        )
        
        if returncode != 0:
            return jsonify({
                'error': 'Kubectl apply failed',
                'details': stderr or stdout
            }), 500
        
        # Wait for service to be ready (max 60 seconds)
        max_wait = 60
        waited = 0
        ready = False
        
        while waited < max_wait:
            returncode, stdout, stderr = run_command(
                f"kubectl get ksvc {function_name} -n default -o jsonpath='{{.status.conditions[?(@.type==\"Ready\")].status}}'"
            )
            
            if stdout.strip() == "True":
                ready = True
                break
            
            time.sleep(2)
            waited += 2
        
        if not ready:
            return jsonify({
                'error': 'Function deployment timed out',
                'details': 'Knative Service did not become Ready within 60 seconds'
            }), 500
        
        # Get service URL
        returncode, stdout, stderr = run_command(
            f"kubectl get ksvc {function_name} -n default -o jsonpath='{{.status.url}}'"
        )
        
        service_url = stdout.strip()
        
        return jsonify({
            'success': True,
            'url': service_url,
            'nodeport_curl_example': f"curl -H 'Host: {function_name}.default.{DOMAIN_SUFFIX}' http://{HARBOR_REGISTRY}:{KOURIER_NODEPORT} -d 'your input'"
        })
        
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error during deployment',
            'details': str(e)
        }), 500

@app.route('/invoke', methods=['POST'])
def invoke():
    """Invoke a deployed function"""
    try:
        data = request.json
        function_name = data.get('name', '').strip()
        input_data = data.get('input', '')
        
        if not function_name:
            return jsonify({'error': 'Function name is required'}), 400
        
        # Invoke function via Kourier NodePort
        host_header = f"{function_name}.default.{DOMAIN_SUFFIX}"
        url = f"http://{HARBOR_REGISTRY}:{KOURIER_NODEPORT}"
        
        # Use curl to invoke the function (escape input data properly)
        import shlex
        escaped_input = shlex.quote(input_data)
        cmd = f"curl -s -H 'Host: {host_header}' {url} --data-raw {escaped_input}"
        returncode, stdout, stderr = run_command(cmd)
        
        if returncode != 0:
            return jsonify({
                'error': 'Function invocation failed',
                'details': stderr or stdout
            }), 500
        
        # Try to parse as JSON, otherwise return as string
        try:
            import json
            response_json = json.loads(stdout)
            return jsonify({
                'success': True,
                'response': response_json
            })
        except json.JSONDecodeError:
            return jsonify({
                'success': True,
                'response': stdout
            })
        
    except Exception as e:
        return jsonify({
            'error': 'Unexpected error during invocation',
            'details': str(e)
        }), 500

if __name__ == '__main__':
    os.makedirs(BUILD_DIR, exist_ok=True)
    app.run(host='0.0.0.0', port=PORTAL_PORT, debug=False)
