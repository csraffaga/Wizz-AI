from flask import Flask, request, jsonify
import pandas as pd
import time
import os
import random
from flask import Flask, send_from_directory
from urllib.parse import quote
from werkzeug.utils import secure_filename
import eyed3
import soundfile as sf
import scipy
import librosa
import numpy as np
import matplotlib.pyplot as plt

app = Flask(__name__)

latest_jumps_per_minute = 0
current_song_path = ""
song_data = ""

# Main function: processes jumps per minute calculation based on process described in the report
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
        result = {"jumps_per_minute": jumps_per_minute, "song_path": current_song_path[1], "song_name": song_data.title, "song_artist": song_data.artist, "song_cover_path": f"http://10.150.53.192:5006/songs/{song_data.title + "cover.jpg"}"}
        return jsonify(result)
    except Exception as e:
        print(f"Error processing data: {str(e)}")
        return jsonify({"error": "Error processing data"}), 500

# Returns calculated information to the requesting application
@app.route('/get_jpm', methods=['GET'])
def get_jpm():
    global latest_jumps_per_minute, current_song_path, song_data
    return jsonify({"jumps_per_minute": round(latest_jumps_per_minute), "song_path": current_song_path[1], "song_name": song_data.title, "song_artist": song_data.artist, "song_cover_path": f"http://10.150.53.192:5006/songs/{song_data.title + "cover.jpg"}"})

# Helper application for main, jump detection function that calculates number of jumps
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

# Retrives the closest bpm based on the available BPM file choices in the songs
def closest_bpm(bpm):
    bpms = [104, 120, 130, 140]
    closest = 0
    for i in range(len(bpms)):
        if abs(bpms[i] - bpm) < abs(bpms[closest] - bpm):
            closest = i
    return bpms[closest]

# Selects the correct song which most closely resembles JPM
def select_song(bpm):
    folder_name = closest_bpm(bpm)
    folder_path = os.path.join(SONGS_DIRECTORY, str(folder_name))
    if os.path.exists(folder_path):
        songs = [song for song in os.listdir(folder_path) if song.endswith('.mp3')]
        if songs:
            selected_song = random.choice(songs)
            encoded_song = quote(selected_song)
            audio_file = eyed3.load(f"../Wizz_songs/{folder_name}/{selected_song}")
            return (audio_file, f"http://10.150.53.192:5006/songs/{folder_name}/{encoded_song}")
    return None


@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400
    if file:
        filename = secure_filename(file.filename)
        file.save(os.path.join('/path/to/save', filename))
        return "File uploaded successfully", 200


def calculate_jumps(audio_path):
    # Loads the file containing the audio
    y, sr = librosa.load(audio_path, sr=None)

    # Use an STFT to analyze the audio
    D = np.abs(librosa.stft(y))
    energy = np.sum(D, axis=0)
    peaks, _ = scipy.signal.find_peaks(energy, height=np.mean(energy) * 1.5, distance=sr / 2)
    intervals = np.diff(peaks) / sr

    # Calculate jumps per minute
    if intervals.size > 0:
        average_interval = np.mean(intervals)
        jumps_per_minute = 60 / average_interval
    else:
        jumps_per_minute = 0

    return jumps_per_minute


# Where to upload audio files
UPLOAD_FOLDER = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Wizz_songs"))

@app.route('/upload', methods=['POST'])
def upload_audio():

    if 'file' not in request.files:
        return jsonify({"message": "No file part"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"message": "No selected file"}), 400
    if file:
        os.makedirs(UPLOAD_FOLDER, exist_ok=True)
        filename = os.path.join(UPLOAD_FOLDER, file.filename)
        file.save(filename)
        return plot_audio(file.filename)


def plot_audio(filename):
    file_path = os.path.join(UPLOAD_FOLDER, filename)
    try:
        data, sample_rate = sf.read(file_path)
        plt.figure(figsize=(10, 4))
        plt.plot(data)
        plt.title('Audio Waveform')
        plt.ylabel('Amplitude')
        plt.xlabel('Sample Number')
        plt.show()
        return jsonify({"message": "File uploaded and plotted successfully", "filename": filename,
                        "plot_filename": f"{filename}.png"}), 200
    except FileNotFoundError:
        return jsonify({"message": "File not found"}), 404
    except Exception as e:
        return jsonify({"message": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5006)
