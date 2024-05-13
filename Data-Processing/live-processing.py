from flask import Flask, request, jsonify
import pandas as pd
import time
import os
import random
from flask import Flask, send_from_directory
from urllib.parse import quote

app = Flask(__name__)

latest_jumps_per_minute = 0
current_song_path = ""

@app.route('/process', methods=['POST'])
def process_data():
    global latest_jumps_per_minute, current_song_path
    try:
        data = request.json
        current_time = time.time()

        for item in data:
            item["timestamp"] = current_time

        df = pd.DataFrame(data)
        if not df.empty:
            packet_span_seconds = 12
            total_jumps = detect_jumps(df['z'])
            jumps_per_minute = (total_jumps / packet_span_seconds) * 60
        else:
            jumps_per_minute = 0

        latest_jumps_per_minute = jumps_per_minute
        current_song_path = select_song(jumps_per_minute)

        print(f"Jumps per minute: {jumps_per_minute}")
        print(f"Selected song path: {current_song_path}")
        result = {"jumps_per_minute": jumps_per_minute, "song_path": current_song_path}
        return jsonify(result)
    except Exception as e:
        print(f"Error processing data: {str(e)}")
        return jsonify({"error": "Error processing data"}), 500

@app.route('/get_jpm', methods=['GET'])
def get_jpm():
    global latest_jumps_per_minute, current_song_path
    return jsonify({"jumps_per_minute": latest_jumps_per_minute, "song_path": current_song_path})

def detect_jumps(z_data, threshold=0.0, min_interval=1):
    jumps = []
    last_jump_index = -min_interval
    for i in range(1, len(z_data)):
        if z_data[i-1] < threshold <= z_data[i] and (i - last_jump_index) >= min_interval:
            jumps.append(i)
            last_jump_index = i
    return len(jumps)

SONGS_DIRECTORY = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Wizz_songs"))


@app.route('/songs/<path:filename>')
def serve_song(filename):
    return send_from_directory(SONGS_DIRECTORY, filename)

def closest_bpm(bpm):
    bpms = [104, 120, 130, 140]
    closest = 0
    for i in range(len(bpms)):
        if abs(bpms[i] - bpm) < abs(bpms[closest] - bpm):
            closest = i
    return bpms[closest]

def select_song(bpm):
    folder_name = closest_bpm(bpm)
    folder_path = os.path.join(SONGS_DIRECTORY, str(folder_name))
    if os.path.exists(folder_path):
        songs = [song for song in os.listdir(folder_path) if song.endswith('.mp3')]
        if songs:
            selected_song = random.choice(songs)
            encoded_song = quote(selected_song)
            return f"http://10.0.0.209:5001/songs/{folder_name}/{encoded_song}"
    return None


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5001)
