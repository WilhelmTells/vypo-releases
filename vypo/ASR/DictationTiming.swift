import Darwin
import Foundation

/// How long each part of one transcription took. Only numbers: no dictated text ever goes into the log.
struct TranscriptionTiming: Sendable, Equatable {
    var decode: Duration = .zero
}

/// The Mac's memory when a dictation is processed.
struct MemorySnapshot: Sendable, Equatable {
    /// `kern.memorystatus_level`, the free share that `memory_pressure` reports.
    var freePercent: Int
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    var pressureLevel: Int
    var compressedBytes: UInt64
    /// vypo's own footprint (as Activity Monitor's “Memory”).
    var footprintBytes: UInt64

    static func current() -> MemorySnapshot {
        MemorySnapshot(freePercent: sysctlInt("kern.memorystatus_level") ?? -1,
                       pressureLevel: sysctlInt("kern.memorystatus_vm_pressure_level") ?? -1,
                       compressedBytes: compressed(), footprintBytes: footprint())
    }

    var pressure: String {
        switch pressureLevel {
        case 1: "normal"
        case 2: "warning"
        case 4: "critical"
        default: "unknown"
        }
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    private static func compressed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(stats.compressor_page_count) * UInt64(getpagesize()) : 0
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// The one log line per dictation (notice level, kept by macOS), with numbers only.
enum DictationTimingLog {
    static func line(audio: TimeInterval, pause: TimeInterval?, transcribe: Duration, asr: TranscriptionTiming?,
                     text: Duration, ready: Duration, memory: MemorySnapshot) -> String {
        var parts = ["audio \(String(format: "%.1f", audio)) s",
                     pause.map(Self.pause) ?? "first since launch"]
        var steps = "transcribe \(transcribe.milliseconds) ms"
        if let asr {
            steps += " (decode \(asr.decode.milliseconds) ms"
            steps += ")"
        }
        parts.append(steps)
        parts.append("text \(text.milliseconds) ms")
        parts.append("ready \(ready.milliseconds) ms")
        parts.append("memory free \(memory.freePercent) %, pressure \(memory.pressure), compressed \(gigabytes(memory.compressedBytes)) GB, vypo \(memory.footprintBytes / 1_048_576) MB")
        return "Dictation timing: " + parts.joined(separator: "; ")
    }

    private static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_073_741_824) }
    private static func pause(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "pause \(Int(max(seconds, 0).rounded())) s" : "pause \(String(format: "%.1f", seconds / 60)) min"
    }
}
