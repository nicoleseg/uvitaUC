import Foundation

struct FileLogger {

    // Base URL: On My iPhone → Uvita/
    static var uvitaDir: URL? {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask).first
    }

    static func setup() {
        guard let base = uvitaDir else { return }
        let folders = ["UVlogs", "Diet", "VitaminD"]
        for folder in folders {
            let url = base.appendingPathComponent(folder)
            try? FileManager.default
                .createDirectory(at: url,
                    withIntermediateDirectories: true)
        }
    }

    // Called every reading — appends to today's CSV
    static func log(reading: DayReading) {
        setup()
        logUV(reading)
        logVitaminD(reading)
    }

    // UVlogs/YYYY-MM-DD_uv.csv
    static func logUV(_ r: DayReading) {
        guard let dir = uvitaDir else { return }
        let dateStr = dayString(r.date)
        let file = dir
            .appendingPathComponent("UVlogs")
            .appendingPathComponent(
                "\(dateStr)_uv.csv")

        // Header if new file
        let header = "timestamp,uvi,daylight_hours,sed_total," +
            "bsa_pct,clothing,indoors," +
            "sed_head,sed_hands,sed_forearms," +
            "sed_upper_arms,sed_lower_legs," +
            "sed_upper_legs,sed_torso\n"

        let bp = r.bodyPartSED
        let row = "\(isoString(r.date))," +
            "\(r.uvi),\(r.daylightHours)," +
            "\(r.sed),\(r.bsaPercent)," +
            "\"\(r.clothingName)\"," +
            "\(r.indoors ? 1 : 0)," +
            "\(bp.head),\(bp.hands)," +
            "\(bp.forearms),\(bp.upperArms)," +
            "\(bp.lowerLegs),\(bp.upperLegs)," +
            "\(bp.torso)\n"

        appendToFile(url: file,
                     header: header, row: row)
    }

    // VitaminD/YYYY-MM-DD_vitamind.csv
    static func logVitaminD(_ r: DayReading) {
        guard let dir = uvitaDir else { return }
        let dateStr = dayString(r.date)
        let file = dir
            .appendingPathComponent("VitaminD")
            .appendingPathComponent(
                "\(dateStr)_vitamind.csv")

        let header = "timestamp,plasma_nmol_l," +
            "sed,oral_ug,bsa_pct,uvi\n"
        let row = "\(isoString(r.date))," +
            "\(r.plasmaLevel),\(r.sed)," +
            "\(r.oralUg),\(r.bsaPercent)," +
            "\(r.uvi)\n"

        appendToFile(url: file,
                     header: header, row: row)
    }

    // Diet/YYYY-MM-DD_diet.csv — called from DataStore
    static func logDiet(_ entry: FoodLogEntry) {
        guard let dir = uvitaDir else { return }
        let dateStr = dayString(entry.date)
        let file = dir
            .appendingPathComponent("Diet")
            .appendingPathComponent(
                "\(dateStr)_diet.csv")

        let header = "timestamp,food_name,brand," +
            "vitamin_d_ug,serving\n"
        let row = "\(isoString(entry.date))," +
            "\"\(entry.name)\"," +
            "\"\(entry.brand)\"," +
            "\(entry.vitaminDug)," +
            "\"\(entry.servingDesc)\"\n"

        appendToFile(url: file,
                     header: header, row: row)
    }

    // Append a row — write header if file is new
    private static func appendToFile(
        url: URL, header: String, row: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? header.write(to: url,
                atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(
            forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = row.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    private static func dayString(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: d)
    }

    private static func isoString(_ d: Date) -> String {
        let fmt = ISO8601DateFormatter()
        return fmt.string(from: d)
    }
}
