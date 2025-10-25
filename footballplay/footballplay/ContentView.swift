//
//  ContentView.swift
//  footballplay
//
//  Created by fredericli on 2025/10/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedZoom = 1
    private let zoomLevels: [ZoomLevel] = [
        .init(label: "0.5x", factor: 0.5),
        .init(label: "1x", factor: 1.0),
        .init(label: "2x", factor: 2.0),
        .init(label: "3x", factor: 3.0)
    ]
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LiveBackground(cameraManager: cameraManager)
                    .ignoresSafeArea()
                
                ScoreboardView()
                    .padding(.leading, 12)
                    .padding(.top, 12)
            }
            .overlay(alignment: .trailing) {
                LiveControlStack()
                    .padding(.trailing, -8)
                    .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) {
                ControlDock(
                    zoomLevels: zoomLevels,
                    selectedZoom: $selectedZoom
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
    var body: some View {
        HStack(spacing: 6) {
            ScoreTile(team: "熱血踢球隊", score: "00", color: .blue)
            SetBadge(set: 1)
            ScoreTile(team: "TFA 阿寶亮斯", score: "00", color: .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.65))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        )
        .scaleEffect(1.25, anchor: .topLeading)
    }
}

private struct ScoreTile: View {
    let team: String
    let score: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(team)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.white.opacity(0.15), in: Capsule())
            Text(score)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.9))
                )
        }
    }
}

private struct SetBadge: View {
    let set: Int
    
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
    }
}

private struct ControlDock: View {
    let zoomLevels: [ZoomLevel]
    @Binding var selectedZoom: Int
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZoomSelector(levels: zoomLevels, selectedZoom: $selectedZoom)
            
            DockDivider(height: 24)
            
            RecordingPanel()
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
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("錄影時間")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text("00:00:00")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            Text("目前：上半場")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
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
    var body: some View {
        VStack(spacing: 10) {
            CaptureButton(icon: "dot.radiowaves.left.and.right", title: "直播", tint: .green, foreground: .white, size: 44)
            CaptureButton(icon: "record.circle.fill", title: "錄影", tint: .red, foreground: .white, size: 44)
            CaptureButton(icon: "stop.circle.fill", title: "停止", tint: .gray.opacity(0.5), foreground: .white, size: 44)
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
    
    var body: some View {
        VStack(spacing: 6) {
            Button {
                // Placeholder
            } label: {
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
