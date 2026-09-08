import Foundation

enum NativeReaderMode: String, CaseIterable, Identifiable {
    case single, spread, continuous
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "单页"
        case .spread: return "双页"
        case .continuous: return "纵向连续"
        }
    }
}
enum NativeReaderFit: String, CaseIterable, Identifiable {
    case page, width
    var id: String { rawValue }
    var title: String { self == .page ? "适应页面" : "适应宽度" }
}
enum NativeReaderBackground: String, CaseIterable, Identifiable {
    case system, dark, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .dark: return "黑色"
        case .paper: return "纸色"
        }
    }
}
enum NativeReaderLayout {
    static func indices(page: Int, count: Int, mode: NativeReaderMode, coverAlone: Bool) -> [Int] {
        guard count > 0 else { return [] }
        let page = min(max(0, page), count - 1)
        guard mode == .spread else { return [page] }
        if coverAlone && page == 0 { return [0] }
        let offset = coverAlone ? 1 : 0
        let start = offset + ((page - offset) / 2) * 2
        return Array(start..<min(start + 2, count))
    }
    static func destination(page: Int, count: Int, mode: NativeReaderMode, coverAlone: Bool, delta: Int) -> Int? {
        let spread = indices(page: page, count: count, mode: mode, coverAlone: coverAlone)
        guard let first = spread.first, let last = spread.last else { return nil }
        if delta > 0 { return last + 1 < count ? last + 1 : nil }
        guard first > 0 else { return nil }
        return indices(page: first - 1, count: count, mode: mode, coverAlone: coverAlone).first
    }
}
