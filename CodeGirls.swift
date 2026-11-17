import SwiftUI
import Foundation
import PhotosUI
import ImageIO
import UIKit

// MARK: - Modelos
// Os modelos descrevem o domínio sem depender das telas, da API ou do armazenamento.

struct User: Identifiable, Codable {
    let id: Int
    let name: String
    let role: String
    let area: String
    let skills: [String]
    let location: String
}

enum ForumCategory: String, CaseIterable, Identifiable, Codable {
    case frontend = "Front-end"
    case backend = "Back-end"

    var id: Self { self }
}

struct ForumTopic: Identifiable, Codable {
    let id: Int
    let title: String
    let body: String
    let category: ForumCategory
}

struct Mentorship: Identifiable, Codable {
    let id: Int
    let mentor: User
    let specialties: [String]
    let date: Date
}

struct StudyGroup: Identifiable, Codable {
    let id: Int
    let name: String
    let description: String
    let date: Date
    let participants: Int
}

enum JobLevel: String, CaseIterable, Identifiable, Codable {
    case junior = "Júnior"
    case mid = "Pleno"
    case senior = "Sênior"

    var id: Self { self }
}

enum WorkMode: String, CaseIterable, Identifiable, Codable {
    case remote = "Remoto"
    case hybrid = "Híbrido"
    case onSite = "Presencial"

    var id: Self { self }
}

struct JobOpening: Identifiable, Codable {
    let id: Int
    let title: String
    let company: String
    let level: JobLevel
    let mode: WorkMode

    var shareText: String {
        "\(title) · \(company)\n\(level.rawValue) · \(mode.rawValue)\nVaga demonstrativa do CodeGirls"
    }
}

private struct PlaceholderPost: Decodable {
    let id: Int
}

private enum ForumState {
    case idle
    case loading
    case success([ForumTopic])
    case failure(String)
}

private struct NetworkFilters: Equatable {
    var area = ""
    var skills = ""
    var location = ""

    func includes(_ user: User) -> Bool {
        let terms = skills.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return containsTerm(area, in: user.area)
            && containsTerm(location, in: user.location)
            && terms.allSatisfy { term in
                user.skills.contains { containsTerm(term, in: $0) }
            }
    }
}

private func containsTerm(_ query: String, in text: String) -> Bool {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return term.isEmpty || text.range(
        of: term, options: [.caseInsensitive, .diacriticInsensitive]
    ) != nil
}

// MARK: - ViewModel
// A ViewModel concentra regras de negócio, filtros, rede e persistência.
// O MainActor mantém as mutações observadas pelo SwiftUI no ator principal.

@MainActor
private final class CodeGirlsViewModel: ObservableObject {
    @Published private(set) var forumState: ForumState = .idle
    @Published var forumSearch = ""
    @Published var forumCategory: ForumCategory?
    @Published var networkDraft = NetworkFilters()
    @Published private var networkFilters = NetworkFilters()
    @Published var selectedLevels: Set<JobLevel> = []
    @Published var selectedModes: Set<WorkMode> = []

    @AppStorage("codegirls.connectionCount") private var storedConnectionCount = 1
    @AppStorage("codegirls.connectedIDs") private var storedConnectedIDs = "1"
    @AppStorage("codegirls.savedJobIDs") private var storedJobIDs = "1"
    @AppStorage("codegirls.joinedGroupIDs") private var storedGroupIDs = ""
    @AppStorage("codegirls.mentorshipDates") private var storedMentorshipDates = Data()

    @Published private(set) var connectedIDs: Set<Int> = []
    @Published private var savedJobIDs: Set<Int> = []
    @Published private var joinedGroupIDs: Set<Int> = []
    @Published private var sessions: [Int: Date] = [:]

    private let people = [
        User(id: 1, name: "Marina Costa", role: "Engenheira iOS", area: "Mobile",
             skills: ["Swift", "SwiftUI"], location: "Fortaleza, CE"),
        User(id: 2, name: "Camila Lima", role: "Dev Back-end", area: "Back-end",
             skills: ["Python", "APIs REST"], location: "Recife, PE"),
        User(id: 3, name: "Luana Alves", role: "Dev Front-end", area: "Front-end",
             skills: ["React", "Acessibilidade"], location: "São Paulo, SP")
    ]

    let groups = [
        StudyGroup(id: 1, name: "Swift em prática",
                   description: "Construa uma tela com SwiftUI em conjunto.",
                   date: .now.addingTimeInterval(86_400 * 3), participants: 12),
        StudyGroup(id: 2, name: "APIs sem mistério",
                   description: "Pratique requisições, decodificação e estados de erro.",
                   date: .now.addingTimeInterval(86_400 * 5), participants: 8)
    ]

    private let jobs = [
        JobOpening(id: 1, title: "Dev iOS", company: "Estúdio Aurora", level: .junior, mode: .remote),
        JobOpening(id: 2, title: "Dev Back-end", company: "Nuvem Labs", level: .mid, mode: .hybrid),
        JobOpening(id: 3, title: "Dev Front-end", company: "Órbita Digital", level: .senior, mode: .onSite)
    ]

    private(set) var mentors: [Mentorship] = []

    init() {
        let firstDate = Date.now.addingTimeInterval(86_400 * 7)
        mentors = people.enumerated().map { index, person in
            Mentorship(id: person.id, mentor: person, specialties: person.skills,
                       date: firstDate.addingTimeInterval(Double(index) * 86_400))
        }
        connectedIDs = decodeIDs(storedConnectedIDs).intersection(people.map(\.id))
        storedConnectionCount = connectedIDs.count
        savedJobIDs = decodeIDs(storedJobIDs)
        joinedGroupIDs = decodeIDs(storedGroupIDs).intersection(groups.map(\.id))
        if let saved = try? JSONDecoder().decode([Int: Date].self, from: storedMentorshipDates) {
            sessions = saved
        } else if let first = mentors.first {
            sessions[first.id] = first.date
            saveMentorshipDates()
        }
    }

    var forumCount: Int? {
        if case let .success(topics) = forumState { return topics.count }
        return nil
    }

    var connectionCount: Int { storedConnectionCount }

    var filteredTopics: [ForumTopic] {
        guard case let .success(topics) = forumState else { return [] }

        return topics.filter { topic in
            (forumCategory == nil || topic.category == forumCategory)
                && containsTerm(forumSearch, in: topic.title + " " + topic.body)
        }
    }

    var connections: [User] { people.filter { connectedIDs.contains($0.id) } }

    var suggestions: [User] {
        people.filter { !connectedIDs.contains($0.id) && networkFilters.includes($0) }
    }

    var filteredJobs: [JobOpening] {
        jobs.filter { job in
            (selectedLevels.isEmpty || selectedLevels.contains(job.level))
                && (selectedModes.isEmpty || selectedModes.contains(job.mode))
        }
    }

    var savedJobs: [JobOpening] { jobs.filter { savedJobIDs.contains($0.id) } }

    var hasJobFilters: Bool { !selectedLevels.isEmpty || !selectedModes.isEmpty }

    func clearJobFilters() {
        selectedLevels.removeAll()
        selectedModes.removeAll()
    }

    var scheduledMentorships: [Mentorship] {
        mentors.compactMap { item -> Mentorship? in
            guard let date = sessions[item.id] else { return nil }
            return Mentorship(id: item.id, mentor: item.mentor,
                              specialties: item.specialties, date: date)
        }.sorted { $0.date < $1.date }
    }

    // Os IDs retornados pela API selecionam tópicos demonstrativos em português.
    func loadForums(force: Bool = false) async {
        if case .loading = forumState { return }
        if case .success = forumState, !force { return }

        let previousState = forumState
        forumState = .loading
        do {
            let endpoint = URL(string: "https://jsonplaceholder.typicode.com/posts")!
            let request = URLRequest(url: endpoint, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let posts = try JSONDecoder().decode([PlaceholderPost].self, from: data)
            try Task.checkCancellation()
            let postIDs = Set(posts.map(\.id))
            forumState = .success(Self.demoTopics.filter { postIDs.contains($0.id) })
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                forumState = previousState
            } else if error is DecodingError {
                forumState = .failure("O serviço retornou um formato inesperado.")
            } else {
                forumState = .failure("Não foi possível carregar os tópicos. Verifique a conexão e tente novamente.")
            }
        }
    }

    var canClearNetworkFilters: Bool {
        networkDraft != NetworkFilters() || networkFilters != NetworkFilters()
    }

    func applyNetworkFilters() {
        networkFilters = networkDraft
    }

    func clearNetworkFilters() {
        networkDraft = NetworkFilters()
        networkFilters = NetworkFilters()
    }

    func connect(to user: User) {
        guard !connectedIDs.contains(user.id) else { return }
        var updated = connectedIDs
        updated.insert(user.id)
        storedConnectedIDs = encodeIDs(updated)
        storedConnectionCount = updated.count
        connectedIDs = updated
    }

    func hasJoined(_ group: StudyGroup) -> Bool { joinedGroupIDs.contains(group.id) }

    func participantCount(for group: StudyGroup) -> Int {
        group.participants + (hasJoined(group) ? 1 : 0)
    }

    func toggleGroup(_ group: StudyGroup) {
        if hasJoined(group) {
            joinedGroupIDs.remove(group.id)
        } else {
            joinedGroupIDs.insert(group.id)
        }
        storedGroupIDs = encodeIDs(joinedGroupIDs)
    }

    func isSaved(_ job: JobOpening) -> Bool { savedJobIDs.contains(job.id) }

    func toggleSaved(_ job: JobOpening) {
        if isSaved(job) {
            savedJobIDs.remove(job.id)
        } else {
            savedJobIDs.insert(job.id)
        }
        storedJobIDs = encodeIDs(savedJobIDs)
    }

    func hasSession(_ mentorship: Mentorship) -> Bool { sessions[mentorship.id] != nil }

    func request(_ mentorship: Mentorship) {
        guard !hasSession(mentorship) else { return }
        sessions[mentorship.id] = max(mentorship.date, .now.addingTimeInterval(86_400))
        saveMentorshipDates()
    }

    func reschedule(_ mentorship: Mentorship, to date: Date) -> Bool {
        guard hasSession(mentorship), date > .now else { return false }
        sessions[mentorship.id] = date
        saveMentorshipDates()
        return true
    }

    private func saveMentorshipDates() {
        if let data = try? JSONEncoder().encode(sessions) {
            storedMentorshipDates = data
        }
    }

    private func decodeIDs(_ value: String) -> Set<Int> {
        Set(value.split(separator: ",").compactMap { Int($0) })
    }

    private func encodeIDs(_ ids: Set<Int>) -> String {
        ids.sorted().map { String($0) }.joined(separator: ",")
    }

    private static let demoTopics = [
        ForumTopic(id: 1, title: "Primeira tela com SwiftUI",
                   body: "Como vocês organizam as primeiras telas para que o projeto continue fácil de manter?",
                   category: .frontend),
        ForumTopic(id: 2, title: "Tratamento de erros em APIs",
                   body: "Quais estratégias vocês usam para transformar falhas de rede em mensagens que ajudam quem usa o app?",
                   category: .backend),
        ForumTopic(id: 3, title: "Testando acessibilidade",
                   body: "Que experiências vocês tiveram ao testar Dynamic Type e VoiceOver em projetos de interface?",
                   category: .frontend),
        ForumTopic(id: 4, title: "Montando uma API para o portfólio",
                   body: "Que recursos vocês escolheriam para praticar autenticação e paginação?",
                   category: .backend)
    ]
}

// MARK: - Componentes SwiftUI
// As Views observam o estado, apresentam os dados e encaminham as ações.
// Estados de apresentação, como a abertura de uma folha, ficam na própria View.

private let violet = Color(red: 0.33, green: 0.17, blue: 0.66)
private let lavender = Color(red: 0.96, green: 0.94, blue: 1)
private let ink = Color(red: 0.10, green: 0.08, blue: 0.13)

@MainActor
private struct Page<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, content: content)
                .frame(maxWidth: 700)
                .padding(20)
                .frame(maxWidth: .infinity)
        }
        .background(.white)
        .foregroundStyle(ink)
        .navigationTitle(title)
    }
}

@MainActor
private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(lavender, in: RoundedRectangle(cornerRadius: 18))
    }
}

@MainActor
private struct PrimaryAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(violet)
    }
}

@MainActor
private struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private struct Tag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(violet)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(violet.opacity(0.09), in: Capsule())
    }
}

@MainActor
private struct SkillTags: View {
    let skills: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { tags }
            VStack(alignment: .leading, spacing: 6) { tags }
        }
    }

    private var tags: some View {
        ForEach(skills, id: \.self) { Tag(title: $0) }
    }
}

@MainActor
private struct PersonRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(violet)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name).font(.headline)
                Text(user.role).font(.subheadline)
                Text(user.location).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Início

@MainActor
private struct HomeView: View {
    @ObservedObject var model: CodeGirlsViewModel
    @AppStorage("codegirls.profileName") private var name = "Raissa"
    @AppStorage("codegirls.profilePhoto") private var photoData = Data()
    @State private var editing = false

    var body: some View {
        Page(title: "CodeGirls") {
            HStack(spacing: 14) {
                avatar
                Text("Bem-vinda, \(name)")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { statistics }
                VStack(spacing: 10) { statistics }
            }

            SectionTitle(title: "Notificações")
            Card {
                if let next = model.scheduledMentorships.first {
                    Label("Mentoria com \(next.mentor.name)", systemImage: "calendar")
                    Text(next.date, format: .dateTime.day().month(.wide).hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Label("Explore novos grupos de estudo", systemImage: "person.3")
            }

            Card {
                Label("Seu perfil: Dev Full Stack", systemImage: "person.text.rectangle")
                    .font(.headline)
                Button("Editar perfil") { editing = true }
                    .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $editing) {
            ProfileEditor(name: $name, photoData: $photoData)
        }
    }

    private var avatar: some View {
        Group {
            if let photo = UIImage(data: photoData) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(violet)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statistics: some View {
        statistic("Fóruns", model.forumCount.map { String($0) } ?? "—", icon: "bubble.left.and.bubble.right")
        statistic("Conexões", String(model.connectionCount), icon: "person.2")
        statistic("Mentorias", String(model.scheduledMentorships.count), icon: "sparkles")
    }

    private func statistic(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(value).font(.title2.bold())
            Text(title).font(.footnote.weight(.semibold))
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .foregroundStyle(violet)
        .background(lavender, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    @Binding var photoData: Data
    @State private var draft = ""
    @State private var draftPhoto = Data()
    @State private var selection: PhotosPickerItem?
    @State private var importing = false
    @State private var photoError = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $draft)
                    .textContentType(.givenName)
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("Escolher foto de perfil", systemImage: "photo")
                }
                if importing { ProgressView("Carregando foto…") }
                if !draftPhoto.isEmpty {
                    Button("Remover foto", role: .destructive) {
                        selection = nil
                        draftPhoto = Data()
                        photoError = false
                        importing = false
                    }
                }
                if photoError {
                    Text("Não foi possível abrir a foto. Tente escolher outra imagem.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Editar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        photoData = draftPhoto
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importing)
                }
            }
            .onAppear {
                draft = name
                draftPhoto = photoData
            }
            .task(id: selection) {
                guard let item = selection else { return }
                importing = true
                photoError = false
                defer {
                    if !Task.isCancelled { importing = false }
                }

                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let jpeg = thumbnailData(from: data) else {
                        if !Task.isCancelled { photoError = true }
                        return
                    }
                    try Task.checkCancellation()
                    draftPhoto = jpeg
                } catch {
                    if !Task.isCancelled { photoError = true }
                }
            }
        }
    }

    // ImageIO reduz o tamanho antes de gravar. A interface usa apenas Views SwiftUI.
    private func thumbnailData(from data: Data) -> Data? {
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: 256
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Fóruns

@MainActor
private struct ForumsView: View {
    @ObservedObject var model: CodeGirlsViewModel

    var body: some View {
        Page(title: "Fóruns") {
            Picker("Categoria", selection: $model.forumCategory) {
                Text("Todos").tag(nil as ForumCategory?)
                ForEach(ForumCategory.allCases) { category in
                    Text(category.rawValue).tag(Optional(category))
                }
            }
            .pickerStyle(.menu)

            switch model.forumState {
            case .idle, .loading:
                ProgressView("Carregando tópicos…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            case let .failure(message):
                Card {
                    Label(message, systemImage: "exclamationmark.circle")
                    PrimaryAction(title: "Tentar novamente") {
                        Task { await model.loadForums(force: true) }
                    }
                }
            case .success:
                if model.filteredTopics.isEmpty {
                    Text("Nenhum tópico encontrado.")
                        .foregroundStyle(.secondary)
                }

                ForEach(model.filteredTopics) { topic in
                    Card {
                        Tag(title: topic.category.rawValue)
                        SectionTitle(title: topic.title)
                        Text(topic.body).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $model.forumSearch, prompt: "Buscar tópicos")
        .refreshable { await model.loadForums(force: true) }
    }
}

// MARK: - Network

@MainActor
private struct NetworkView: View {
    @ObservedObject var model: CodeGirlsViewModel

    var body: some View {
        Page(title: "Network") {
            SectionTitle(title: "Conexões")
            if model.connections.isEmpty {
                Text("Suas conexões aparecerão aqui.").foregroundStyle(.secondary)
            }
            ForEach(model.connections) { person in
                Card { PersonRow(user: person) }
            }

            Card {
                SectionTitle(title: "Filtrar perfis")
                TextField("Área", text: $model.networkDraft.area)
                    .textFieldStyle(.roundedBorder)
                TextField("Habilidades, separadas por vírgula", text: $model.networkDraft.skills)
                    .textFieldStyle(.roundedBorder)
                TextField("Localização", text: $model.networkDraft.location)
                    .textFieldStyle(.roundedBorder)
                PrimaryAction(title: "Aplicar Filtros") { model.applyNetworkFilters() }
                if model.canClearNetworkFilters {
                    Button("Limpar filtros") { model.clearNetworkFilters() }
                }
            }

            SectionTitle(title: "Conheça outras profissionais")
            if model.suggestions.isEmpty {
                Text("Nenhuma sugestão com esses filtros.").foregroundStyle(.secondary)
            }
            ForEach(model.suggestions) { person in
                Card {
                    PersonRow(user: person)
                    SkillTags(skills: person.skills)
                    Button("Conectar") { model.connect(to: person) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - Grupos

@MainActor
private struct GroupsView: View {
    @ObservedObject var model: CodeGirlsViewModel

    var body: some View {
        Page(title: "Grupos") {
            SectionTitle(title: "Próximos encontros")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(model.groups) { group in
                        groupCard(group)
                            .frame(width: 250)
                    }
                }
            }
        }
    }

    private func groupCard(_ group: StudyGroup) -> some View {
        let joined = model.hasJoined(group)
        let participantCount = model.participantCount(for: group)

        return Card {
            SectionTitle(title: group.name)
            Text(group.description)
                .foregroundStyle(.secondary)
            Label {
                Text(group.date, format: .dateTime.day().month(.abbreviated).hour().minute())
            } icon: {
                Image(systemName: "calendar")
            }
            Label("\(participantCount) participantes", systemImage: "person.2")
            if joined {
                Button("Sair do grupo") { model.toggleGroup(group) }
                    .buttonStyle(.bordered)
            } else {
                PrimaryAction(title: "Participar") { model.toggleGroup(group) }
            }
        }
    }
}

// MARK: - Vagas

@MainActor
private struct JobsView: View {
    @ObservedObject var model: CodeGirlsViewModel

    var body: some View {
        Page(title: "Vagas") {
            Card {
                SectionTitle(title: "Nível")
                ForEach(JobLevel.allCases) { level in
                    Toggle(level.rawValue, isOn: membership(level, in: $model.selectedLevels))
                }

                Divider()
                SectionTitle(title: "Modalidade")
                ForEach(WorkMode.allCases) { mode in
                    Toggle(mode.rawValue, isOn: membership(mode, in: $model.selectedModes))
                }
                if model.hasJobFilters {
                    Button("Limpar filtros") { model.clearJobFilters() }
                }
            }
            .tint(violet)

            SectionTitle(title: "Vagas disponíveis")
            if model.filteredJobs.isEmpty {
                Text("Nenhuma vaga com esses filtros.").foregroundStyle(.secondary)
            }
            ForEach(model.filteredJobs) { job in
                jobCard(job)
            }

            SectionTitle(title: "Vagas salvas")
            if model.savedJobs.isEmpty {
                Text("Salve uma vaga para encontrá-la aqui.").foregroundStyle(.secondary)
            }
            ForEach(model.savedJobs) { job in
                jobCard(job)
            }
        }
    }

    private func jobCard(_ job: JobOpening) -> some View {
        Card {
            SectionTitle(title: job.title)
            Text(job.company).foregroundStyle(.secondary)
            SkillTags(skills: [job.level.rawValue, job.mode.rawValue])
            Button(model.isSaved(job) ? "Remover dos salvos" : "Salvar vaga") {
                model.toggleSaved(job)
            }
            .buttonStyle(.bordered)
            ShareLink(item: job.shareText) {
                Label("Compartilhar vaga", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func membership<Value: Hashable>(
        _ value: Value, in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(value)
                } else {
                    selection.wrappedValue.remove(value)
                }
            }
        )
    }
}

// MARK: - Mentoria

@MainActor
private struct MentoringView: View {
    @ObservedObject var model: CodeGirlsViewModel
    @State private var editing: Mentorship?

    var body: some View {
        Page(title: "Mentoria") {
            SectionTitle(title: "Suas mentorias")
            ForEach(model.scheduledMentorships) { item in
                Card {
                    SectionTitle(title: "Encontro com \(item.mentor.name)")
                    Text(item.date, format: .dateTime.day().month(.wide).hour().minute())
                        .foregroundStyle(.secondary)
                    Button("Reagendar") { editing = item }
                        .buttonStyle(.bordered)
                }
            }

            SectionTitle(title: "Conheça as mentoras")
            ForEach(model.mentors) { item in
                Card {
                    PersonRow(user: item.mentor)
                    SkillTags(skills: item.specialties)
                    if model.hasSession(item) {
                        Label("Mentoria agendada", systemImage: "checkmark.circle")
                            .foregroundStyle(violet)
                    } else {
                        PrimaryAction(title: "Solicitar Mentoria") { model.request(item) }
                    }
                }
            }
        }
        .sheet(item: $editing) { item in
            RescheduleView(mentorship: item) { date in
                model.reschedule(item, to: date)
            }
        }
    }
}

@MainActor
private struct RescheduleView: View {
    @Environment(\.dismiss) private var dismiss
    let mentorship: Mentorship
    let onSave: (Date) -> Bool

    @State private var date: Date
    @State private var showError = false
    private let earliestDate: Date

    init(mentorship: Mentorship, onSave: @escaping (Date) -> Bool) {
        self.mentorship = mentorship
        self.onSave = onSave
        let earliest = Date.now
        earliestDate = earliest
        _date = State(initialValue: max(mentorship.date, earliest.addingTimeInterval(3_600)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(mentorship.mentor.name).font(.headline)
                DatePicker("Nova data e hora", selection: $date, in: earliestDate...)
                if showError {
                    Text("Escolha uma data e um horário futuros.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reagendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        if onSave(date) {
                            dismiss()
                        } else {
                            showError = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Navegação e ponto de entrada

private enum AppTab: String, CaseIterable, Identifiable {
    case home = "Início"
    case forums = "Fóruns"
    case network = "Network"
    case groups = "Grupos"
    case jobs = "Vagas"
    case mentoring = "Mentoria"

    var id: Self { self }

    var icon: String {
        switch self {
        case .home: return "house"
        case .forums: return "bubble.left.and.bubble.right"
        case .network: return "person.2"
        case .groups: return "person.3"
        case .jobs: return "briefcase"
        case .mentoring: return "sparkles"
        }
    }
}

@MainActor
private struct CodeGirlsTabs: View {
    @ObservedObject var model: CodeGirlsViewModel
    @State private var selection: AppTab = .home
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(model: model) }.tag(AppTab.home)
            NavigationStack { ForumsView(model: model) }.tag(AppTab.forums)
            NavigationStack { NetworkView(model: model) }.tag(AppTab.network)
            NavigationStack { GroupsView(model: model) }.tag(AppTab.groups)
            NavigationStack { JobsView(model: model) }.tag(AppTab.jobs)
            NavigationStack { MentoringView(model: model) }.tag(AppTab.mentoring)
        }
        // A barra em SwiftUI mantém as seis abas na base também em telas compactas.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Divider()
                ViewThatFits(in: .horizontal) {
                    if !typeSize.isAccessibilitySize {
                        tabRow(AppTab.allCases)
                    }
                    VStack(spacing: 2) {
                        tabRow(Array(AppTab.allCases.prefix(3)))
                        tabRow(Array(AppTab.allCases.suffix(3)))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
            .background(.white)
        }
        .task { await model.loadForums() }
    }

    private func tabRow(_ tabs: [AppTab]) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.body)
                            .accessibilityHidden(true)
                        Text(tab.rawValue)
                            .font(.caption2.weight(.semibold))
                            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                    }
                    .padding(.horizontal, 3)
                    .frame(minHeight: 46)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == tab ? violet : ink)
                    .background(
                        selection == tab ? lavender : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
    }
}

@main
@MainActor
struct CodeGirlsApp: App {
    @StateObject private var model = CodeGirlsViewModel()

    var body: some Scene {
        WindowGroup {
            CodeGirlsTabs(model: model)
                .tint(violet)
                .preferredColorScheme(.light)
                .environment(\.locale, Locale(identifier: "pt_BR"))
        }
    }
}
