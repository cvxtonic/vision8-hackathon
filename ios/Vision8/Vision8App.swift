import SwiftUI

@main
struct Vision8App: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Ink.dawn)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                Screen {
                    VStack(spacing: 20) {
                        Text("Vision 8").font(.display(40))
                        if let error = model.loadError {
                            ErrorNote(text: error).fixedSize()
                            Button("Noch einmal versuchen") { Task { await model.refresh() } }
                                .buttonStyle(PressStyle(filled: false))
                                .frame(width: 240)
                        } else {
                            ProgressView().tint(Ink.dawn)
                        }
                    }
                    .padding(32)
                }
            case .onboarding:
                OnboardingFlow()
            case .main:
                MainTabs()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.phase == .main { Task { await model.refresh() } }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            TodayView().tabItem { Label("Heute", systemImage: "sun.horizon") }
            TalkView().tabItem { Label("Coach", systemImage: "waveform") }
            VisionView().tabItem { Label("Vision", systemImage: "sparkles") }
            SettingsView().tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(Ink.night, for: .tabBar)
        .overlay(alignment: .bottom) {
            if model.call.active, !model.call.ending, !model.call.crisis {
                CoachBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 64) // above the tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.call.active)
        .sheet(isPresented: Binding(get: { model.call.expanded }, set: { model.call.expanded = $0 })) {
            CoachSheet()
                .presentationDetents([.fraction(0.4), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
        }
        .sheet(isPresented: Binding(get: { model.call.ending || model.call.crisis }, set: { if !$0 { model.call.close() } })) {
            CoachSummary().presentationDetents([.medium])
        }
        // The server ends the talk (the coach said goodbye): sum it up without a tap.
        .onChange(of: model.call.live.state) { _, state in
            if state == .finished { model.call.end(model.api) { await model.refresh() } }
            if case .failed = state { model.call.bank() }
        }
    }
}
