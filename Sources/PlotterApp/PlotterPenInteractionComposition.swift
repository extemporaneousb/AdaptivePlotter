import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime

struct PlotterApplicationRuntimePenInteractionActuationPort: PlotterPenInteractionActuationPort {
  let machineSession: (any PlotterMachineSession)?
  let simulatedAdapter: PlotterCausalSimulatorEffectAdapter
  let clock: any RuntimeClock

  func settle(
    _ request: PlotterPenInteractionActuationRequest
  ) async -> PlotterPenInteractionActuationSettlement {
    switch request.environment {
    case .live:
      guard let machineSession else {
        return PlotterPenInteractionActuationSettlement(
          operationID: request.operationID,
          outcome: .refused(.notConnected),
          machineSnapshot: nil,
          simulatedTruth: nil,
          observedPosition: nil,
          timestamp: timestamp
        )
      }
      let outcome = await PlotterManualMotionComposition.settleNativePenCommand(
        using: machineSession,
        command: request.command,
        profile: request.profile
      )
      let snapshot = await machineSession.snapshot()
      return PlotterPenInteractionActuationSettlement(
        operationID: request.operationID,
        outcome: outcome,
        machineSnapshot: snapshot,
        simulatedTruth: nil,
        observedPosition: snapshot?.machine.position,
        timestamp: timestamp
      )

    case .simulated:
      let pose: SimulatedLearningPenPose = request.command == .raise ? .up : .down
      let result = await simulatedAdapter.executeRetainedWorkflowPen(
        pose,
        owner: EpisodeAuthorityID(rawValue: "PlotterPenInteractionRuntime")
      )
      let outcome: PenOutcome
      if let refusal = result.refusal {
        if case .stickyAmbiguity(let ambiguity) = refusal {
          outcome = .ambiguous(.transport("causal simulator ambiguity: \(ambiguity)"))
        } else {
          outcome = .refused(.controllerRejected("causal simulator refusal: \(refusal)"))
        }
      } else {
        outcome = .commandedAndSettled(
          command: request.command,
          commandedState: request.command.commandedState
        )
      }
      return PlotterPenInteractionActuationSettlement(
        operationID: request.operationID,
        outcome: outcome,
        machineSnapshot: nil,
        simulatedTruth: result.truth,
        observedPosition: nil,
        timestamp: timestamp
      )
    }
  }

  private var timestamp: RuntimeTimestamp {
    RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
  }
}

enum PlotterPenInteractionComposition {
  static func makeRuntime(
    machineSession: (any PlotterMachineSession)?,
    simulatedAdapter: PlotterCausalSimulatorEffectAdapter,
    clock: any RuntimeClock = SystemRuntimeClock()
  ) -> PlotterPenInteractionRuntime {
    PlotterPenInteractionRuntime(port: PlotterApplicationRuntimePenInteractionActuationPort(
      machineSession: machineSession,
      simulatedAdapter: simulatedAdapter,
      clock: clock
    ))
  }
}
