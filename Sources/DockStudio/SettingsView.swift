import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case dock, icons, groups, tiles, behavior, themes, connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dock: return "Dock"
        case .icons: return "Iconen"
        case .groups: return "Groepen"
        case .tiles: return "Tegels"
        case .behavior: return "Gedrag"
        case .themes: return "Thema's"
        case .connections: return "Koppelingen"
        }
    }

    var symbol: String {
        switch self {
        case .dock: return "dock.rectangle"
        case .icons: return "square.grid.2x2"
        case .groups: return "folder"
        case .tiles: return "rectangle.split.3x1"
        case .behavior: return "wand.and.stars"
        case .themes: return "paintpalette"
        case .connections: return "link"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var ha = HAStore.shared
    @ObservedObject var updater = Updater.shared
    @ObservedObject var prefs = DockPrefs.shared
    @ObservedObject var dockModel = DockModel.shared
    @State private var updateTokenInput = ""
    @AppStorage("dockstudio.settingsFloating") private var floating = false
    @State private var tab: SettingsTab = .dock
    @State private var tokenInput = ""
    @State private var entityFilter = ""
    @State private var haPickerGroup: UUID?
    @State private var haStyleEntity: String?
    @ObservedObject var tileStore = TileStore.shared
    @State private var tilePickerID: UUID?
    @State private var iconPickerID: UUID?
    @State private var tileFilter = ""
    @State private var tileToken = ""
    @State private var groupHAFilter = ""
    @FocusState private var searchFocused: Bool
    @State private var paletteIndex = 0
    @State private var paletteStyle: DockStyle = .glass
    @State private var wallpaperPalette: Palette?
    @State private var wallpaperMessage = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
            detail
                .frame(minWidth: 520)
        }
        .frame(minWidth: 780, minHeight: 720)
    }

    // MARK: Thema-lijst

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Thema's")
                    .font(.headline)
                Spacer()
                Text("\(store.themes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            List(selection: $store.selectedID) {
                ForEach(store.themes) { t in
                    ThemeRow(theme: t).tag(t.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 6) {
                Button { store.duplicateSelected() } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Dupliceer het geselecteerde thema")

                Button { store.deleteSelected() } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.themes.count <= 1)
                .help("Verwijder het geselecteerde thema")

                Spacer()

                Menu {
                    Button("Exporteer thema…") { store.exportSelected() }
                    Button("Importeer thema…") { store.importTheme() }
                    Divider()
                    Button("Herstel standaardthema's") { store.resetToPresets() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Importeren, exporteren en herstellen")
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    // MARK: Rechterkant: kopbalk, tabbladen, inhoud

    private var detail: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            tabBar
            Divider()
            Form { content }
                .formStyle(.grouped)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Naam", text: store.binding(\.name))
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Text("Je bewerkt het actieve thema. Wijzigingen zijn direct zichtbaar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                floating.toggle()
                SettingsWindow.apply()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: floating ? "pin.fill" : "pin")
                    if floating { Text("Vastgepind").font(.caption) }
                }
                .foregroundColor(floating ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Houd dit venster bovenop andere apps")
            VStack(alignment: .trailing, spacing: 2) {
                Toggle("Mijn dock tonen", isOn: $store.dockEnabled)
                    .toggleStyle(.switch)
                Text("Verbergt het echte Dock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { t in
                VStack(spacing: 3) {
                    Image(systemName: t.symbol)
                        .font(.system(size: 18))
                    Text(t.title)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundColor(tab == t ? .accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tab == t ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { tab = t }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .dock: dockTab
        case .icons: iconsTab
        case .groups: groupsTab
        case .tiles: tilesTab
        case .behavior: behaviorTab
        case .themes: themesTab
        case .connections: connectionsTab
        }
    }

    // MARK: Tab: Dock

    @ViewBuilder
    private var dockTab: some View {
        Section {
            slider("Verticaal (afstand tot onderrand)", store.binding(\.bottomMargin), -150...300)
            slider("Horizontaal (0 = midden)", store.binding(\.offsetX), -1000...1000)
            note("Een negatieve waarde laat de dock deels onder de schermrand zakken. In de vakjes kun je ook een exacte waarde typen, buiten het bereik van de schuif.")
        } header: {
            sectionHeader("Positie", "arrow.up.and.down.and.arrow.left.and.right")
        }

        Section {
            Toggle("Vaste breedte", isOn: Binding(
                get: { store.theme.fixedWidth > 0 },
                set: { on in store.binding(\.fixedWidth).wrappedValue = on ? 700 : 0 }
            ))
            if store.theme.fixedWidth > 0 {
                slider("Breedte", store.binding(\.fixedWidth), 200...3000)
                note("Past alles niet in deze breedte, dan scroll je horizontaal over de dock met twee vingers of het muiswiel.")
            }
        } header: {
            sectionHeader("Breedte", "arrow.left.and.right")
        }

        Section {
            Toggle("Dock-achtergrond tonen", isOn: store.binding(\.showBackground))
            note("Uit = alleen de iconen, zonder balk, rand en schaduw.")
        } header: {
            sectionHeader("Achtergrond", "rectangle.dashed")
        }

        Section {
            Picker("Vorm", selection: store.binding(\.shape)) {
                ForEach(DockShape.allCases) { Text($0.label).tag($0) }
            }
            slider("Hoekradius", store.binding(\.cornerRadius), 0...50)
        } header: {
            sectionHeader("Vorm", "square.on.circle")
        }
        .disabled(!store.theme.showBackground)

        Section {
            ColorPicker("Kleur", selection: store.colorBinding(\.colorA), supportsOpacity: true)
            Toggle("Kleurverloop", isOn: store.binding(\.useGradient))
            if store.theme.useGradient {
                ColorPicker("Tweede kleur", selection: store.colorBinding(\.colorB), supportsOpacity: true)
            }
            Toggle("Doorzichtige blur (glas)", isOn: store.binding(\.useBlur))
        } header: {
            sectionHeader("Kleur", "paintbrush")
        }
        .disabled(!store.theme.showBackground)

        Section {
            ColorPicker("Randkleur", selection: store.colorBinding(\.borderColor), supportsOpacity: true)
            slider("Randdikte", store.binding(\.borderWidth), 0...8, decimals: 1)
            slider("Schaduw", store.binding(\.shadowRadius), 0...40)
        } header: {
            sectionHeader("Rand en schaduw", "square.dashed")
        }
        .disabled(!store.theme.showBackground)
    }

    // MARK: Tab: Iconen

    @ViewBuilder
    private var iconsTab: some View {
        Section {
            slider("Icoongrootte", store.binding(\.iconSize), 24...96)
            slider("Ruimte tussen iconen", store.binding(\.spacing), 0...30)
        } header: {
            sectionHeader("Maten", "arrow.up.left.and.arrow.down.right")
        }

        Section {
            slider("Boven", store.binding(\.paddingTop), 0...40)
            slider("Onder", store.binding(\.paddingBottom), 0...40)
            slider("Links", store.binding(\.paddingLeft), 0...60)
            slider("Rechts", store.binding(\.paddingRight), 0...60)
        } header: {
            sectionHeader("Marges binnen de dock", "rectangle.inset.filled")
        }

        Section {
            Picker("Icoonvorm", selection: store.binding(\.iconShape)) {
                ForEach(IconShape.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Achtergrond achter iconen", isOn: store.binding(\.iconBackgroundEnabled))
            if store.theme.iconBackgroundEnabled {
                ColorPicker("Achtergrondkleur", selection: store.colorBinding(\.iconBackgroundColor), supportsOpacity: true)
            }
            slider("Binnenmarge icoon", store.binding(\.iconInset), 0...20)
            slider("Schaduw onder iconen", store.binding(\.iconShadow), 0...20)
        } header: {
            sectionHeader("Icoonvorm", "app")
        }

        Section {
            Toggle("Naam tonen bij hover", isOn: store.binding(\.showLabels))
            ColorPicker("Kleur actief-bolletje", selection: store.colorBinding(\.indicatorColor), supportsOpacity: true)
        } header: {
            sectionHeader("Labels en indicator", "tag")
        }
    }

    // MARK: Tab: Gedrag

    @ViewBuilder
    private var behaviorTab: some View {
        Section {
            slider("Vergroting (1 = uit)", store.binding(\.magnification), 1...2.5, decimals: 2)
            slider("Bereik van vergroting", store.binding(\.magnificationRange), 0.5...4, decimals: 1)
        } header: {
            sectionHeader("Vergroting", "plus.magnifyingglass")
        }

        Section {
            Toggle("Glow achter het icoon", isOn: store.binding(\.glowEnabled))
            if store.theme.glowEnabled {
                ColorPicker("Glow-kleur", selection: store.colorBinding(\.glowColor), supportsOpacity: true)
                slider("Glow-grootte", store.binding(\.glowSize), 0.6...2.5, decimals: 1)
                slider("Glow-sterkte", store.binding(\.glowIntensity), 0...1, decimals: 2)
            }
            Toggle("Andere iconen dimmen", isOn: store.binding(\.dimOthers))
            if store.theme.dimOthers {
                slider("Mate van dimmen", store.binding(\.dimAmount), 0...0.95, decimals: 2)
                Toggle("Ook kleur verminderen", isOn: store.binding(\.dimDesaturate))
            }
        } header: {
            sectionHeader("Hover-effecten", "sparkles")
        }

        Section {
            slider("Reactiesnelheid", store.binding(\.animResponse), 0.05...0.8, decimals: 2)
            slider("Veerkracht (laag = meer wiebel)", store.binding(\.animDamping), 0.3...1, decimals: 2)
            Toggle("Stuiteren bij openen van een app", isOn: store.binding(\.launchBounce))
            slider("Tijd voor verbergen/tonen (sec)", store.binding(\.fadeDuration), 0...1, decimals: 2)
        } header: {
            sectionHeader("Animatie", "waveform.path")
        }

        Section {
            Picker("Gedrag", selection: $store.windowMode) {
                ForEach(WindowMode.allCases) { Text($0.label).tag($0) }
            }
            switch store.windowMode {
            case .none:
                note("Vensters kunnen over de dock heen liggen.")
            case .reserve:
                note("Vensters worden kleiner of omhoog geschoven zodat ze niet onder de dock vallen.")
            case .smartHide:
                note("De dock verdwijnt als een venster erover ligt. Muis onderaan het scherm = dock terug.")
            }
            if !WindowAvoider.isTrusted {
                Text("Toegang nodig: zet Dokko (of Terminal, als je met swift run start) aan onder Privacy en beveiliging > Toegankelijkheid.")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button("Vraag toegang") { WindowAvoider.requestTrust() }
                    Button("Open instellingen") { WindowAvoider.openSystemSettings() }
                    Button("Controleer opnieuw") { store.objectWillChange.send() }
                }
            }
        } header: {
            sectionHeader("Vensters van andere apps", "macwindow")
        }

        Section {
            updatesSection
        } header: {
            sectionHeader("Updates", "arrow.down.circle")
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        LabeledContent("Huidige versie", value: updater.currentVersion)
        Toggle("Bij opstarten naar updates zoeken", isOn: $updater.autoCheck)
        HStack {
            Button("Zoek naar updates") { Task { await updater.check() } }
                .disabled(updater.busy)
            if let v = updater.availableVersion {
                Button("Installeer \(v)") { Task { await updater.install() } }
                    .disabled(updater.busy)
            }
            if updater.busy { ProgressView().controlSize(.small) }
        }
        if !updater.status.isEmpty { note(updater.status) }
        SecureField("GitHub-token (alleen nodig bij een privé-repo)", text: $updateTokenInput)
            .textFieldStyle(.roundedBorder)
        HStack {
            Button("Bewaar token") { updater.saveToken(updateTokenInput); updateTokenInput = "" }
                .disabled(updateTokenInput.isEmpty)
            if updater.tokenSaved {
                Button("Verwijder token") { updater.saveToken("") }
            }
        }
        note(updater.tokenSaved ? "Token staat in je sleutelhanger."
             : "Maak een fine-grained token met leesrechten (Contents) voor alleen deze repo.")
    }

    // MARK: Tab: Thema's

    @ViewBuilder
    private var themesTab: some View {
        Section {
            Picker("Palet", selection: $paletteIndex) {
                ForEach(Array(Palettes.all.enumerated()), id: \.offset) { i, p in
                    Text(p.name).tag(i)
                }
            }
            swatches(Palettes.all[paletteIndex].palette)
            Picker("Stijl", selection: $paletteStyle) {
                ForEach(DockStyle.allCases) { Text($0.label).tag($0) }
            }
            Button("Maak dock-thema uit palet") {
                store.createFromPalette(Palettes.all[paletteIndex], style: paletteStyle)
            }
            note("Maakt een nieuw thema in de lijst. Daarna kun je het verder aanpassen.")
        } header: {
            sectionHeader("Palet", "swatchpalette")
        }

        Section {
            Button("Lees kleuren uit mijn wallpaper") {
                if let url = WallpaperPalette.currentWallpaperURL(),
                   let p = WallpaperPalette.extract(from: url) {
                    wallpaperPalette = p
                    wallpaperMessage = ""
                } else {
                    wallpaperPalette = nil
                    wallpaperMessage = "Kon het wallpaper niet lezen (bewegende wallpapers worden niet ondersteund)."
                }
            }
            if let wp = wallpaperPalette {
                swatches(wp)
                Button("Maak dock-thema uit wallpaper (stijl hierboven)") {
                    store.createFromPalette(NamedPalette(name: "Wallpaper", palette: wp), style: paletteStyle)
                }
            }
            if !wallpaperMessage.isEmpty { note(wallpaperMessage) }
            Toggle("Wallpaper automatisch volgen", isOn: $store.followWallpaper)
            if store.followWallpaper {
                Picker("Stijl bij volgen", selection: $store.followStyle) {
                    ForEach(DockStyle.allCases) { Text($0.label).tag($0) }
                }
                note("Bij elke wallpaper-wissel wordt het thema \"Wallpaper (auto)\" opnieuw gemaakt en gekozen. Eigen aanpassingen daaraan worden overschreven; dupliceer het thema om ze te bewaren.")
            }
        } header: {
            sectionHeader("Palet uit wallpaper", "photo")
        }

        Section {
            note("Map: ~/.config/dockstudio/themes. Gewone json-bestanden, handig voor je dotfiles.")
            HStack {
                Button("Open map") { store.openThemesFolder() }
                Button("Herlaad uit map") { store.loadFromFolder() }
                Button("Sla alle thema's op") { store.saveAllToFolder() }
            }
            if !store.status.isEmpty { note(store.status) }
        } header: {
            sectionHeader("Thema's als bestanden", "doc.text")
        }
    }

    // MARK: Tab: Groepen

    @ViewBuilder
    private var groupsTab: some View {
        Section {
            note("Een groep verschijnt als één icoon in de dock. Klik erop om de inhoud te zien. Je kunt apps en Home Assistant-acties erin zetten door ze op de groep te slepen, via rechtsklik 'Voeg toe aan groep', of hieronder.")
            Button("Nieuwe groep") { prefs.newGroup(with: nil) }
        } header: {
            sectionHeader("Groepen", "folder")
        }

        ForEach($prefs.groups) { $g in
            Section {
                TextField("Naam", text: $g.name)
                Picker("Weergave", selection: $g.style.layout) {
                    Text("Raster").tag(GroupLayout.grid)
                    Text("Lijst").tag(GroupLayout.list)
                }
                .pickerStyle(.segmented)
                if g.style.layout == .grid {
                    Stepper(value: $g.style.columns, in: 0...8) {
                        Text("Kolommen: " + (g.style.columns == 0 ? "automatisch" : "\(g.style.columns)"))
                    }
                }
                slider("Icoongrootte", $g.style.iconSize, 28...100)
                Toggle("Namen tonen", isOn: $g.style.showNames)
                Picker("Achtergrond", selection: $g.style.background) {
                    Text("Thema").tag(GroupBackground.theme)
                    Text("Glas").tag(GroupBackground.glass)
                    Text("Geen").tag(GroupBackground.none)
                }
                ForEach(g.members, id: \.self) { path in
                    HStack {
                        Image(nsImage: memberIcon(path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(memberName(path))
                        Spacer()
                        Button {
                            prefs.move(path, in: g.id, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(g.members.first == path)
                        Button {
                            prefs.move(path, in: g.id, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(g.members.last == path)
                        Button {
                            prefs.remove(path, from: g.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Voeg app of actie toe") {
                    ForEach(dockModel.items.filter { $0.groupID == nil && !$0.isTrash }) { app in
                        Button(app.name) { prefs.add(app.id, to: g.id) }
                    }
                }
                Button("Kies app van schijf…") { pickApps(for: g.id) }
                Button("Zoek Home Assistant-actie…") {
                    groupHAFilter = ""
                    haPickerGroup = g.id
                }
                .popover(isPresented: Binding(
                    get: { haPickerGroup == g.id },
                    set: { on in if !on, haPickerGroup == g.id { haPickerGroup = nil } }
                ), arrowEdge: .bottom) {
                    haPicker(for: g.id)
                }
                Button("Verwijder groep", role: .destructive) { prefs.delete(g.id) }
            } header: {
                sectionHeader(g.name, "folder")
            }
        }
    }

    // MARK: HA-iconen

    private var haStyleBinding: Binding<HAIconStyle> {
        Binding(get: { ha.config.iconStyle ?? HAIconStyle() },
                set: { ha.config.iconStyle = $0 })
    }

    private func haColorBinding(_ kp: WritableKeyPath<HAIconStyle, RGBA>) -> Binding<Color> {
        Binding(get: { (ha.config.iconStyle ?? HAIconStyle())[keyPath: kp].color },
                set: {
                    var st = ha.config.iconStyle ?? HAIconStyle()
                    st[keyPath: kp] = RGBA(color: $0)
                    ha.config.iconStyle = st
                })
    }

    @ViewBuilder
    private var haStyleSection: some View {
        HStack(spacing: 14) {
            ForEach(Array([("light", true), ("light", false), ("switch", true), ("scene", true),
                           ("lock", false), ("fan", true)].enumerated()), id: \.offset) { _, s in
                Image(nsImage: HAIcon.make(domain: s.0, on: s.1))
                    .resizable()
                    .frame(width: 40, height: 40)
            }
        }
        Picker("Achtergrond van het icoon", selection: haStyleBinding.tile) {
            Text("Afgerond").tag(HATile.rounded)
            Text("Cirkel").tag(HATile.circle)
            Text("Alleen symbool").tag(HATile.none)
        }
        .pickerStyle(.segmented)
        Toggle("Kleur 'aan' uit het thema-accent", isOn: haStyleBinding.useThemeAccent)
        if !haStyleBinding.wrappedValue.useThemeAccent {
            ColorPicker("Kleur als aan", selection: haColorBinding(\.onColor), supportsOpacity: false)
        }
        ColorPicker("Kleur als uit", selection: haColorBinding(\.offColor), supportsOpacity: false)
        Toggle("Kleurverloop", isOn: haStyleBinding.gradient)
        slider("Grootte symbool", haStyleBinding.glyphSize, 0.3...0.8, decimals: 2)
        note("Per entiteit kun je een eigen symbool en kleur kiezen met het penseel-icoon in de lijst hieronder.")
    }

    private func styleButton(_ id: String) -> some View {
        Button { haStyleEntity = id } label: { Image(systemName: "paintbrush") }
            .buttonStyle(.borderless)
            .help("Symbool en kleur aanpassen")
            .popover(isPresented: Binding(
                get: { haStyleEntity == id },
                set: { on in if !on, haStyleEntity == id { haStyleEntity = nil } }
            ), arrowEdge: .bottom) {
                entityStyleEditor(id)
            }
    }

    private func updateEntity(_ id: String, _ change: (inout HADockEntity) -> Void) {
        if let i = ha.config.dockEntities.firstIndex(where: { $0.id == id }) {
            change(&ha.config.dockEntities[i])
        } else if var list = ha.config.groupEntities, let i = list.firstIndex(where: { $0.id == id }) {
            change(&list[i])
            ha.config.groupEntities = list
        }
    }

    private func entityStyleEditor(_ id: String) -> some View {
        let e = (ha.config.dockEntities + (ha.config.groupEntities ?? [])).first { $0.id == id }
        let symbols = ["lightbulb.fill", "lamp.floor.fill", "lamp.desk.fill", "power", "fan.fill", "lock.fill",
                       "sparkles", "moon.fill", "sun.max.fill", "tv.fill", "speaker.wave.2.fill",
                       "thermometer.medium", "door.garage.closed", "blinds.horizontal.closed",
                       "bed.double.fill", "sofa.fill", "house.fill", "bolt.fill"]
        return VStack(alignment: .leading, spacing: 10) {
            Text(e?.name ?? id).font(.headline)
            HStack {
                Image(nsImage: HAIcon.make(domain: e?.domain ?? "switch", on: true,
                                           symbol: e?.symbol, color: e?.color))
                    .resizable().frame(width: 44, height: 44)
                Image(nsImage: HAIcon.make(domain: e?.domain ?? "switch", on: false,
                                           symbol: e?.symbol, color: e?.color))
                    .resizable().frame(width: 44, height: 44)
            }
            TextField("SF Symbol-naam, bijv. lamp.floor.fill", text: Binding(
                get: { e?.symbol ?? "" },
                set: { v in updateEntity(id) { $0.symbol = v.isEmpty ? nil : v } }
            ))
            .textFieldStyle(.roundedBorder)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 6), spacing: 6) {
                ForEach(symbols, id: \.self) { name in
                    Button { updateEntity(id) { $0.symbol = name } } label: {
                        Image(systemName: name).frame(width: 30, height: 26)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Toggle("Eigen kleur", isOn: Binding(
                get: { e?.color != nil },
                set: { on in updateEntity(id) { $0.color = on ? (ha.config.iconStyle ?? HAIconStyle()).onColor : nil } }
            ))
            if e?.color != nil {
                ColorPicker("Kleur als aan", selection: Binding(
                    get: { e?.color?.color ?? .yellow },
                    set: { c in updateEntity(id) { $0.color = RGBA(color: c) } }
                ), supportsOpacity: false)
            }
            Button("Zet terug naar standaard") {
                updateEntity(id) { $0.symbol = nil; $0.color = nil }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func haEntity(for path: String) -> HADockEntity? {
        guard path.hasPrefix("ha:") else { return nil }
        let id = String(path.dropFirst(3))
        return (ha.config.dockEntities + (ha.config.groupEntities ?? [])).first { $0.id == id }
    }

    private func pickApps(for gid: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Kies de apps voor deze groep"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for u in panel.urls { prefs.add(u.standardizedFileURL.path, to: gid) }
        }
    }

    private func haPicker(for gid: UUID) -> some View {
        let words = groupHAFilter.lowercased().split(separator: " ").map(String.init)
        let matches: [HAEntity] = words.isEmpty ? [] : Array(ha.available.filter { e in
            let hay = (e.id + " " + e.name).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Zoek entiteit, bijv. woonkamer", text: $groupHAFilter)
                    .textFieldStyle(.roundedBorder)
                Button { ha.fetchEntities() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Entiteiten opnieuw ophalen")
            }
            if ha.available.isEmpty {
                Text(ha.tokenSaved ? "Nog geen entiteiten. Klik op vernieuwen."
                                   : "Sla eerst een token op onder Koppelingen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if words.isEmpty {
                Text("Typ om te zoeken in \(ha.available.count) entiteiten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if matches.isEmpty {
                Text("Geen resultaten.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(matches) { e in
                Button {
                    ha.addGroupEntity(e)
                    prefs.add("ha:\(e.id)", to: gid)
                    haPickerGroup = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: HAIcon.symbol(for: e.domain)).frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(e.name)
                            Text(e.id).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            if ha.available.isEmpty && ha.tokenSaved && ha.config.enabled { ha.fetchEntities() }
        }
    }

    private func memberName(_ path: String) -> String {
        if path.hasPrefix("ha:") { return haEntity(for: path)?.name ?? String(path.dropFirst(3)) }
        return FileManager.default.displayName(atPath: path)
    }

    private func memberIcon(_ path: String) -> NSImage {
        if path.hasPrefix("ha:") {
            let e = haEntity(for: path)
            return HAIcon.make(domain: e?.domain ?? "switch", on: false, symbol: e?.symbol, color: e?.color)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    // MARK: Tab: Tegels

    private func sideThemePicker(_ title: String, _ selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Zelfde als hoofd-dock").tag(UUID?.none)
            ForEach(store.themes) { th in
                Text(th.name).tag(UUID?.some(th.id))
            }
        }
    }

    @ViewBuilder
    private var tilesTab: some View {
        Section {
            Toggle("Tegels naast de dock tonen", isOn: $tileStore.enabled)
            sideThemePicker("Opmaak links", $tileStore.leftTheme)
            sideThemePicker("Opmaak rechts", $tileStore.rightTheme)
            Menu("Nieuwe tegel") {
                Button("3D-print voortgang (Home Assistant)") { tileStore.add(.printer) }
                Button("VPN-status") { tileStore.add(.vpn) }
                Button("Claude-verbruik (lokale logs)") { tileStore.add(.claude) }
                Button("Processor") { tileStore.add(.cpu) }
                Button("Accu") { tileStore.add(.battery) }
                Divider()
                Button("Klok") { tileStore.add(.clock) }
                Button("Weer") { tileStore.add(.weather) }
                Divider()
                Button("Knop: map openen") { tileStore.add(.folder) }
                Button("Knop: server verbinden") { tileStore.add(.server) }
                Divider()
                Button("Eigen shell-commando") { tileStore.add(.command) }
                Button("URL met JSON") { tileStore.add(.url) }
            }
            note("Een kant verschijnt zodra er een tegel op staat. Met 'Tegen de schermrand' staat een tegel links of rechts op het scherm, los van de dock. Tegels zijn zo groot als je dock-iconen. Bij 'Bij klikken' kun je van elke tegel een knop maken.")
        } header: {
            sectionHeader("Tweede dock", "rectangle.split.3x1")
        }

        ForEach($tileStore.tiles) { $t in
            Section {
                TextField("Titel", text: $t.title)
                Picker("Kant", selection: $t.side) {
                    Text("Links").tag(TileSide.left)
                    Text("Rechts").tag(TileSide.right)
                }
                .pickerStyle(.segmented)
                Toggle("Tegen de schermrand, los van de dock", isOn: $t.edge)
                Picker("Bron", selection: $t.kind) {
                    ForEach(TileKind.allCases) { Text($0.label).tag($0) }
                }
                tileSourceFields($t)
                if t.kind.choosesDisplay {
                    Picker("Weergave", selection: $t.display) {
                        Text("Waarde").tag(TileDisplay.value)
                        Text("Ring").tag(TileDisplay.ring)
                        Text("Status").tag(TileDisplay.status)
                    }
                    .pickerStyle(.segmented)
                }
                if t.kind != .clock {
                    HStack {
                        TextField("Symbool: SF Symbol of mdi:naam", text: $t.symbol)
                            .textFieldStyle(.roundedBorder)
                        TileGlyph(name: t.symbol, size: 18, color: .primary)
                            .frame(width: 26, height: 26)
                        Button("Zoek…") { iconPickerID = t.id }
                            .popover(isPresented: Binding(
                                get: { iconPickerID == t.id },
                                set: { on in if !on, iconPickerID == t.id { iconPickerID = nil } }
                            ), arrowEdge: .bottom) {
                                IconPickerView(current: t.symbol) { name in
                                    $t.wrappedValue.symbol = name
                                    iconPickerID = nil
                                }
                            }
                    }
                }
                if t.kind.hasNumericValue {
                    TextField("Eenheid, bijv. %", text: $t.unit)
                }
                if t.display == .ring && t.kind.hasNumericValue {
                    slider("Ring leeg bij", $t.lo, -100...1000)
                    slider("Ring vol bij", $t.hi, 0...1000)
                }
                if t.kind.hasInterval {
                    Stepper(value: $t.interval, in: 5...3600, step: t.kind == .weather ? 60 : 5) {
                        Text("Verversen elke \(Int(t.interval)) s")
                    }
                }
                Picker("Bij klikken", selection: $t.action) {
                    ForEach(TileAction.allCases) { Text($0.label).tag($0) }
                }
                if t.action != .none {
                    HStack {
                        TextField(t.action.placeholder, text: $t.actionTarget)
                            .textFieldStyle(.roundedBorder)
                        if t.action == .folder {
                            Button("Kies…") { pickTileFolder($t) }
                        }
                    }
                    if t.action == .ha {
                        note("Scènes, scripts en knoppen worden uitgevoerd, schakelaars en lampen gaan aan of uit.")
                    }
                }
                Toggle("Eigen kleur", isOn: Binding(
                    get: { t.color != nil },
                    set: { on in $t.wrappedValue.color = on ? RGBA(0.35, 0.8, 1.0) : nil }
                ))
                if t.color != nil {
                    ColorPicker("Kleur", selection: Binding(
                        get: { t.color?.color ?? .blue },
                        set: { $t.wrappedValue.color = RGBA(color: $0) }
                    ), supportsOpacity: false)
                }
                HStack {
                    Button { tileStore.move(t.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    Button { tileStore.move(t.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    Spacer()
                    Button("Verwijder tegel", role: .destructive) {
                        tileStore.tiles.removeAll { $0.id == t.id }
                    }
                }
            } header: {
                sectionHeader(t.title, "square.grid.2x2")
            }
        }
    }

    @ViewBuilder
    private func tileSourceFields(_ t: Binding<TileConfig>) -> some View {
        switch t.wrappedValue.kind {
        case .ha:
            HStack {
                TextField("Entiteit, bijv. sensor.printer_voortgang", text: t.entity)
                    .textFieldStyle(.roundedBorder)
                Button("Zoek…") {
                    tileFilter = ""
                    tilePickerID = t.wrappedValue.id
                }
                .popover(isPresented: Binding(
                    get: { tilePickerID == t.wrappedValue.id },
                    set: { on in if !on, tilePickerID == t.wrappedValue.id { tilePickerID = nil } }
                ), arrowEdge: .bottom) {
                    tileEntityPicker(t)
                }
            }
            note("De waarde van de entiteit wordt elke paar seconden opgehaald. Getallen krijgen een eenheid en een ring, andere waarden (aan/uit, thuis/weg) worden vertaald.")
        case .shell:
            TextField("Commando", text: t.command)
                .textFieldStyle(.roundedBorder)
            note("De eerste regel van de uitvoer wordt getoond. Met 'tekst|42' vult de ring zich tot 42%. Het commando draait in zsh en mag maximaal 15 seconden duren.")
        case .http:
            TextField("URL, bijv. http://printer.local/printer/objects/query?display_status", text: t.url)
                .textFieldStyle(.roundedBorder)
            TextField("Pad in de JSON, bijv. result.status.display_status.progress", text: t.jsonPath)
                .textFieldStyle(.roundedBorder)
            SecureField("Bearer-token (optioneel)", text: $tileToken)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Bewaar token") {
                    tileStore.setToken(tileToken, for: t.wrappedValue.id)
                    tileToken = ""
                }
                .disabled(tileToken.isEmpty)
                if tileStore.token(for: t.wrappedValue.id) != nil {
                    Button("Verwijder token") { tileStore.setToken("", for: t.wrappedValue.id) }
                }
            }
            note("Een getal van 0 tot 1, zoals de voortgang van Moonraker, vul je met 'Ring vol bij' = 1.")
        case .vpn:
            note("Toont 'Aan' zodra een VPN-verbinding actief is, ook bij apps als WireGuard of Tailscale.")
        case .system:
            Picker("Meting", selection: t.metric) {
                ForEach(SystemMetric.allCases) { Text($0.label).tag($0) }
            }
        case .clock:
            Picker("Tijdzone", selection: t.timezone) {
                Text("Lokale tijd").tag("")
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }
            note("Bij een andere tijdzone toont de tegel de titel (bijvoorbeeld de plaatsnaam) in plaats van de datum.")
        case .weather:
            TextField("Plaats, bijv. Utrecht", text: t.place)
                .textFieldStyle(.roundedBorder)
            note("Temperatuur en weertype via Open-Meteo. Er is geen account of sleutel nodig.")
        case .button:
            note("Deze tegel toont alleen een symbool en een titel. Kies hieronder wat een klik doet.")
        case .claude:
            Picker("Periode", selection: t.period) {
                Text("Vandaag").tag(ClaudePeriod.day)
                Text("Laatste 7 dagen").tag(ClaudePeriod.week)
            }
            .pickerStyle(.segmented)
            slider("Budget voor ring (tokens, 0 = geen)", t.hi, 0...50_000_000)
            note("Telt invoer, uitvoer en cache-aanmaak uit de lokale Claude Code-logs in ~/.claude. Dit is alleen verbruik van Claude Code op deze Mac.")
        }
    }

    private func pickTileFolder(_ t: Binding<TileConfig>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            t.wrappedValue.actionTarget = url.path
        }
    }

    private func tileEntityPicker(_ t: Binding<TileConfig>) -> some View {
        let words = tileFilter.lowercased().split(separator: " ").map(String.init)
        let matches: [HAEntity] = words.isEmpty ? [] : Array(ha.available.filter { e in
            let hay = (e.id + " " + e.name).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Zoek entiteit, bijv. printer", text: $tileFilter)
                    .textFieldStyle(.roundedBorder)
                Button { ha.fetchEntities() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            if ha.available.isEmpty {
                Text(ha.tokenSaved ? "Nog geen entiteiten. Klik op vernieuwen."
                                   : "Sla eerst een token op onder Koppelingen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if words.isEmpty {
                Text("Typ om te zoeken in \(ha.available.count) entiteiten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if matches.isEmpty {
                Text("Geen resultaten.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(matches) { e in
                Button {
                    t.wrappedValue.entity = e.id
                    if t.wrappedValue.title == "Tegel" || t.wrappedValue.title == "Print" {
                        t.wrappedValue.title = e.name
                    }
                    tilePickerID = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: HAIcon.symbol(for: e.domain)).frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(e.name)
                            Text(e.id).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            if ha.available.isEmpty && ha.tokenSaved && ha.config.enabled { ha.fetchEntities() }
        }
    }

    // MARK: Tab: Koppelingen

    @ViewBuilder
    private var connectionsTab: some View {
        Section {
            Toggle("Scripts uitvoeren bij een themawissel", isOn: $store.hooksEnabled)
            note("Scripts in ~/.config/dockstudio/hooks krijgen de kleuren als variabelen (DOCKSTUDIO_BG, _FG, _ACCENT, …). Alleen uitvoerbare bestanden (chmod +x) draaien.")
            HStack {
                Button("Open hooks-map") {
                    HookRunner.ensureFolder()
                    NSWorkspace.shared.open(HookRunner.folder)
                }
                Button("Voer hooks nu uit") {
                    HookRunner.run(theme: store.theme, force: true)
                }
            }
        } header: {
            sectionHeader("Hooks bij themawissel", "terminal")
        }

        Section {
            Toggle("Home Assistant gebruiken", isOn: $ha.config.enabled)
            TextField("URL", text: $ha.config.baseURL)
            SecureField("Long-lived access token", text: $tokenInput)
            HStack {
                Button("Bewaar token") {
                    ha.saveToken(tokenInput)
                    tokenInput = ""
                }
                .disabled(tokenInput.isEmpty)
                Button("Test verbinding") { ha.testConnection() }
            }
            note(ha.tokenSaved
                 ? "Het token staat in de Sleutelhanger."
                 : "Nog geen token. Maak er een in Home Assistant: profiel > Beveiliging > Langdurige toegangstokens.")
            if !ha.status.isEmpty { note(ha.status) }
        } header: {
            sectionHeader("Home Assistant", "house")
        }

        Section {
            haStyleSection
        } header: {
            sectionHeader("Uiterlijk van HA-iconen", "paintbrush")
        }

        Section {
            if ha.config.dockEntities.isEmpty && ha.config.themeLights.isEmpty && ha.config.themeScene.isEmpty {
                note("Nog niets gekozen. Zoek hieronder een lamp, schakelaar of scène.")
            }
            ForEach(ha.config.dockEntities) { e in
                HStack {
                    selectedRow(symbol: e.symbol ?? HAIcon.symbol(for: e.domain), title: e.name, subtitle: e.id, badge: "Dock") {
                        ha.config.dockEntities.removeAll { $0.id == e.id }
                    }
                    styleButton(e.id)
                }
            }
            ForEach(ha.config.groupEntities ?? []) { e in
                HStack {
                    selectedRow(symbol: e.symbol ?? HAIcon.symbol(for: e.domain), title: e.name, subtitle: e.id, badge: "Groep") {
                        ha.config.groupEntities?.removeAll { $0.id == e.id }
                        for g in prefs.groups { prefs.remove("ha:\(e.id)", from: g.id) }
                    }
                    styleButton(e.id)
                }
            }
            ForEach(ha.config.themeLights, id: \.self) { id in
                selectedRow(symbol: "lightbulb", title: ha.available.first { $0.id == id }?.name ?? id,
                            subtitle: id, badge: "Thema") {
                    ha.config.themeLights.removeAll { $0 == id }
                }
            }
            if !ha.config.themeScene.isEmpty {
                selectedRow(symbol: "sparkles",
                            title: ha.available.first { $0.id == ha.config.themeScene }?.name ?? ha.config.themeScene,
                            subtitle: ha.config.themeScene, badge: "Thema-scène") {
                    ha.config.themeScene = ""
                }
            }
        } header: {
            sectionHeader("Gekozen entiteiten", "checklist")
        }

        Section {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Zoek entiteit, bijv. woonkamer of light.", text: $entityFilter)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onAppear {
                        if ha.available.isEmpty && ha.tokenSaved && ha.config.enabled { ha.fetchEntities() }
                    }
                if !entityFilter.isEmpty {
                    Button { entityFilter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Button { ha.fetchEntities() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Entiteiten opnieuw ophalen")
            }

            if ha.available.isEmpty {
                note(ha.tokenSaved
                     ? "Nog geen entiteiten geladen. Controleer de verbinding hierboven en klik op vernieuwen."
                     : "Sla eerst een token op om te kunnen zoeken.")
            } else if entityFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                note("Typ om te zoeken in \(ha.available.count) entiteiten.")
            } else {
                let found = searchResults
                if found.items.isEmpty {
                    note("Geen resultaten.")
                }
                ForEach(found.items) { e in
                    HStack(spacing: 8) {
                        Image(systemName: HAIcon.symbol(for: e.domain))
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(e.name)
                            Text(e.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(isOn: ha.dockBinding(e)) { Text("Dock") }
                            .toggleStyle(.button)
                        if e.domain == "light" {
                            Toggle(isOn: ha.lightBinding(e.id)) { Text("Thema") }
                                .toggleStyle(.button)
                        }
                        if e.domain == "scene" {
                            Toggle(isOn: ha.sceneBinding(e.id)) { Text("Thema-scène") }
                                .toggleStyle(.button)
                        }
                    }
                    .controlSize(.small)
                }
                if found.more > 0 {
                    note("Nog \(found.more) resultaten. Maak je zoekopdracht specifieker.")
                }
            }
        } header: {
            sectionHeader("Zoek entiteiten", "magnifyingglass")
        }

        Section {
            Toggle("Lampen en scène aanpassen bij een themawissel", isOn: $ha.config.syncTheme)
            Picker("Kleur voor de lampen", selection: $ha.config.themeColor) {
                ForEach(HAThemeColor.allCases) { Text($0.label).tag($0) }
            }
            slider("Helderheid (%)", $ha.config.themeBrightness, 5...100)
            note("Gekozen lampen: \(ha.config.themeLights.count)"
                 + (ha.config.themeScene.isEmpty ? "" : ", scène: \(ha.config.themeScene)"))
            Button("Test: stuur dit thema naar de lampen") {
                ha.applyTheme(store.theme, force: true)
            }
        } header: {
            sectionHeader("Lampen volgen het thema", "lightbulb")
        }
    }

    // MARK: Hulpjes

    /// Alle woorden uit de zoekopdracht moeten in de naam of het id voorkomen.
    private var searchResults: (items: [HAEntity], more: Int) {
        let words = entityFilter.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ([], 0) }
        let matches = ha.available.filter { e in
            let hay = (e.id + " " + e.name).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
        return (Array(matches.prefix(8)), max(matches.count - 8, 0))
    }

    private func selectedRow(symbol: String, title: String, subtitle: String, badge: String,
                             remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(badge)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            Button(action: remove) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Verwijderen")
        }
    }

    private func sectionHeader(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func swatches(_ p: Palette) -> some View {
        let hexes = [p.background, p.surface, p.foreground, p.accent, p.secondary]
        return HStack(spacing: 6) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 5)
                    .fill(RGBA(hex: h).color)
                    .frame(width: 34, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2)))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// Schuif met een invulveld: de waarde mag ook buiten het bereik van de schuif getypt worden.
    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        decimals: Int = 0) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            TextField("", value: value,
                      format: .number.precision(.fractionLength(0...decimals)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 64)
        }
    }
}

/// Rij in de themalijst: klein voorbeeld van het thema met naam en stijl.
struct ThemeRow: View {
    let theme: DockTheme

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 46, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name).lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if !theme.showBackground { return "Alleen iconen" }
        let fill = theme.useBlur ? "glas" : (theme.useGradient ? "verloop" : "solide")
        return "\(theme.shape.label.lowercased()) · \(fill)"
    }

    private var preview: some View {
        let shape = theme.makeShape()
        return ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.28))
            if theme.showBackground {
                shape
                    .fill(LinearGradient(
                        colors: [theme.colorA.color, (theme.useGradient ? theme.colorB : theme.colorA).color],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(shape.stroke(theme.borderColor.color, lineWidth: 1))
                    .padding(2)
            }
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == 1 && theme.glowEnabled ? theme.glowColor.color : theme.indicatorColor.color)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}
