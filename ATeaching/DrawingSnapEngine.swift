import SwiftUI

#if os(macOS)
struct DrawingSnapEngine {
    static func snap(
        shape: ShapeElement,
        to shapes: [ShapeElement],
        excluding excludedID: UUID?,
        movingHandle: ShapeHandleKey?
    ) -> ShapeElement {
        let targets = shapes.filter { $0.id != excludedID }
        guard !targets.isEmpty else { return shape }

        if let result = snapPointToPoint(shape, targets: targets, movingHandle: movingHandle) {
            return result
        }
        if let result = snapLineEndpointPerpendicular(shape, targets: targets, movingHandle: movingHandle) {
            return result
        }
        if let result = snapEdgeToEdge(shape, targets: targets) {
            return result
        }
        if let result = snapPointToLine(shape, targets: targets, movingHandle: movingHandle) {
            return result
        }
        return shape
    }

    private static func snapPointToPoint(
        _ shape: ShapeElement,
        targets: [ShapeElement],
        movingHandle: ShapeHandleKey?
    ) -> ShapeElement? {
        let tolerance: CGFloat = 10
        let movingPoints = snapPoints(for: shape, movingHandle: movingHandle)
        let targetPoints = targets.flatMap(\.snapPoints)

        var best: (source: SnapPoint, target: CGPoint, distance: CGFloat)?
        for source in movingPoints {
            for target in targetPoints {
                let distance = source.point.distance(to: target.point)
                guard distance <= tolerance else { continue }
                if best == nil || distance < best!.distance {
                    best = (source, target.point, distance)
                }
            }
        }

        guard let best else { return nil }
        return moveSnapPoint(best.source, in: shape, to: best.target)
    }

    private static func snapLineEndpointPerpendicular(
        _ shape: ShapeElement,
        targets: [ShapeElement],
        movingHandle: ShapeHandleKey?
    ) -> ShapeElement? {
        guard let movingHandle,
              let source = snapPoints(for: shape, movingHandle: movingHandle).first,
              let opposite = oppositePoint(for: movingHandle, in: shape),
              source.point.distance(to: opposite) > 8 else {
            return nil
        }

        let tolerance: CGFloat = 12
        let perpendicularTolerance = degreesToRadians(5)
        let currentAngle = atan2(source.point.y - opposite.y, source.point.x - opposite.x)
        let length = source.point.distance(to: opposite)

        var best: (projection: CGPoint, targetAngle: CGFloat, distance: CGFloat)?
        for segment in targets.flatMap(\.snapSegments) {
            let projection = projectedPoint(source.point, onto: segment)
            let distance = source.point.distance(to: projection)
            guard distance <= tolerance else { continue }

            let targetAngle = segment.angle
            let perpendicularDelta = min(
                angularDifference(currentAngle, targetAngle + .pi / 2),
                angularDifference(currentAngle, targetAngle - .pi / 2)
            )
            guard perpendicularDelta <= perpendicularTolerance else { continue }

            if best == nil || distance < best!.distance {
                best = (projection, targetAngle, distance)
            }
        }

        guard let best else { return nil }
        let candidateA = best.targetAngle + .pi / 2
        let candidateB = best.targetAngle - .pi / 2
        let snappedAngle = angularDifference(currentAngle, candidateA) <= angularDifference(currentAngle, candidateB)
            ? candidateA
            : candidateB
        let unit = CGPoint(x: cos(snappedAngle), y: sin(snappedAngle))

        var result = shape
        switch movingHandle {
        case .start:
            result.start = best.projection
            result.end = CGPoint(x: best.projection.x - unit.x * length, y: best.projection.y - unit.y * length)
        case .end:
            result.end = best.projection
            result.start = CGPoint(x: best.projection.x - unit.x * length, y: best.projection.y - unit.y * length)
        case .third:
            return nil
        }
        return result
    }

    private static func snapEdgeToEdge(
        _ shape: ShapeElement,
        targets: [ShapeElement]
    ) -> ShapeElement? {
        let distanceTolerance: CGFloat = 10
        let angleTolerance = degreesToRadians(10)
        let sourceSegments = shape.snapSegments
        let targetSegments = targets.flatMap(\.snapSegments)

        var best: (source: SnapSegment, target: SnapSegment, deltaAngle: CGFloat, distance: CGFloat)?
        for source in sourceSegments {
            for target in targetSegments {
                let sameDirectionDelta = angularDifference(source.angle, target.angle)
                let reversedDelta = angularDifference(source.angle, target.angle + .pi)
                let delta = min(sameDirectionDelta, reversedDelta)
                guard delta <= angleTolerance else { continue }

                let sourceMid = source.midpoint
                let projection = projectedPoint(sourceMid, onto: target)
                let distance = sourceMid.distance(to: projection)
                guard distance <= distanceTolerance else { continue }

                if best == nil || distance < best!.distance {
                    best = (source, target, sameDirectionDelta <= reversedDelta ? target.angle - source.angle : target.angle + .pi - source.angle, distance)
                }
            }
        }

        guard let best else { return nil }
        let rotatedSourceStart = rotate(best.source.start, around: best.source.start, by: best.deltaAngle)
        let snappedStart = projectedPoint(rotatedSourceStart, onto: best.target)
        let translated = CGPoint(x: snappedStart.x - rotatedSourceStart.x, y: snappedStart.y - rotatedSourceStart.y)
        return transform(shape, around: best.source.start, rotation: best.deltaAngle, translation: translated)
    }

    private static func snapPointToLine(
        _ shape: ShapeElement,
        targets: [ShapeElement],
        movingHandle: ShapeHandleKey?
    ) -> ShapeElement? {
        let tolerance: CGFloat = 9
        let movingPoints = snapPoints(for: shape, movingHandle: movingHandle)
        let targetSegments = targets.flatMap(\.snapSegments)

        var best: (source: SnapPoint, projection: CGPoint, distance: CGFloat)?
        for source in movingPoints {
            for segment in targetSegments {
                let projection = projectedPoint(source.point, onto: segment)
                let distance = source.point.distance(to: projection)
                guard distance <= tolerance else { continue }
                if best == nil || distance < best!.distance {
                    best = (source, projection, distance)
                }
            }
        }

        guard let best else { return nil }
        return moveSnapPoint(best.source, in: shape, to: best.projection)
    }

    private static func snapPoints(for shape: ShapeElement, movingHandle: ShapeHandleKey?) -> [SnapPoint] {
        let all = shape.snapPoints
        guard let movingHandle else { return all }
        return all.filter { $0.handle == movingHandle }
    }

    private static func moveSnapPoint(_ point: SnapPoint, in shape: ShapeElement, to target: CGPoint) -> ShapeElement {
        if let handle = point.handle {
            return setHandle(handle, in: shape, to: target)
        }
        let delta = CGPoint(x: target.x - point.point.x, y: target.y - point.point.y)
        return transform(shape, around: point.point, rotation: 0, translation: delta)
    }

    private static func setHandle(_ handle: ShapeHandleKey, in shape: ShapeElement, to target: CGPoint) -> ShapeElement {
        var result = shape
        if shape.isRotatableBox {
            switch handle {
            case .start:
                result.start = shape.unrotatedPoint(from: target)
                result.third = shape.preservedRotationHandle(forStart: result.start, end: result.end)
            case .end:
                result.end = shape.unrotatedPoint(from: target)
                result.third = shape.preservedRotationHandle(forStart: result.start, end: result.end)
            case .third:
                result.third = target
            }
            return result
        }

        switch handle {
        case .start:
            result.start = target
        case .end:
            result.end = target
        case .third:
            result.third = target
        }
        return result
    }

    private static func oppositePoint(for handle: ShapeHandleKey, in shape: ShapeElement) -> CGPoint? {
        switch handle {
        case .start:
            return shape.end
        case .end:
            return shape.start
        case .third:
            return nil
        }
    }

    private static func transform(
        _ shape: ShapeElement,
        around pivot: CGPoint,
        rotation: CGFloat,
        translation: CGPoint
    ) -> ShapeElement {
        var result = shape
        result.start = transformed(shape.start, around: pivot, rotation: rotation, translation: translation)
        result.end = transformed(shape.end, around: pivot, rotation: rotation, translation: translation)
        if let third = shape.third {
            result.third = transformed(third, around: pivot, rotation: rotation, translation: translation)
        }
        return result
    }

    private static func transformed(
        _ point: CGPoint,
        around pivot: CGPoint,
        rotation: CGFloat,
        translation: CGPoint
    ) -> CGPoint {
        let rotated = rotate(point, around: pivot, by: rotation)
        return CGPoint(x: rotated.x + translation.x, y: rotated.y + translation.y)
    }

    private static func rotate(_ point: CGPoint, around pivot: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return CGPoint(
            x: pivot.x + dx * cos(angle) - dy * sin(angle),
            y: pivot.y + dx * sin(angle) + dy * cos(angle)
        )
    }

    private static func projectedPoint(_ point: CGPoint, onto segment: SnapSegment) -> CGPoint {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let lengthSquared = max(1, dx * dx + dy * dy)
        let rawT = ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / lengthSquared
        let t = min(1, max(0, rawT))
        return CGPoint(x: segment.start.x + dx * t, y: segment.start.y + dy * t)
    }

    private static func angularDifference(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        var value = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi * 2)
        if value > .pi {
            value = .pi * 2 - value
        }
        if value > .pi / 2 {
            value = .pi - value
        }
        return abs(value)
    }

    private static func degreesToRadians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}

private struct SnapPoint {
    var point: CGPoint
    var handle: ShapeHandleKey?
}

private struct SnapSegment {
    var start: CGPoint
    var end: CGPoint

    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
    }

    var angle: CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }
}

private extension ShapeElement {
    var snapPoints: [SnapPoint] {
        switch tool {
        case .triangle:
            return [
                SnapPoint(point: start, handle: .start),
                SnapPoint(point: end, handle: .end),
                SnapPoint(point: third ?? fallbackTriangleThird, handle: .third)
            ]
        case .rectangle, .ellipse:
            return [
                SnapPoint(point: rotatedPoint(start), handle: .start),
                SnapPoint(point: rotatedPoint(end), handle: .end),
                SnapPoint(point: rotationHandlePoint, handle: .third)
            ]
        case .axis:
            return [
                SnapPoint(point: start, handle: .start),
                SnapPoint(point: end, handle: .end),
                SnapPoint(point: third ?? ShapeElement.defaultAxisSecondEndpoint(start: start, end: end), handle: .third)
            ]
        case .line, .arrow, .wall:
            return [
                SnapPoint(point: start, handle: .start),
                SnapPoint(point: end, handle: .end)
            ]
        }
    }

    var snapSegments: [SnapSegment] {
        switch tool {
        case .line, .arrow, .wall:
            return [SnapSegment(start: start, end: end)]
        case .axis:
            return [
                SnapSegment(start: start, end: end),
                SnapSegment(start: start, end: third ?? ShapeElement.defaultAxisSecondEndpoint(start: start, end: end))
            ]
        case .triangle:
            let p3 = third ?? fallbackTriangleThird
            return [
                SnapSegment(start: start, end: end),
                SnapSegment(start: end, end: p3),
                SnapSegment(start: p3, end: start)
            ]
        case .rectangle:
            let corners = rotatedRectCorners
            return [
                SnapSegment(start: corners[0], end: corners[1]),
                SnapSegment(start: corners[1], end: corners[2]),
                SnapSegment(start: corners[2], end: corners[3]),
                SnapSegment(start: corners[3], end: corners[0])
            ]
        case .ellipse:
            return []
        }
    }

    private var rawRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(1, abs(end.x - start.x)),
            height: max(1, abs(end.y - start.y))
        )
    }

    private var center: CGPoint {
        CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
    }

    private var fallbackTriangleThird: CGPoint {
        CGPoint(
            x: (start.x + end.x) * 0.5,
            y: min(start.y, end.y) - max(24, abs(end.x - start.x) * 0.55)
        )
    }

    private var rotationHandlePoint: CGPoint {
        third ?? CGPoint(x: rawRect.midX, y: rawRect.minY - 28)
    }

    private var rotationAngle: CGFloat {
        guard third != nil else { return 0 }
        return atan2(rotationHandlePoint.y - center.y, rotationHandlePoint.x - center.x) + .pi / 2
    }

    private var rotatedRectCorners: [CGPoint] {
        [
            CGPoint(x: rawRect.minX, y: rawRect.minY),
            CGPoint(x: rawRect.maxX, y: rawRect.minY),
            CGPoint(x: rawRect.maxX, y: rawRect.maxY),
            CGPoint(x: rawRect.minX, y: rawRect.maxY)
        ].map(rotatedPoint)
    }

    private func rotatedPoint(_ point: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(rotationAngle) - dy * sin(rotationAngle),
            y: center.y + dx * sin(rotationAngle) + dy * cos(rotationAngle)
        )
    }
}
#endif
