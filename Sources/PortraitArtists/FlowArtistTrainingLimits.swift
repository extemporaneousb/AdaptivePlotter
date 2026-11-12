/// Logical allocation limits for a current local fit. Frozen historical
/// readers separately bound the shared storage they materialize.
package enum FlowArtistTrainingLimits {
  package static let maximumFeatureValues = 10_000_000
  package static let maximumLabels = 20_000
  package static let maximumComparisons = 20_000

  package static func accepts(featureValueCount: Int, explicitLabelCount: Int) -> Bool {
    (0...maximumFeatureValues).contains(featureValueCount)
      && (0...maximumLabels).contains(explicitLabelCount)
  }
}
