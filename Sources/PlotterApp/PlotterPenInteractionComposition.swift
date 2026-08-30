import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime

struct OperatorWorkspacePenInteractionActuationPort: PlotterPenInteractionActuationPort {
  let machineActions: OperatorWorkspace.MachineActions?
  let simulatedAdapter: PlotterCausalSimulatorEffectAdapter
  let nowNanoseconds: @Sendable () -> UInt64

  func settle(
    _ request: PlotterPenInteractionActuationRequest
  ) async -> PlotterPenInteractionActuationSettlement {
    switch request.environment {
    case .live:
      guard let machineActions else {
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
        using: machineActions,
        command: request.command,
        profile: request.profile
      )
      let snapshot = await machineActions.snapshot()
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
    RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
  }
}

enum PlotterPenInteractionComposition {
  static func makeRuntime(
    machineActions: OperatorWorkspace.MachineActions?,
    simulatedAdapter: PlotterCausalSimulatorEffectAdapter,
    nowNanoseconds: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) -> PlotterPenInteractionRuntime {
    PlotterPenInteractionRuntime(port: OperatorWorkspacePenInteractionActuationPort(
      machineActions: machineActions,
      simulatedAdapter: simulatedAdapter,
      nowNanoseconds: nowNanoseconds
    ))
  }
}
