from flask import Flask, request, jsonify
import pandas as pd
import time
import os
import random
from flask import Flask, send_from_directory
from urllib.parse import quote
import eyed3

app = Flask(__name__)

latest_jumps_per_minute = 0
current_song_path = ""
song_data = ""

@app.route('/process', methods=['POST'])
def process_data():
    global latest_jumps_per_minute, current_song_path, song_data
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
        song_data = current_song_path[0].tag
        print(song_data.artist)
        print(song_data.title)
        for image in song_data.images:
            print(image)
        if song_data.title + "cover.jpg" not in os.listdir(SONGS_DIRECTORY):
            image_file = open("../Wizz_songs/"+song_data.title + "cover.jpg", "wb")
            image_file.write(song_data.images[0].image_data)
            image_file.close()
        print(f"Jumps per minute: {jumps_per_minute}")
        print(f"Selected song path: {current_song_path[1]}")
        result = {"jumps_per_minute": jumps_per_minute, "song_path": current_song_path[1], "song_name": song_data.title, "song_artist": song_data.artist, "song_cover_path": f"http://10.0.0.229:5006/songs/{song_data.title + "cover.jpg"}"}
        return jsonify(result)
    except Exception as e:
        print(f"Error processing data: {str(e)}")
        return jsonify({"error": "Error processing data"}), 500

@app.route('/get_jpm', methods=['GET'])
def get_jpm():
    global latest_jumps_per_minute, current_song_path, song_data
    return jsonify({"jumps_per_minute": round(latest_jumps_per_minute), "song_path": current_song_path[1], "song_name": song_data.title, "song_artist": song_data.artist, "song_cover_path": f"http://10.0.0.229:5006/songs/{song_data.title + "cover.jpg"}"})

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
            audio_file = eyed3.load(f"../Wizz_songs/{folder_name}/{selected_song}")
            return (audio_file, f"http://10.0.0.229:5006/songs/{folder_name}/{encoded_song}")
    return None


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5006)
