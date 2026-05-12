import Foundation

struct WeatherResult {
    let uvi:           Double
    let daylightHours: Double
    let indoors:       Bool
}

class WeatherService {

    func fetch(lat: Double, lon: Double,
               accuracy: Double) async throws
               -> WeatherResult {

        // Hourly UV index — not daily max
        var comps = URLComponents(
            string:
            "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude",
                  value: "\(lat)"),
            .init(name: "longitude",
                  value: "\(lon)"),
            .init(name: "hourly",
                  value: "uv_index"),
            .init(name: "daily",
                  value: "sunrise,sunset"),
            .init(name: "timezone",
                  value: "auto"),
            .init(name: "forecast_days",
                  value: "1"),
        ]
        let (data, _) = try await URLSession.shared
            .data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(
            with: data) as! [String: Any]

        // Current hour's actual UV
        let hourly  = json["hourly"] as! [String: Any]
        let uviList = hourly["uv_index"] as! [Double]
        let hour    = Calendar.current.component(
            .hour, from: Date())
        let uvi     = uviList[
            min(hour, uviList.count - 1)]

        // Daylight hours for SED (Eq. 2)
        let daily = json["daily"] as! [String: Any]
        let srStr = (daily["sunrise"]
            as! [String]).first ?? ""
        let ssStr = (daily["sunset"]
            as! [String]).first ?? ""
        let fmt   = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let sr    = fmt.date(from: srStr) ?? Date()
        let ss    = fmt.date(from: ssStr) ?? Date()
        let hours = max(0,
            ss.timeIntervalSince(sr) / 3600)

        // Check if indoors via OSM building footprints
        let indoors = await checkIfIndoors(
            lat: lat, lon: lon, accuracy: accuracy)

        // Zero UV if indoors — glass blocks ~97% UVB
        let finalUVI = indoors ? 0.0 : uvi

        return WeatherResult(
            uvi:           finalUVI,
            daylightHours: hours,
            indoors:       indoors)
    }

    func checkIfIndoors(
        lat: Double, lon: Double,
        accuracy: Double) async -> Bool {
        let radius = max(20, accuracy * 2)
        let query  = """
        [out:json][timeout:5];
        way["building"](around:\(Int(radius)),\(lat),\(lon));
        out geom;
        """
        guard let url = URL(string:
            "https://overpass-api.de/api/interpreter")
        else { return false }

        var req = URLRequest(url: url)
        req.httpMethod      = "POST"
        req.httpBody        = query.data(using: .utf8)
        req.timeoutInterval = 6

        do {
            let (data, _) = try await
                URLSession.shared.data(for: req)
            let json = try JSONSerialization
                .jsonObject(with: data)
                as! [String: Any]
            let elements = json["elements"]
                as? [[String: Any]] ?? []
            return !elements.isEmpty && accuracy < 25
        } catch {
            print("Indoor check failed: \(error)")
            return false
        }
    }
}
