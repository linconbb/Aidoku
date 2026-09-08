import AppKit
import SwiftUI

struct NativeReaderView: View {
    @ObservedObject var model: MacModel
    @State private var jump = ""
    @State private var scrollPage: Int?
    @State private var settings = false
    @GestureState private var magnification = 1.0

    private var background: Color {
        switch model.readerBackground {
        case .system: return Color(nsColor: .textBackgroundColor)
        case .dark: return Color(red: 0.07, green: 0.07, blue: 0.08)
        case .paper: return Color(red: 0.95, green: 0.92, blue: 0.85)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.closeReader() } label: { Label("返回", systemImage: "chevron.backward") }
                Text(model.readerTitle).lineLimit(1).help(model.readerTitle)
                Spacer(minLength: 8)
                Picker("阅读模式", selection: $model.readerMode) {
                    ForEach(NativeReaderMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 110)
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .help("阅读设置")
                    .popover(isPresented: $settings) { NativeReaderSettings(model: model).padding().frame(width: 310) }
                Button { model.saveChapter() } label: { Image(systemName: "square.and.arrow.down") }
                    .help("保存本章为 CBZ").disabled(model.exportBusy || model.pageCount == 0)
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("全屏")
            }.padding(10)
            Divider()
            GeometryReader { geometry in
                Group {
                    if model.readerMode == .continuous {
                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<model.pageCount, id: \.self) { index in
                                    NativeReaderPage(model: model, index: index, width: geometry.size.width * model.readerZoom,
                                                     fittedHeight: nil, session: model.readerSession)
                                        .id(index)
                                }
                            }.scrollTargetLayout()
                        }
                        .scrollPosition(id: $scrollPage, anchor: .top)
                        .onAppear { scrollPage = model.page }
                        .onChange(of: scrollPage) { _, newValue in
                            if let newValue { model.recordVisiblePage(newValue) }
                        }
                        .onChange(of: model.page) { _, value in
                            if scrollPage != value { scrollPage = value }
                        }
                    } else {
                        let indices = model.rightToLeft ? Array(model.visiblePageIndices.reversed()) : model.visiblePageIndices
                        let width = max(1, (geometry.size.width - CGFloat(max(0, model.visiblePageIndices.count - 1)) * 4) / CGFloat(max(1, model.visiblePageIndices.count)))
                        ScrollView([.horizontal, .vertical]) {
                            HStack(spacing: 4) {
                                ForEach(Array(indices), id: \.self) { index in
                                    NativeReaderPage(model: model, index: index,
                                        width: width * model.readerZoom * magnification,
                                        fittedHeight: model.readerFit == .page ? geometry.size.height * model.readerZoom * magnification : nil,
                                        session: model.readerSession)
                                }
                            }
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.readerZoom = model.readerZoom > 1 ? 1 : 2 }
                        }
                        .id("\(model.readerSession)-\(model.visiblePageIndices.first ?? 0)")
                        .gesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }
                            .onEnded { model.readerZoom = min(3, max(0.5, model.readerZoom * $0)) })
                    }
                }.background(background)
            }
            if model.exportBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.exportProgress).font(.caption)
                    Button("取消保存") { model.cancelExport() }
                    Spacer()
                }.padding(8)
            }
            Divider()
            HStack(spacing: 10) {
                Button { Task { await model.changeChapter(-1) } } label: { Image(systemName: "backward.end") }
                    .help("上一章").disabled(model.adjacentChapter(-1) == nil || model.busy)
                Button { model.turnVisual(-1) } label: { Image(systemName: "chevron.left") }
                    .help(model.rightToLeft ? "下一页" : "上一页")
                    .disabled(model.pageDestination(model.rightToLeft ? 1 : -1) == nil)
                TextField("页码", text: $jump).multilineTextAlignment(.center).frame(width: 48)
                    .onSubmit { if let value = Int(jump) { model.renderPage(value - 1) } else { jump = "\(model.page + 1)" } }
                Text("/ \(model.pageCount)").monospacedDigit()
                Button { model.turnVisual(1) } label: { Image(systemName: "chevron.right") }
                    .help(model.rightToLeft ? "上一页" : "下一页")
                    .disabled(model.pageDestination(model.rightToLeft ? -1 : 1) == nil)
                Button { Task { await model.changeChapter(1) } } label: { Image(systemName: "forward.end") }
                    .help("下一章").disabled(model.adjacentChapter(1) == nil || model.busy)
                Spacer()
                Button { model.readerZoom = max(0.5, model.readerZoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                Button("\(Int(model.readerZoom * 100))%") { model.readerZoom = 1 }.frame(width: 54)
                Button { model.readerZoom = min(3, model.readerZoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
            }.padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { jump = "\(model.page + 1)" }
        .onChange(of: model.page) { jump = "\(model.page + 1)" }
        .onChange(of: model.readerMode) { scrollPage = model.page }
    }
}

struct NativeReaderSettings: View {
    @ObservedObject var model: MacModel
    var body: some View {
        Form {
            Picker("阅读模式", selection: $model.readerMode) {
                ForEach(NativeReaderMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("从右向左翻页", isOn: $model.rightToLeft)
            Toggle("封面单独显示", isOn: $model.coverAlone)
                .disabled(model.readerMode != .spread)
            Picker("图片缩放", selection: $model.readerFit) {
                ForEach(NativeReaderFit.allCases) { Text($0.title).tag($0) }
            }.disabled(model.readerMode == .continuous)
            Picker("背景", selection: $model.readerBackground) {
                ForEach(NativeReaderBackground.allCases) { Text($0.title).tag($0) }
            }
            Text("设置会自动保存。方向键翻页，空格下一页，双击图片切换 100% / 200%。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NativeReaderPage: View {
    @ObservedObject var model: MacModel
    let index: Int
    let width: CGFloat
    let fittedHeight: CGFloat?
    let session: UUID
    @State private var content: NativeReaderContent?
    @State private var failure: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let image = content?.image {
                Image(nsImage: image).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: fittedHeight ?? width * image.size.height / max(image.size.width, 1))
            } else if let text = content?.text {
                Text(text).textSelection(.enabled).foregroundStyle(.primary)
                    .padding(24).frame(width: width, alignment: .leading)
                    .frame(minHeight: fittedHeight ?? 200)
                    .background(Color(nsColor: .textBackgroundColor))
            } else if let failure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("第 \(index + 1) 页加载失败")
                    Text(failure).font(.caption).lineLimit(4)
                    Button("重试") { retry += 1 }
                }.padding().frame(width: width, height: fittedHeight ?? max(240, width * 1.3))
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                ProgressView("第 \(index + 1) 页")
                    .frame(width: width, height: fittedHeight ?? max(240, width * 1.3))
            }
        }
        .task(id: "\(session)-\(index)-\(retry)") {
            content = nil; failure = nil
            do {
                let loaded = try await model.readerContent(at: index, session: session)
                try Task.checkCancellation()
                content = loaded
            } catch is CancellationError {
            } catch { failure = error.localizedDescription }
        }
        .onDisappear { content = nil }
    }
}
