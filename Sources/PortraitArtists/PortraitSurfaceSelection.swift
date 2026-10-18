import Foundation
import PlotterModel

/// Bounded experimental proposals over an existing Flow Edge program. These
/// landmark-relative regions are geometric proxies, not learned skin segmentation,
/// age judgments, or a claim that a fixed number of marks expresses a surface.
package enum PortraitSurfaceSelection {
  package static let revision = "flow-surface-exercise-v1"
  package struct Decision: Codable, Equatable, Sendable {
    package let strokeID: StrokeID
    package let region: String
    package let featureProtected: Bool
    package let evidenceScore: Double
    package let retained: Bool
  }
  package struct Proposal: Codable, Sendable {
    package let revision: String
    package let round: Int
    package let decisions: [Decision]
    package var removedIDs: [StrokeID] { decisions.filter { !$0.retained }.map(\.strokeID) }
  }
  private struct Candidate {
    let strokeID: StrokeID
    let region: String
    let protected: Bool
    let score: Double
    let center: CGPoint
  }

  package static func propose(program: DrawingProgram, raster: PortraitRaster, round: Int) throws -> Proposal {
    guard [1,2].contains(round), let field = PortraitRegionalTreatment.Field(raster: raster),
      let face = raster.faceAnalysis?.boundingBox else {
      throw PortraitDrawingError.unreadableImage
    }
    let w = Double(raster.width), h = Double(raster.height)
    func luminance(_ p: CGPoint) -> Double {
      let x = min(raster.width-1,max(0,Int(p.x.rounded())))
      let y = min(raster.height-1,max(0,Int(p.y.rounded())))
      return raster.luminance[y*raster.width+x]
    }
    var candidates: [Candidate] = []
    for stroke in program.strokes {
      try Task.checkCancellation()
      let points = stroke.path.points.map { CGPoint(x: $0.x/program.fieldExtent.width*w-0.5,
        y: (1-$0.y/program.fieldExtent.height)*h-0.5) }
      let center = points.reduce(CGPoint.zero) { CGPoint(x: $0.x+$1.x,y: $0.y+$1.y) }
      let mean = CGPoint(x: center.x/Double(points.count),y: center.y/Double(points.count))
      let source = field.sourcePoint(mean)
      let u = (source.x-face.x)/face.width, v = (source.y-face.y)/face.height
      // Keep every candidate touching measured feature or jaw support. In
      // particular, do not prune eyes by line length or try to classify reflections.
      let protected = points.contains { field.protection($0) > 0.12 || field.weight($0,region: .silhouette) > 0.25 }
      let region: String
      if protected { region = "features-and-jaw" }
      else if v < 0 { region = "hair" }
      else if v > 1.05 { region = u < 0.5 ? "left-clothing" : "right-clothing" }
      else if u < -0.08 || u > 1.08 { region = "outer" }
      else if v < 0.28 { region = "forehead" }
      else if v > 0.80 { region = "chin" }
      else { region = u < 0.5 ? "left-cheek" : "right-cheek" }
      let gradient = points.reduce(0.0) { value,p in
        value + hypot(luminance(.init(x:p.x+1,y:p.y))-luminance(.init(x:p.x-1,y:p.y)),
          luminance(.init(x:p.x,y:p.y+1))-luminance(.init(x:p.x,y:p.y-1)))
      }/Double(points.count)
      let pixels = zip(points,points.dropFirst()).reduce(0.0) { $0+hypot($1.1.x-$1.0.x,$1.1.y-$1.0.y) }
      // Evidence, continuity and spatial coverage rank surface candidates. No
      // change to points, width or ordering is permitted by this selector.
      candidates.append(Candidate(strokeID: stroke.id,region: region,protected: protected,
        score: gradient * sqrt(max(1,pixels)),center: mean))
    }
    let budgets = round == 1
      ? ["forehead":4,"left-cheek":4,"right-cheek":4,"chin":3,"hair":8,"left-clothing":5,"right-clothing":5,"outer":5]
      : ["forehead":4,"left-cheek":2,"right-cheek":2,"chin":2,"hair":5,"left-clothing":2,"right-clothing":2,"outer":3]
    var retained = Set(candidates.filter(\.protected).map(\.strokeID))
    for region in budgets.keys.sorted() {
      let ranked = candidates.filter { $0.region == region }.sorted {
        $0.score == $1.score ? $0.strokeID.rawValue.uuidString < $1.strokeID.rawValue.uuidString : $0.score > $1.score
      }
      var centers: [CGPoint] = []
      for candidate in ranked {
        guard centers.count < budgets[region]! else { break }
        let separation = round == 1 ? 7.0 : 11.0
        guard centers.allSatisfy({ hypot($0.x-candidate.center.x,$0.y-candidate.center.y) >= separation }) else { continue }
        retained.insert(candidate.strokeID); centers.append(candidate.center)
      }
    }
    guard !retained.isEmpty else { throw PortraitDrawingError.noLines }
    return Proposal(revision: revision,round: round,decisions: candidates.map {
      Decision(strokeID:$0.strokeID,region:$0.region,featureProtected:$0.protected,
        evidenceScore:$0.score,retained:retained.contains($0.strokeID))
    })
  }
}
