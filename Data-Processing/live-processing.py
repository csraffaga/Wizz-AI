from flask import Flask, request, jsonify # type: ignore
import pandas as pd # type: ignore

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process_data():
    data = request.json  # Assuming the incoming data is in JSON format
    df = pd.DataFrame(data)  # Convert the JSON data to a pandas DataFrame

    # Process your data here with pandas or any other library

    result = {"message": "Data processed successfully"}  # Example result
    return jsonify(result)

if __name__ == '__main__':
    app.run(debug=True, port=5000)

