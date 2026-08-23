# Learning Path Button Transitions

This diagram inventories the buttons owned by the Learning Path action strip and
the state reached by each normal click. **Connect** and **Enable Motion** belong
to the workbench toolbar, so they are dependencies shown outside the Learning
Path rather than navigator rows or exercise transitions.

```mermaid
flowchart TD
  subgraph workbench["External workbench facts — not Learning Path steps"]
    frame["Current exact camera or simulated frame"]
    connected["Controller session connected"]
    motion["Motion enabled"]
    connected -->|prerequisite| motion
  end

  subgraph pen["3.1 Pen Interaction"]
    p0["Ready<br/>Identify Pen Cap"]
    p1["Frozen frame awaiting cap-body click<br/>Cancel Attempt"]
    p2["Up confirmation<br/>Up slider · Next · Cancel Attempt"]
    p3["Down confirmation<br/>Down slider · Next · Cancel Attempt"]
    p4["Final Up confirmation<br/>Up slider · Next · Cancel Attempt"]
    pdone["3.1 complete<br/>Redo This Step · Record Another Attempt"]
    pcancel["Attempt settled without acceptance<br/>Restart"]
    p0 -->|Identify Pen Cap| p1
    p1 -->|valid cap-body click — point selection, not a button| p2
    p2 -->|Next| p3
    p3 -->|Next| p4
    p4 -->|Next| pdone
    p1 -->|Cancel Attempt| pcancel
    p2 -->|Cancel Attempt| pcancel
    p3 -->|Cancel Attempt| pcancel
    p4 -->|Cancel Attempt| pcancel
    pcancel -->|Restart| p0
    pdone -->|Redo This Step — replacement| p0
    pdone -->|Record Another Attempt — additional evidence| p0
  end

  subgraph boundary["3.2 Paired Boundary Discovery and Centering"]
    b0["Choose an allowed direction<br/>direction selectors · Start"]
    b1["Boundary motion owns the controller<br/>Stop Boundary"]
    b2["Side settled<br/>next allowed direction · Start"]
    b3["Four sides accepted<br/>Move to Estimated Center<br/>accepted-side repeat actions"]
    bdone["3.2 complete<br/>accepted-side Redo / Record Another actions"]
    b0 -->|direction selector — change pending direction only| b0
    b0 -->|Start| b1
    b1 -->|Stop Boundary and settle| b2
    b2 -->|direction selector — change pending direction only| b2
    b2 -->|Start next side| b1
    b2 -->|after fourth side| b3
    b3 -->|Move to Estimated Center| bdone
    b3 -->|Redo named Boundary — replacement| b1
    b3 -->|Record Another named Attempt — additional evidence| b1
    bdone -->|Redo named Boundary — replacement| b1
    bdone -->|Record Another named Attempt — additional evidence| b1
  end

  subgraph camera["3.3 Calibrate Camera and Visible Cap"]
    c0["Ready<br/>Capture Five Cap Samples"]
    c1["Automatic five-position capture<br/>Capturing Five Cap Samples… — disabled<br/>Stop replaces it while a motion owner is stoppable"]
    c2["Fit proposal review<br/>Accept Camera and Visible-Cap Fit<br/>Reject Camera Fit · Cancel Attempt"]
    cempty["Stopped or rejected; same attempt, no proposal<br/>Capture Five Cap Samples<br/>Discard Cap Samples · Cancel Attempt"]
    cdone["3.3 complete<br/>Redo This Step"]
    ccancel["Attempt settled without acceptance<br/>Restart"]
    c0 -->|Capture Five Cap Samples| c1
    c1 -->|five accepted samples and fit| c2
    c1 -->|Stop and settle current motion| cempty
    c2 -->|Accept Camera and Visible-Cap Fit| cdone
    c2 -->|Reject Camera Fit| cempty
    c2 -->|Cancel Attempt| ccancel
    cempty -->|Capture Five Cap Samples| c1
    cempty -->|Discard Cap Samples| cempty
    cempty -->|Cancel Attempt| ccancel
    ccancel -->|Restart| c0
    cdone -->|Redo This Step — replacement| c0
  end

  subgraph tip["3.4 Calibrate Pen Contact from Sparse Marks"]
    s0["Ready<br/>Draw Four Corner Circles"]
    s1["Automatic four-circle batch and reveal<br/>busy phase action — disabled<br/>Stop replaces it while stoppable"]
    s2["Frozen reveal frame; zero clicks<br/>Cancel Attempt"]
    s2partial["Frozen reveal frame; one to three clicks<br/>Undo Last Click · Clear Clicks on This Frame<br/>Cancel Attempt"]
    s3["Tip-map proposal review<br/>Accept Tip Map · Undo Last Click<br/>Clear Clicks on This Frame · Reject Tip Map · Cancel Attempt"]
    sdone["3.4 complete<br/>Redo This Step"]
    scancel["Attempt settled without acceptance<br/>Restart"]
    spaper["Possible-ink location blacklisted<br/>Record Paper Replacement"]
    s0 -->|Draw Four Corner Circles| s1
    s1 -->|one reveal frame| s2
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
    s3 -->|Accept Tip Map| sdone
    s3 -->|Reject Tip Map| s2
    s3 -->|Undo Last Click| s2partial
    s3 -->|Clear Clicks on This Frame| s2
    s3 -->|Cancel Attempt| scancel
    scancel -->|Restart| s0
    spaper -->|Record Paper Replacement| s0
    sdone -->|Redo This Step — replacement| s0
  end

  subgraph trial["4.1 Run Predicted Picture Frame Trial"]
    t0["Ready<br/>Go"]
    t1["One automatic six-phase trial<br/>current phase… — disabled<br/>Stop replaces it while stoppable"]
    tdone["4.1 complete<br/>exact comparison remains reviewable"]
    trecovery["Possible-ink / interrupted recovery<br/>Continue Observation or Retry Trial<br/>never automatic redraw"]
    t0 -->|Go| t1
    t1 -->|settled execution, observation, comparison| tdone
    t1 -->|Stop, ambiguity, or possible ink| trecovery
    trecovery -->|Continue Observation when no redraw is needed| tdone
    trecovery -->|Retry Trial only when a new trial is safe| t0
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

- `motion enabled` implies `controller session connected`;
- **Identify Pen Cap** requires only a current exact frame;
- after the cap click, the first **Next** and its servo slider remain visible but
  disabled until connection and Motion authorization exist;
- 3.2, 3.3, 3.4, and 4.1 expose their normal exercise action in place, disabled
  with the exact missing workbench dependency;
- satisfying a dependency enables the existing action. It never inserts a
  Learning Path **Connect**, **Enable Motion**, **Start**, **Continue**, or
  acceptance step.

The two normal-flow acceptance buttons are evidence commits, not forward gates:
**Accept Camera and Visible-Cap Fit** commits the five-sample registration, and
**Accept Tip Map** commits the four-click tip registration. Stage 3.3 begins
directly with **Capture Five Cap Samples**, and Stage 3.4 begins directly with
**Draw Four Corner Circles**; neither has a preceding generic **Start**.
