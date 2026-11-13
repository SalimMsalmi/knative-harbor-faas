import json
import os
import psycopg2

def handle(event, context):
    try:
        conn = psycopg2.connect(
            host=os.environ.get("DB_HOST", "192.168.1.7"),
            port=5432,
            dbname="demodb",
            user="demouser",
            password=os.environ.get("DB_PASSWORD", ""),
            connect_timeout=5
        )
        cur = conn.cursor()
        cur.execute("SELECT id, name, value FROM items ORDER BY id;")
        rows = cur.fetchall()
        cur.close()
        conn.close()

        items = [{"id": r[0], "name": r[1], "value": r[2]} for r in rows]

        return {
            'statusCode': 200,
            'body': json.dumps({'items': items}),
            'headers': {'Content-Type': 'application/json'}
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)}),
            'headers': {'Content-Type': 'application/json'}
        }