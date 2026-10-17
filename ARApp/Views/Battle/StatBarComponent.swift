//
//  StatBarComponent.swift
//  ARApp
//

import SwiftUI

/// 名前と数値付きの横棒（HP バー・必殺技ゲージ共通）
struct StatBarComponent: View {
    let title: String
    let value: Int
    let maxValue: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(value) / \(maxValue)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(value) / CGFloat(maxValue))
                }
            }
            .frame(height: 12)
            .animation(.easeOut(duration: 0.2), value: value)
        }
    }
}

#Preview {
    StatBarComponent(title: "ネコ", value: 220, maxValue: 300, color: .green)
        .padding()
}
