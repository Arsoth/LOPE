// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import SwiftUI

struct DPIStageTriangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

struct DPIStagePentagon: Shape {
  private let cornerRadius: CGFloat = 3

  func path(in rect: CGRect) -> Path {
    let vertices = [
      CGPoint(x: rect.midX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38),
      CGPoint(x: rect.minX + rect.width * 0.81, y: rect.maxY),
      CGPoint(x: rect.minX + rect.width * 0.19, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38),
    ]
    let roundedVertices = vertices.enumerated().map { index, vertex in
      let previous = vertices[(index + vertices.count - 1) % vertices.count]
      let next = vertices[(index + 1) % vertices.count]
      return (
        before: point(on: vertex, toward: previous, distance: cornerRadius),
        after: point(on: vertex, toward: next, distance: cornerRadius),
        vertex: vertex
      )
    }

    var path = Path()
    path.move(to: roundedVertices[0].before)
    for (index, roundedVertex) in roundedVertices.enumerated() {
      if index > 0 {
        path.addLine(to: roundedVertex.before)
      }
      path.addQuadCurve(to: roundedVertex.after, control: roundedVertex.vertex)
    }
    path.addLine(to: roundedVertices[0].before)
    path.closeSubpath()
    return path
  }

  private func point(on vertex: CGPoint, toward other: CGPoint, distance: CGFloat) -> CGPoint {
    let dx = other.x - vertex.x
    let dy = other.y - vertex.y
    let length = max(sqrt(dx * dx + dy * dy), 0.001)
    let fraction = min(distance, length / 2) / length
    return CGPoint(x: vertex.x + dx * fraction, y: vertex.y + dy * fraction)
  }
}

enum DPIStagePalette {
  static let shift = Color(red: 0.20, green: 0.52, blue: 0.94)
  static let defaultStage = Color(red: 0.91, green: 0.24, blue: 0.25)
  //static let other = Color(red: 0.72, green: 0.83, blue: 0.20)
  static let other = Color(red: 0.95, green: 0.70, blue: 0.15)
  static let bar = Color(red: 0.42, green: 0.45, blue: 0.50)
}

func formattedDPIValue(_ value: Int) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.locale = .current
  formatter.usesGroupingSeparator = true
  formatter.minimumFractionDigits = 0
  formatter.maximumFractionDigits = 0
  return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

enum DPILegendRole: Hashable {
  case defaultStage
  case shift
  case other
}

struct DPIStageDragUpdate: Equatable {
  let index: Int
  let value: Int
}

struct DPIStageSelection: Identifiable, Equatable {
  let index: Int

  var id: Int { index }
}

struct DPIStagePopupFrameKey: PreferenceKey {
  static var defaultValue: CGRect? = nil

  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}
