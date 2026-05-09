from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import requests, os

app = Flask(__name__)
CORS(app)

@app.route("/")
def index():
    frontend = os.path.join(os.path.dirname(__file__), "../frontend")
    return send_from_directory(frontend, "index.html")

def get_uvi(lat, lon):
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": lat, "longitude": lon,
        "daily": ["uv_index_max", "sunrise", "sunset"],
        "timezone": "auto", "forecast_days": 1
    }
    r = requests.get(url, params=params, timeout=8).json()
    uvi = r["daily"]["uv_index_max"][0]
    from datetime import datetime
    fmt = "%Y-%m-%dT%H:%M"
    sr = datetime.strptime(r["daily"]["sunrise"][0], fmt)
    ss = datetime.strptime(r["daily"]["sunset"][0], fmt)
    daylight_h = (ss - sr).seconds / 3600
    return uvi, daylight_h

def vitamin_d_estimate(uvi, daylight_h, bsa, age, skin, oral_ug=5.0):
    f_age  = max(0.1, 1.0 - 0.013 * (age - 20))
    f_skin = 1.0 if skin == "I-II" else 0.74
    A, f, beta, alpha = 0.18, 0.15, 25, 0.6
    S, alpha_p = 0.023, 1.5
    sed    = uvi * 0.025 * daylight_h * 3600 / (2 * 100)
    R_uv   = A * ((1-f)*2**(-1/beta) + f*2**(-1/250) - 2**(-1/alpha))
    R_oral = S * ((1-f)*2**(-1/beta) + f*2**(-1/250) - 2**(-1/alpha_p))
    sun    = f_age * f_skin * sed * bsa * R_uv
    oral   = oral_ug * R_oral
    return round(50.0 + sun + oral, 1)

@app.route("/estimate", methods=["POST"])
def estimate():
    d = request.get_json()
    try:
        uvi, daylight_h = get_uvi(d["lat"], d["lon"])
        vd = vitamin_d_estimate(
            uvi, daylight_h,
            float(d["bsa"]), int(d["age"]), d["skin"],
            float(d.get("oral_ug", 5.0))
        )
        return jsonify({
            "uvi": round(uvi, 1),
            "daylight_hours": round(daylight_h, 1),
            "vitamin_d_nmol_l": vd
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)