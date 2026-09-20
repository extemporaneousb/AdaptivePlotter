import Foundation
import PlotterModel

/// Runtime bridge for captured controller settings. Parsing stays beside the
/// controller protocol; pure Model policy never reads or changes firmware.
public enum DrawingMotionPolicyContext {
  public static let continuousStrategyRevision = "$J-bounded-stroke-v1"
  public static let isolatedStrategyRevision = "$J-idle-per-segment-v1"

  public static func controllerLimits(from probe: PassiveProbeResult?) -> DrawingControllerMotionLimits {
    controllerLimits(from: probe?.exchanges ?? [])
  }

  public static func controllerLimits(from exchanges: [PassiveProbeExchange]) -> DrawingControllerMotionLimits {
    var values: [String: Double] = [:]
    for exchange in exchanges where exchange.query == .configuration {
      for line in exchange.lines {
        guard case .configuration(let key, let value) = line.kind else { continue }
        // An invalid later readback invalidates the earlier setting.
        if let number = Double(value), number.isFinite, number >= 0,
          key == "$11" || number > 0 { values[key] = number } else { values[key] = nil }
      }
    }
    return try! DrawingControllerMotionLimits(maximumXFeedMMPerMinute: values["$110"],
      maximumYFeedMMPerMinute: values["$111"], xAccelerationMMPerSecondSquared: values["$120"],
      yAccelerationMMPerSecondSquared: values["$121"], junctionDeviationMM: values["$11"])
  }

  public static func makeRecipe(plan: ExecutionPlanRevision, travelFeedMMPerMinute: Double,
    drawingFeedMMPerMinute: Double, penActuationProfile: PenActuationProfile,
    probe: PassiveProbeResult?, continuity: DrawingMotionPolicy.Continuity) throws -> DrawingMotionRecipe {
    let policy = try DrawingMotionPolicy(continuity: continuity,
      drawingFeedMMPerMinute: drawingFeedMMPerMinute, travelFeedMMPerMinute: travelFeedMMPerMinute,
      pen: DrawingMotionPenPolicy(raisedSpindleValue: penActuationProfile.raisedSpindleValue,
        loweredSpindleValue: penActuationProfile.loweredSpindleValue,
        settleSeconds: penActuationProfile.settleSeconds), controllerLimits: controllerLimits(from: probe),
      executionStrategyRevision: continuity == .continuousWithinStroke
        ? continuousStrategyRevision : isolatedStrategyRevision)
    return try DrawingPlanner.motionRecipe(for: plan, policy: policy)
  }

  public static func validate(recipe: DrawingMotionRecipe, plan: ExecutionPlanRevision,
    travelFeedMMPerMinute: Double, drawingFeedMMPerMinute: Double,
    penActuationProfile: PenActuationProfile, requireSupportedStrategy: Bool = true) throws {
    try recipe.validate(plan: plan)
    let supported = recipe.policy.continuity == .continuousWithinStroke
      ? continuousStrategyRevision : isolatedStrategyRevision
    guard !requireSupportedStrategy || recipe.policy.executionStrategyRevision == supported else {
      throw PlotterModelError.invalidValue("unsupported drawing motion execution strategy")
    }
    guard recipe.policy.travelFeedMMPerMinute == travelFeedMMPerMinute,
      recipe.policy.drawingFeedMMPerMinute == drawingFeedMMPerMinute,
      recipe.policy.pen.raisedSpindleValue == penActuationProfile.raisedSpindleValue,
      recipe.policy.pen.loweredSpindleValue == penActuationProfile.loweredSpindleValue,
      recipe.policy.pen.settleSeconds == penActuationProfile.settleSeconds else {
      throw PlotterModelError.invalidValue("drawing motion recipe differs from requested feeds or pen settings")
    }
  }
}
