from flask import Flask, request, jsonify
import pandas as pd
import time

app = Flask(__name__)
data_store = []

@app.route('/process', methods=['POST'])
def process_data():
    global data_store
    data = request.json
    current_time = time.time()

    data_store.append({**data, "timestamp": current_time})
    #remove data older than 60 seconds
    data_store = [d for d in data_store if current_time - d['timestamp'] < 60]

    df = pd.DataFrame(data_store)
    jumps_count = detect_jumps(df['z'])

    result = {"jumps_per_minute": jumps_count}  
    return jsonify(result)

def detect_jumps(z_data, threshold=1.2, min_interval=10):
    jumps = []
    last_jump = -min_interval
    for i in range(1, len(z_data)):
        if z_data[i-1] < threshold < z_data[i] and (i - last_jump) >= min_interval:
            jumps.append(i)
            last_jump = i
    return len(jumps)

if __name__ == '__main__':
    app.run(debug=True, port=5000)
