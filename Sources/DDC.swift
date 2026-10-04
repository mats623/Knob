import Foundation
import IOKit

/// Talks to an external monitor over DDC/CI (Apple Silicon, via IOAVService).
final class DDCDisplay {
    static let volumeCode: UInt8 = 0x62

    private let service: IOAVService

    private init(service: IOAVService) {
        self.service = service
    }

    static func externalDisplays() -> [DDCDisplay] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var displays: [DDCDisplay] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
            displays.append(DDCDisplay(service: service))
        }
        return displays
    }

    func read(_ code: UInt8) -> (current: Int, max: Int)? {
        guard let reply = communicate([code], replyLength: 11), reply[4] == code else { return nil }
        let max = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        return max > 0 ? (current, max) : nil
    }

    @discardableResult
    func write(_ code: UInt8, _ value: Int) -> Bool {
        communicate([code, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)], replyLength: 0) != nil
    }

    private func communicate(_ send: [UInt8], replyLength: Int) -> [UInt8]? {
        var packet: [UInt8] = [0x80 | UInt8(send.count + 1), UInt8(send.count)] + send + [0]
        var checksum: UInt8 = send.count == 1 ? 0x6E : 0x6E ^ 0x51
        for byte in packet.dropLast() { checksum ^= byte }
        packet[packet.count - 1] = checksum

        for _ in 0..<4 {
            var wrote = false
            for _ in 0..<2 {
                usleep(10_000)
                if IOAVServiceWriteI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == kIOReturnSuccess {
                    wrote = true
                }
            }
            if wrote && replyLength == 0 { return [] }
            if wrote {
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: replyLength)
                if IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(replyLength)) == kIOReturnSuccess {
                    var expected: UInt8 = 0x50
                    for byte in reply.dropLast() { expected ^= byte }
                    if expected == reply.last { return reply }
                }
            }
            usleep(20_000)
        }
        return nil
    }
}
