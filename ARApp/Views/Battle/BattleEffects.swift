//
//  BattleEffects.swift
//  ARApp
//

import SwiftUI

/// バトル画面の演出（揺れ、踏み込み、タップの波紋、ダメージの数字、画面の光）

extension View {
    /// trigger が変わるたびに左右に揺れる（攻撃を受けた演出）
    func shake(trigger: UUID?) -> some View {
        phaseAnimator([0, -12, 12, -6, 0], trigger: trigger) { content, x in
            content.offset(x: x)
        } animation: { _ in
            .linear(duration: 0.05)
        }
    }

    /// trigger が変わるたびに offset の方向へ踏み込んで戻る（攻撃する演出）
    func lunge(_ offset: CGSize, trigger: UUID?) -> some View {
        phaseAnimator([CGSize.zero, offset, .zero], trigger: trigger) { content, value in
            content.offset(value)
        } animation: { _ in
            .easeOut(duration: 0.08)
        }
    }
}

/// タップした位置に広がって消える円
struct TapRippleComponent: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .stroke(.secondary, lineWidth: 2)
            .frame(width: 60, height: 60)
            .scaleEffect(isExpanded ? 1 : 0.2)
            .opacity(isExpanded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { isExpanded = true }
            }
    }
}

/// ダメージの数字。上に浮かびながら消える
struct FloatingDamageComponent: View {
    let text: String
    let color: Color
    let fontSize: CGFloat
    @State private var isFloating = false

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .shadow(radius: 2)
            .offset(y: isFloating ? -80 : -20)
            .opacity(isFloating ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { isFloating = true }
            }
    }
}

/// 画面全体が一瞬光って消える（必殺技の演出）
struct FlashComponent: View {
    @State private var isFading = false

    var body: some View {
        Color.yellow
            .opacity(isFading ? 0 : 0.6)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { isFading = true }
            }
    }
}
