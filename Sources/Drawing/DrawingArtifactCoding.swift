import Foundation
import CryptoKit

/// Stable JSON and digest primitives shared by current authored artifacts.
public enum DrawingArtifactCoding {
  public static func sha256(_ bytes:Data)->String {
    SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
  }
  public static func encoder()->JSONEncoder {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];return encoder
  }

}

public enum DrawingArtifactLimits {
  public static let sourceBytes = 32 * 1024 * 1024
  public static let maximumStrokes = 10_000
  public static let maximumImageDimension = 8192
  public static let maximumImagePixels = 32 * 1024 * 1024
}
