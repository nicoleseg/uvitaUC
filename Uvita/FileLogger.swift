import Foundation

struct FileLogger {

    static var uvitaDir: URL? {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask).first
    }

    static func setup() {
        guard let base = uvitaDir else { return }
        let folders = ["UVlogs", "Diet", "VitaminD", "Corrections", "LabeledReadings"]
        for folder in folders {
            let url = base.appendingPathComponent(folder)
            try? FileManager.default
                .createDirectory(at: url,
                    withIntermediateDirectories: true)
        }
    }

    static func log(reading: DayReading) {
        setup()
        if reading.label != nil {
            // Manual Log Now reading — goes only to labeled_readings.csv.
            // Kept out of UVlogs/VitaminD so those files remain a clean
            // passive background sensor stream for evaluation.
            logLabeled(reading)
        } else {
            // Automatic 5-min reading — goes to UVlogs + VitaminD only.
            logUV(reading)
            logVitaminD(reading)
        }
    }

    // UVlogs/YYYY-MM-DD_uv.csv
    // Now includes uvi column so you can see
    // the rolling-average value that was actually used
    static func logUV(_ r: DayReading) {
        guard let dir = uvitaDir else { return }
        let file = dir
            .appendingPathComponent("UVlogs")
            .appendingPathComponent("\(dayString(r.date))_uv.csv")

        let header = "timestamp,uvi,raw_uvi,interval_hours,sed," +
            "bsa_pct,clothing,indoors,uncertain," +
            "sed_head,sed_neck,sed_upper_arms,sed_forearms," +
            "sed_hands,sed_torso,sed_upper_legs,sed_lower_legs\n"

        let bp = r.bodyPartSED
        let row = "\(iso(r.date))," +
            "\(r.uvi),\(r.rawUVI),\(r.intervalHours)," +
            "\(r.sed),\(r.bsaPercent)," +
            "\"\(r.clothingName)\"," +
            "\(r.indoors ? 1 : 0)," +
            "\(r.isUncertain ? 1 : 0)," +
            "\(bp.head),\(bp.neck)," +
            "\(bp.upperArms),\(bp.forearms)," +
            "\(bp.hands),\(bp.torso)," +
            "\(bp.upperLegs),\(bp.lowerLegs)\n"

        appendToFile(url: file, header: header, row: row)
    }


    // VitaminD/YYYY-MM-DD_vitamind.csv
    static func logVitaminD(_ r: DayReading) {
        guard let dir = uvitaDir else { return }
        let file = dir
            .appendingPathComponent("VitaminD")
            .appendingPathComponent("\(dayString(r.date))_vitamind.csv")

        let header = "timestamp,plasma_nmol_l,sed,oral_ug,bsa_pct,uvi\n"
        let row    = "\(iso(r.date)),\(r.plasmaLevel),\(r.sed)," +
                     "\(r.oralUg),\(r.bsaPercent),\(r.uvi)\n"

        appendToFile(url: file, header: header, row: row)
    }

    // Diet/YYYY-MM-DD_diet.csv
    static func logDiet(_ entry: FoodLogEntry) {
        guard let dir = uvitaDir else { return }
        let file = dir
            .appendingPathComponent("Diet")
            .appendingPathComponent("\(dayString(entry.date))_diet.csv")

        let header = "timestamp,food_name,brand,vitamin_d_ug,serving\n"
        let row    = "\(iso(entry.date))," +
                     "\"\(entry.name)\",\"\(entry.brand)\"," +
                     "\(entry.vitaminDug),\"\(entry.servingDesc)\"\n"

        appendToFile(url: file, header: header, row: row)
    }

    // Corrections/corrections.csv — one global file, appended.
    // Records every time the user overrides auto indoor detection.
    // Useful for evaluating where/when the detector is wrong.
    static func logCorrection(date: Date,
                               lat: Double, lon: Double,
                               accuracy: Double,
                               autoDetected: Bool,
                               userSet: Bool,
                               uvi: Double,
                               sed: Double) {
        guard let dir = uvitaDir else { return }
        setup()
        let file = dir
            .appendingPathComponent("Corrections")
            .appendingPathComponent("corrections.csv")

        // Self-contained — no need to cross-reference UVlogs.
        // uvi/sed are the corrected values that went into the model
        // (0 if user set indoors, actual UVI if user set outdoors).
        let header = "timestamp,lat,lon,gps_accuracy_m," +
                     "auto_detected_indoor,user_set_indoor," +
                     "was_wrong,corrected_uvi,corrected_sed\n"
        let wasWrong = autoDetected != userSet
        let row = "\(iso(date))," +
                  "\(lat),\(lon),\(accuracy)," +
                  "\(autoDetected ? 1 : 0)," +
                  "\(userSet ? 1 : 0)," +
                  "\(wasWrong ? 1 : 0)," +
                  "\(uvi),\(sed)\n"

        appendToFile(url: file, header: header, row: row)
    }

    // LabeledReadings/labeled_readings.csv — one global file.
    // Written only for manual "Log now" readings that have a label.
    // Contains full snapshot: label, GPS, all model inputs/outputs.
    // Primary dataset for ground-truth indoor/outdoor evaluation.
    static func logLabeled(_ r: DayReading) {
        guard let dir = uvitaDir,
              let label = r.label else { return }
        let file = dir
            .appendingPathComponent("LabeledReadings")
            .appendingPathComponent("labeled_readings.csv")

        let header = "timestamp,label,lat,lon,gps_accuracy_m," +
                     "indoors,uncertain,uvi,sed," +
                     "bsa_pct,clothing,plasma_nmol_l,oral_ug\n"
        let row = "\(iso(r.date))," +
                  "\"\(label)\"," +
                  "\(r.lat),\(r.lon),\(r.gpsAccuracy)," +
                  "\(r.indoors ? 1 : 0)," +
                  "\(r.isUncertain ? 1 : 0)," +
                  "\(r.uvi),\(r.sed)," +
                  "\(r.bsaPercent)," +
                  "\"\(r.clothingName)\"," +
                  "\(r.plasmaLevel),\(r.oralUg)\n"

        appendToFile(url: file, header: header, row: row)
    }

    // ── Helpers ───────────────────────────────────────────────

    private static func appendToFile(url: URL,
                                      header: String,
                                      row: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? header.write(to: url,
                atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
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

    private static func iso(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}
