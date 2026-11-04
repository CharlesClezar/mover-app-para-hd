import SwiftUI
import UniformTypeIdentifiers

// MARK: - Modelo

enum Status {
    case pending, working
    case done(String)
    case failed(String)
}

struct Item: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .pending
    var name: String { url.deletingPathExtension().lastPathComponent }
}

func shQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func run(_ cmd: String, admin: Bool) -> (ok: Bool, out: String) {
    let p = Process()
    if admin {
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"\(esc)\" with administrator privileges"]
    } else {
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
    }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (false, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus == 0, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func sizeKB(_ path: String) -> Int {
    let r = run("/usr/bin/du -sk \(shQuote(path)) | cut -f1", admin: false)
    return Int(r.out) ?? 0
}

func fmt(_ kb: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file)
}

func isSymlink(_ path: String) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
}

/// Move o app para `dest` e deixa um link no lugar. Se o app já está em `dest`, só cria o link em /Applications.
func moveApp(_ url: URL, dest: String) -> Status {
    let src = url.path
    let name = url.lastPathComponent
    guard name.hasSuffix(".app") else { return .failed("Não é um aplicativo (.app)") }
    if isSymlink(src) { return .failed("Já é um link — nada a fazer") }
    let target = dest + "/" + name
    let fm = FileManager.default
    let cmd: String
    var freed = 0

    if src.hasPrefix(dest + "/") {
        let link = "/Applications/" + name
        if fm.fileExists(atPath: link) || isSymlink(link) { return .failed("Já existe em Aplicativos") }
        cmd = "/bin/ln -s \(shQuote(target)) \(shQuote(link))"
    } else {
        if fm.fileExists(atPath: target) { return .failed("Já existe uma cópia no HD") }
        freed = sizeKB(src)
        cmd = "/usr/bin/ditto \(shQuote(src)) \(shQuote(target)) && /bin/rm -rf \(shQuote(src)) && /bin/ln -s \(shQuote(target)) \(shQuote(src))"
    }

    var r = run(cmd, admin: false)
    if !r.ok { r = run(cmd, admin: true) }
    if r.ok { return .done(freed > 0 ? "Movido · \(fmt(freed)) liberados no SSD" : "Link criado em Aplicativos") }
    return .failed(r.out.isEmpty ? "Falhou" : r.out)
}

@MainActor
final class Model: ObservableObject {
    @Published var items: [Item] = []
    @Published var destination: String? = UserDefaults.standard.string(forKey: "destino")
    @Published var busy = false
    @Published var targeted = false
    private var queue: [UUID] = []

    var freedKB = 0

    func chooseDestination() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Usar esta pasta"
        p.message = "Escolha a pasta no HD onde os apps ficarão guardados"
        if p.runModal() == .OK, let u = p.url {
            destination = u.path
            UserDefaults.standard.set(u.path, forKey: "destino")
        }
    }

    func chooseApps() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.applicationBundle]
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.message = "Escolha os apps para mover para o HD"
        if p.runModal() == .OK { add(p.urls) }
    }

    func add(_ urls: [URL]) {
        if destination == nil { chooseDestination() }
        guard destination != nil else { return }
        let apps = urls.filter { $0.pathExtension == "app" }
        for u in apps where !items.contains(where: { $0.url == u && { if case .done = $0.status { return false }; return true }($0) }) {
            let it = Item(url: u)
            items.insert(it, at: 0)
            queue.append(it.id)
        }
        if !busy { Task { await drain() } }
    }

    func drain() async {
        busy = true
        while let id = queue.first {
            queue.removeFirst()
            guard let dest = destination, let idx = items.firstIndex(where: { $0.id == id }) else { continue }
            items[idx].status = .working
            let url = items[idx].url
            let result = await Task.detached { moveApp(url, dest: dest) }.value
            if let i = items.firstIndex(where: { $0.id == id }) { items[i].status = result }
        }
        busy = false
    }

    func clear() { items.removeAll { if case .working = $0.status { return false }; return true } }
}

// MARK: - Interface

struct AppRow: View {
    let item: Item
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                switch item.status {
                case .pending: Text("Na fila…").foregroundStyle(.secondary).font(.caption)
                case .working: Text("Movendo para o HD…").foregroundStyle(.secondary).font(.caption)
                case .done(let m): Text(m).foregroundStyle(.green).font(.caption)
                case .failed(let m): Text(m).foregroundStyle(.red).font(.caption).lineLimit(2)
                }
            }
            Spacer()
            switch item.status {
            case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
            case .working: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.title3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct ContentView: View {
    @StateObject var model = Model()
    var targeted: Bool { model.targeted }

    var body: some View {
        VStack(spacing: 16) {
            header
            destinationCard
            dropZone
            if !model.items.isEmpty { list }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onOpenURL { model.add([$0]) }
    }

    var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 24)).foregroundStyle(.white)
            }.frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mover App para HD").font(.system(size: 22, weight: .bold))
                Text("Libere espaço no SSD sem quebrar seus apps").foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    var destinationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("PASTA DE DESTINO NO HD").font(.caption2).foregroundStyle(.secondary)
                if let d = model.destination {
                    Text(d).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Nenhuma pasta escolhida").foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(model.destination == nil ? "Escolher…" : "Alterar…") { model.chooseDestination() }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: model.items.isEmpty ? 44 : 30))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
                .scaleEffect(targeted ? 1.15 : 1)
            Text(targeted ? "Solte para mover" : "Arraste os apps aqui").font(.headline)
            if model.items.isEmpty {
                Text("Arraste da pasta Aplicativos (ou da pasta do HD, para só criar o link)")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Escolher apps…") { model.chooseApps() }
        }
        .frame(maxWidth: .infinity, minHeight: model.items.isEmpty ? 220 : 120, maxHeight: model.items.isEmpty ? .infinity : 120)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.5),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { model.targeted }, set: { model.targeted = $0 })) { providers in
            for p in providers {
                p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async { model.add([url]) }
                    }
                }
            }
            return true
        }
    }

    var list: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Atividade").font(.headline)
                Spacer()
                Button("Limpar") { model.clear() }.buttonStyle(.link)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.items) { it in
                        AppRow(item: it)
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxHeight: .infinity)
    }
}

@main
struct MoverApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentMinSize)
    }
}
