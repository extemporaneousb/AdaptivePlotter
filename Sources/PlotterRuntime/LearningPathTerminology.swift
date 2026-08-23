/// Canonical end-user vocabulary for the Learning Path.
///
/// Stage and exercise names describe operator goals. Action names describe the
/// exact effect of a click. Runtime implementation terms such as "owner",
/// "admission", "typed", and "workflow coordinator" do not belong in this
/// vocabulary.
public enum LearningPathTerminology {
  public enum Stage {
    public static let plotterCalibration = "Plotter Calibration"
    public static let drawingValidation = "Drawing Validation"
  }

  public enum Exercise {
    public static let identifyAndCalibratePen = "Identify and Calibrate the Pen"
    public static let measureAndCenterDrawingBoundary =
      "Measure and Center the Drawing Boundary"
    public static let calibrateCameraFromPenCap =
      "Calibrate Camera from Pen Cap Positions"
    public static let calibratePenTipFromCornerMarks =
      "Calibrate Pen Tip from Corner Marks"
    public static let drawAndValidateFrame = "Draw and Validate the Frame"
  }

  public enum Action {
    public static let identifyPenCap = "Identify Pen Cap"
    public static let confirmPenUp = "Confirm Pen Up"
    public static let confirmPenDown = "Confirm Pen Down"
    public static let runCameraCalibration = "Run Five-Position Camera Calibration"
    public static let acceptCameraCalibration = "Accept Camera Calibration"
    public static let rejectCameraCalibration = "Reject Camera Calibration"
    public static let discardCameraSamples = "Discard Captured Samples"
    public static let drawCalibrationCircles = "Draw Four Calibration Circles"
    public static let acceptPenTipCalibration = "Accept Pen-Tip Calibration"
    public static let rejectPenTipCalibration = "Reject Pen-Tip Calibration"
    public static let drawAndValidateFrame = "Draw and Validate Frame"
    public static let useSavedLearning = "Use Saved Learning"
    public static let startNewLearning = "Start New Learning"
  }

  public enum Evidence {
    public static let acceptedDrawingBoundaryOverlay = "ACCEPTED DRAWING BOUNDARY"
    public static let drawingFrameValidation = "drawing-frame validation"
    public static let penTipCalibration = "pen-tip calibration"
  }
}
