from flask import Flask, json
import socket, os

app = Flask(__name__)

@app.route('/')
def hello_world():
    hostname = socket.gethostname()
    bg_color = os.environ.get('BG_COLOR', 'white')
    font_color = os.environ.get('FONT_COLOR', 'black')
    custom_header = os.environ.get('CUSTOM_HEADER', 'Containerized Webapp')
    custom_photo = os.environ.get('CUSTOM_PHOTO', 'https://raw.githubusercontent.com/kubernetes/kubernetes/master/logo/logo.svg')
    
    html = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Containerized Webapp</title>
        <style>
            * {{
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }}
            body {{
                background-color: {bg_color};
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                color: {font_color};
            }}
            .container {{
                text-align: center;
                padding: 20px;
                max-width: 800px;
            }}
            .photo {{
                width: 200px;
                height: 200px;
                margin-bottom: 30px;
                object-fit: contain;
            }}
            h1 {{
                font-size: 2.5em;
                margin-bottom: 30px;
                color: {font_color};
            }}
            h2 {{
                font-size: 1.5em;
                margin-top: 30px;
                color: {font_color};
            }}
            b {{
                font-weight: 600;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <img src="{custom_photo}" alt="Custom Photo" class="photo">
            <h1>{custom_header}</h1>
            <h2>Hello World! Served from <b>{hostname}</b></h2>
        </div>
    </body>
    </html>
    """
    return html