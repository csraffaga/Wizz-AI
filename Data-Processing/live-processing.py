from flask import Flask, request, jsonify
import pandas as pd
import time

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process_data():
    try:
        data = request.json  # This should be a list of dictionaries
        current_time = time.time()

        # Append a timestamp to each item (optional, depends if you need it later)
        for item in data:
            item["timestamp"] = current_time

        # Create a DataFrame from the current packet's data
        df = pd.DataFrame(data)
        if not df.empty:
            packet_span_seconds = 5  # The data packet span in seconds is now 5 seconds
            total_jumps = detect_jumps(df['z'])
            jumps_per_minute = (total_jumps / packet_span_seconds) * 60  # Recalculate jumps per minute for 5 seconds span
        else:
            jumps_per_minute = 0

        print(f"Jumps per minute: {jumps_per_minute}")
        result = {"jumps_per_minute": jumps_per_minute}
        return jsonify(result)
    except Exception as e:
        print(f"Error processing data: {str(e)}")
        return jsonify({"error": "Error processing data"}), 500

def detect_jumps(z_data, threshold=0.0, min_interval=1):
    jumps = []
    last_jump_index = -min_interval
    for i in range(1, len(z_data)):
        if z_data[i-1] < threshold <= z_data[i] and (i - last_jump_index) >= min_interval:
            jumps.append(i)
            last_jump_index = i
    print(f"Detected jumps indices: {jumps}")  
    return len(jumps)


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5001)
