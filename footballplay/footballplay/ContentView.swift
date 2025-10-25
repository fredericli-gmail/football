//
//  ContentView.swift
//  footballplay
//
//  Created by fredericli on 2025/10/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var scoreboard: ScoreboardState
    @StateObject private var cameraManager: CameraManager
    @State private var selectedZoom = 1
    private let zoomLevels: [ZoomLevel] = [
        .init(label: "0.5x", factor: 0.5),
        .init(label: "1x", factor: 1.0),
        .init(label: "2x", factor: 2.0),
        .init(label: "3x", factor: 3.0)
    ]
    
    init() {
        let scoreboard = ScoreboardState()
        _scoreboard = StateObject(wrappedValue: scoreboard)
        _cameraManager = StateObject(wrappedValue: CameraManager(scoreboard: scoreboard))
    }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LiveBackground(cameraManager: cameraManager)
                    .ignoresSafeArea()
                
                ScoreboardView(state: scoreboard)
                    .padding(.leading, 12)
                    .padding(.top, 12)
            }
            .overlay(alignment: .trailing) {
                LiveControlStack(cameraManager: cameraManager)
                    .padding(.trailing, -8)
                    .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) {
                ControlDock(
                    zoomLevels: zoomLevels,
                    selectedZoom: $selectedZoom,
                    cameraManager: cameraManager
                )
                .padding(.horizontal, max(8, proxy.size.width * 0.02))
                .padding(.vertical, 2)
                .background(Color.clear)
            }
        }
        .onChange(of: selectedZoom) { newValue in
            cameraManager.setZoom(factor: zoomLevels[newValue].factor)
        }
        .onChange(of: cameraManager.isConfigured) { ready in
            if ready {
                cameraManager.setZoom(factor: zoomLevels[selectedZoom].factor)
            }
        }
    }
}

private struct ZoomLevel {
    let label: String
    let factor: CGFloat
}

private extension TimeInterval {
    var formattedTime: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Layout Components

private struct VideoBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [.black, .gray.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LiveBackground: View {
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        #if targetEnvironment(simulator)
        fallbackView(message: "Simulator 不支援實際鏡頭。請於真機查看直播畫面")
        #else
        switch cameraManager.authorizationStatus {
        case .authorized:
            if cameraManager.isConfigured {
                CameraPreviewView(session: cameraManager.session)
                    .overlay(gradientOverlay)
            } else {
                fallbackView(message: "正在啟動鏡頭...")
            }
        case .denied, .restricted:
            fallbackView(message: "請在設定中允許相機權限。")
        case .notDetermined:
            fallbackView(message: "等待相機授權...")
        @unknown default:
            fallbackView(message: "相機狀態未知")
        }
        #endif
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            colors: [.black.opacity(0.15), .black.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func fallbackView(message: String) -> some View {
        VideoBackdrop()
            .overlay(
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                .padding(24), alignment: .center
            )
    }
}

private struct ScoreboardView: View {
    @ObservedObject var state: ScoreboardState
    @State private var editTarget: EditTarget?
    @State private var inputValue = ""
    
    var body: some View {
        HStack(spacing: 10) {
            ScoreTile(team: state.homeTeamName,
                      score: state.homeScore,
                      color: .blue,
                      onTap: { state.homeScore += 1 },
                      onLongPressName: { beginEditing(.homeName) },
                      onLongPressScore: { beginEditing(.homeScore) })
            SetBadge(set: state.currentSet,
                     onTap: { state.currentSet += 1 },
                     onLongPress: { beginEditing(.set) })
            ScoreTile(team: state.awayTeamName,
                      score: state.awayScore,
                      color: .green,
                      onTap: { state.awayScore += 1 },
                      onLongPressName: { beginEditing(.awayName) },
                      onLongPressScore: { beginEditing(.awayScore) })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.65))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        )
        .scaleEffect(1.25, anchor: .topLeading)
        .sheet(item: $editTarget) { target in
            ScoreboardEditSheet(target: target,
                                inputValue: inputBinding,
                                onSave: applyEdit)
        }
    }
    
    private var inputBinding: Binding<String> {
        Binding(get: { inputValue }, set: { inputValue = $0 })
    }
    
    private func beginEditing(_ target: EditTarget) {
        inputValue = target.currentValue(from: state)
        editTarget = target
    }
    
    private func applyEdit(for target: EditTarget) {
        switch target {
        case .homeName:
            state.homeTeamName = inputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .awayName:
            state.awayTeamName = inputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .homeScore:
            if let value = Int(inputValue) { state.homeScore = max(0, value) }
        case .awayScore:
            if let value = Int(inputValue) { state.awayScore = max(0, value) }
        case .set:
            if let value = Int(inputValue) { state.currentSet = max(1, value) }
        }
    }
}

private struct ScoreTile: View {
    let team: String
    let score: Int
    let color: Color
    var onTap: () -> Void
    var onLongPressName: () -> Void
    var onLongPressScore: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Text(team)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.white.opacity(0.15), in: Capsule())
                .onLongPressGesture(perform: onLongPressName)
            Text(String(format: "%02d", score))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.9))
                )
                .onTapGesture(perform: onTap)
                .onLongPressGesture(perform: onLongPressScore)
        }
    }
}

private struct SetBadge: View {
    let set: Int
    var onTap: () -> Void
    var onLongPress: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(set)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("Set")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 36, height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.4))
        )
        .onTapGesture(perform: onTap)
        .onLongPressGesture(perform: onLongPress)
    }
}

private enum EditTarget: Identifiable {
    case homeName, awayName, homeScore, awayScore, set
    var id: String {
        switch self {
        case .homeName: return "homeName"
        case .awayName: return "awayName"
        case .homeScore: return "homeScore"
        case .awayScore: return "awayScore"
        case .set: return "set"
        }
    }
    
    var title: String {
        switch self {
        case .homeName: return "編輯主隊名稱"
        case .awayName: return "編輯客隊名稱"
        case .homeScore: return "設定主隊分數"
        case .awayScore: return "設定客隊分數"
        case .set: return "設定場次"
        }
    }
    
    var keyboard: UIKeyboardType {
        switch self {
        case .homeName, .awayName:
            return .default
        case .homeScore, .awayScore, .set:
            return .numberPad
        }
    }
    
    func currentValue(from state: ScoreboardState) -> String {
        switch self {
        case .homeName: return state.homeTeamName
        case .awayName: return state.awayTeamName
        case .homeScore: return String(state.homeScore)
        case .awayScore: return String(state.awayScore)
        case .set: return String(state.currentSet)
        }
    }
}

private struct ScoreboardEditSheet: View {
    let target: EditTarget
    @Binding var inputValue: String
    var onSave: (EditTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(target.title)) {
                    TextField("輸入值", text: $inputValue)
                        .keyboardType(target.keyboard)
                }
            }
            .navigationTitle("編輯比分")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(target)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ControlDock: View {
    let zoomLevels: [ZoomLevel]
    @Binding var selectedZoom: Int
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZoomSelector(levels: zoomLevels, selectedZoom: $selectedZoom)
            
            DockDivider(height: 24)
            
            RecordingPanel(manager: cameraManager)
                .frame(maxWidth: 160)
            
            DockDivider(height: 24)
            
            FineTunePanel()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.black.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        )
    }
}

private struct ZoomSelector: View {
    let levels: [ZoomLevel]
    @Binding var selectedZoom: Int
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Button {
                    selectedZoom = index
                } label: {
                    Text(level.label)
                        .font(.caption)
                        .fontWeight(index == selectedZoom ? .bold : .medium)
                        .foregroundStyle(index == selectedZoom ? Color.yellow : Color.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(index == selectedZoom ? .white.opacity(0.25) : .black.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RecordingPanel: View {
    @ObservedObject var manager: CameraManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("錄影時間")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(manager.isRecording ? Color.red : Color.gray)
                Text(manager.recordingDuration.formattedTime)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            Text("目前：上半場")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            if let message = manager.lastSaveMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.12))
        )
    }
}

private struct FineTunePanel: View {
    var body: some View {
        HStack(spacing: 6) {
            FineTuneButton(icon: "camera.aperture", label: "鏡頭")
            FineTuneButton(icon: "slider.horizontal.3", label: "設定")
        }
    }
}

private struct FineTuneButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(.white.opacity(0.18))
                )
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

private struct DockDivider: View {
    var height: CGFloat = 30
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: height)
    }
}

private struct LiveControlStack: View {
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        VStack(spacing: 10) {
            CaptureButton(icon: "dot.radiowaves.left.and.right", title: "直播", tint: .green, foreground: .white, size: 44) {
                // TODO: integrate live streaming
            }
            CaptureButton(icon: cameraManager.isRecording ? "pause.circle.fill" : "record.circle.fill",
                           title: cameraManager.isRecording ? "錄影中" : "錄影",
                           tint: cameraManager.isRecording ? .red : .red,
                           foreground: .white,
                           size: 44) {
                if !cameraManager.isRecording {
                    cameraManager.startRecording()
                }
            }
            CaptureButton(icon: "stop.circle.fill", title: "停止", tint: .gray.opacity(0.5), foreground: .white, size: 44) {
                cameraManager.stopRecording()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.black.opacity(0.65))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        )
        .frame(width: 120)
    }
}

private struct CaptureButton: View {
    let icon: String
    let title: String
    let tint: Color
    let foreground: Color
    var size: CGFloat = 72
    var action: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(foreground)
                    .frame(width: size, height: size)
                    .background(Circle().fill(tint))
            }
            .buttonStyle(.plain)
            
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

#Preview {
    ContentView()
        .previewInterfaceOrientation(.landscapeLeft)
}
