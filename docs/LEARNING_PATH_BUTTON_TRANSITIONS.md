# Learning Path Button Transitions

This diagram inventories every normal Learning Path button and the state reached
by clicking it. **Connect** and **Enable Motion** belong to the workbench
toolbar. They are external prerequisites, not Learning Path stages, exercises,
or transitions.

```mermaid
flowchart TD
  subgraph workbench["External workbench prerequisites — not Learning Path steps"]
    frame["Current exact camera or simulated frame"]
    connected["Controller session connected"]
    motion["Motion enabled"]
    connected -->|required before| motion
  end

  subgraph pen["1.1 Identify and Calibrate the Pen"]
    p0["Ready<br/>Identify Pen Cap"]
    p1["Frozen frame awaiting cap-body click<br/>Cancel Attempt"]
    p2["Set and verify Up<br/>Pen Up slider · Confirm Pen Up · Cancel Attempt"]
    p3["Set and verify Down<br/>Pen Down slider · Confirm Pen Down · Cancel Attempt"]
    p4["Verify return to Up<br/>Pen Up slider · Confirm Pen Up · Cancel Attempt"]
    pdone["1.1 complete<br/>Redo This Step · Record Another Attempt"]
    pcancel["Attempt settled without acceptance<br/>Restart Attempt"]
    p0 -->|Identify Pen Cap| p1
    p1 -->|valid cap-body point selection — not a button| p2
    p2 -->|Confirm Pen Up| p3
    p3 -->|Confirm Pen Down| p4
    p4 -->|Confirm Pen Up| pdone
    p1 -->|Cancel Attempt| pcancel
    p2 -->|Cancel Attempt| pcancel
    p3 -->|Cancel Attempt| pcancel
    p4 -->|Cancel Attempt| pcancel
    pcancel -->|Restart Attempt| p0
    pdone -->|Redo This Step — replace accepted result| p0
    pdone -->|Record Another Attempt — retain additional evidence| p0
  end

  subgraph boundary["1.2 Measure and Center the Drawing Boundary"]
    b0["Choose an allowed direction<br/>direction selectors · Move Toward X−/X+/Y−/Y+"]
    b1["Moving toward selected side<br/>Stop Boundary Search"]
    b2["Side recorded<br/>next allowed direction · Move Toward direction"]
    b3["Four sides recorded<br/>Move to Estimated Center<br/>accepted-side repeat actions"]
    bdone["1.2 complete<br/>accepted-side Redo / Record Another actions"]
    b0 -->|direction selector — selection only| b0
    b0 -->|Move Toward direction| b1
    b1 -->|Stop Boundary Search and settle| b2
    b2 -->|direction selector — selection only| b2
    b2 -->|Move Toward next direction| b1
    b2 -->|after fourth side| b3
    b3 -->|Move to Estimated Center| bdone
    b3 -->|Redo named Boundary — replace accepted side| b1
    b3 -->|Record Another named Attempt — retain evidence| b1
    bdone -->|Redo named Boundary — replace accepted side| b1
    bdone -->|Record Another named Attempt — retain evidence| b1
  end

  subgraph camera["1.3 Calibrate Camera from Pen Cap Positions"]
    c0["Ready<br/>Run Five-Position Camera Calibration"]
    c1["Automatic five-position measurement<br/>Run Five-Position Camera Calibration… — disabled<br/>Stop replaces it during stoppable motion"]
    c2["Calibration review<br/>Accept Camera Calibration<br/>Reject Camera Calibration · Cancel Attempt"]
    cempty["Stopped or rejected; no proposal<br/>Run Five-Position Camera Calibration<br/>Discard Captured Samples · Cancel Attempt"]
    cdone["1.3 complete<br/>Redo This Step"]
    ccancel["Attempt settled without acceptance<br/>Restart Attempt"]
    c0 -->|Run Five-Position Camera Calibration| c1
    c1 -->|three fit and two check measurements pass| c2
    c1 -->|Stop and settle current motion| cempty
    c2 -->|Accept Camera Calibration| cdone
    c2 -->|Reject Camera Calibration| cempty
    c2 -->|Cancel Attempt| ccancel
    cempty -->|Run Five-Position Camera Calibration| c1
    cempty -->|Discard Captured Samples| cempty
    cempty -->|Cancel Attempt| ccancel
    ccancel -->|Restart Attempt| c0
    cdone -->|Redo This Step — replace accepted result| c0
  end

  subgraph tip["1.4 Calibrate Pen Tip from Corner Marks"]
    s0["Ready<br/>Draw Four Calibration Circles"]
    s1["Automatic four-circle drawing and reveal<br/>busy action — disabled<br/>Stop replaces it during stoppable motion"]
    s2["Frozen reveal frame; zero clicks<br/>Cancel Attempt"]
    s2partial["Frozen reveal frame; one to three clicks<br/>Undo Last Click · Clear Clicks on This Frame<br/>Cancel Attempt"]
    s3["Pen-tip calibration review<br/>Accept Pen-Tip Calibration · Undo Last Click<br/>Clear Clicks on This Frame · Reject Pen-Tip Calibration · Cancel Attempt"]
    sdone["1.4 complete<br/>Redo This Step"]
    scancel["Attempt settled without acceptance<br/>Restart Attempt"]
    spaper["Possible-ink location excluded<br/>Record Paper Replacement"]
    s0 -->|Draw Four Calibration Circles| s1
    s1 -->|one final reveal frame| s2
    s1 -->|Stop before possible contact| scancel
    s1 -->|Stop or ambiguity after possible contact| spaper
    s2 -->|first valid point selection| s2partial
    s2partial -->|second or third valid point selection| s2partial
    s2partial -->|fourth valid point selection| s3
    s2 -->|Cancel Attempt| scancel
    s2partial -->|Undo Last Click — clicks remain| s2partial
    s2partial -->|Undo Last Click — count returns to zero| s2
    s2partial -->|Clear Clicks on This Frame| s2
    s2partial -->|Cancel Attempt| scancel
    s3 -->|Accept Pen-Tip Calibration| sdone
    s3 -->|Reject Pen-Tip Calibration| s2
    s3 -->|Undo Last Click| s2partial
    s3 -->|Clear Clicks on This Frame| s2
    s3 -->|Cancel Attempt| scancel
    scancel -->|Restart Attempt| s0
    spaper -->|Record Paper Replacement| s0
    sdone -->|Redo This Step — replace accepted result| s0
  end

  subgraph validation["2.1 Draw and Validate the Frame"]
    t0["Ready<br/>Draw and Validate Frame"]
    t1["Automatic six-phase validation<br/>Draw and Validate Frame… — disabled<br/>Stop replaces it during stoppable motion"]
    tdone["2.1 complete<br/>exact comparison remains reviewable"]
    trecovery["Interrupted / possible-ink recovery<br/>Resume Frame Observation or Retry Frame Validation<br/>never automatic redraw"]
    t0 -->|Draw and Validate Frame| t1
    t1 -->|settled drawing, observation, and comparison| tdone
    t1 -->|Stop, ambiguity, or possible ink| trecovery
    trecovery -->|Resume Frame Observation when no redraw is needed| tdone
    trecovery -->|Retry Frame Validation only when a new drawing is safe| t0
  end

  frame -.->|enables Identify Pen Cap| p0
  connected -.->|required after the cap click| p2
  motion -.->|required after the cap click| p2
  pdone --> b0
  motion -.->|required| b0
  bdone --> c0
  motion -.->|required| c0
  cdone --> s0
  motion -.->|required| s0
  sdone --> t0
  motion -.->|required| t0
```

Dependency behavior is intentionally asymmetric:

- Motion Enabled implies a connected controller session.
- **Identify Pen Cap** requires only a current exact frame.
- After the cap click, **Confirm Pen Up** and the Pen Up slider remain visible
  but disabled until connection and Motion authorization exist.
- Exercises 1.2, 1.3, 1.4, and 2.1 keep their normal action visible and name the
  exact missing workbench prerequisite.
- Satisfying a prerequisite enables the existing action. It never inserts a
  Learning Path **Connect**, **Enable Motion**, generic **Start**, **Next**,
  **Go**, or redundant acceptance step.

The two normal-flow acceptance buttons commit reviewable calibration evidence;
they are not forward gates. **Accept Camera Calibration** commits the
five-position camera calibration. **Accept Pen-Tip Calibration** commits the
four-click pen-tip calibration. Exercises 1.3 and 1.4 begin directly with their
physical actions.
