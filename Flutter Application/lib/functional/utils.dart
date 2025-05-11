import 'dart:math';
import 'package:tracking_app/domain/measurement.dart';

/* ---------- DISTANCES ---------------------------------------------- */
List<double> get_distances(List<Measurement> measurements) {
  double cum = 0;
  final list = <double>[0];
  for (var i = 1; i < measurements.length; i++) {
    cum += haversine(measurements[i - 1], measurements[i]);
    list.add(cum);
  }
  return list; // km
}

const _rEarth = 6371.0; // km
double haversine(Measurement a, Measurement b) {
  final dLat = _deg(b.lat - a.lat);
  final dLon = _deg(b.lon - a.lon);
  final lat1 = _deg(a.lat);
  final lat2 = _deg(b.lat);
  final h =
      pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
  return 2 * _rEarth * asin(sqrt(h));
}

double _deg(double d) => d * pi / 180;

/* ---------- MINIMAL LOESS ------------------------------------------ */
List<double> loess(List<double> x, List<double> y,
    {double window = .1, int iters = 2}) {
  try {
    final n = x.length;
    if (n < 3) return List<double>.from(y); // Return original if too few points

    // Calculate window size - at least 3 points, at most n points
    final wSize = max(3, min(n, (window * n).round()));

    // Start with original values
    var yHat = List<double>.from(y);

    // Optimize: pre-compute distances between points
    final distances =
        List.generate(n, (i) => List.generate(n, (j) => (x[i] - x[j]).abs()));

    // Run multiple iterations of LOESS for robustness
    for (var iter = 0; iter < iters; iter++) {
      final res = List<double>.filled(n, 0); // Store residuals

      // For each point, fit a local polynomial
      for (var i = 0; i < n; i++) {
        try {
          // Get distances from current point to all others
          final dists = distances[i];

          // Find indices of nearest neighbors
          final indices = List.generate(n, (j) => j);
          indices.sort((a, b) => dists[a].compareTo(dists[b]));
          final nn = indices.take(wSize).toList();

          // Calculate max distance in this neighborhood
          double dMax = nn.map((j) => dists[j]).reduce(max);
          if (dMax <= 0) dMax = 1.0; // Avoid division by zero

          // Compute tricube weights: w(x) = (1 - (d/dMax)³)³
          final w = [
            for (final j in nn)
              dists[j] >= dMax
                  ? 0.0
                  : pow(1 - pow((dists[j] / dMax), 3), 3).toDouble()
          ];

          // Check if weights are valid
          if (w.every((weight) => weight == 0)) {
            // All weights are zero, skip this point
            continue;
          }

          // Create design matrix X with columns [1, dx, dx²]
          final List<List<double>> X = [
            for (final j in nn)
              [
                1.0, // Constant term
                (x[j] - x[i]), // Linear term
                pow(x[j] - x[i], 2).toDouble(), // Quadratic term
              ]
          ];

          // Compute X transpose
          final List<List<double>> XT = List.generate(
            3,
            (k) => [for (final row in X) row[k]],
          );

          // Create diagonal weight matrix
          final List<List<double>> W = List.generate(
            wSize,
            (r) => List.generate(wSize, (c) => r == c ? w[r] : 0.0),
          );

          // Matrix calculations for weighted least squares
          final XT_W = _matMul(XT, W);
          final XTW_X = _matMul(XT_W, X);
          final XTW_y = _matVec(XT_W, [for (final j in nn) y[j]]);

          // Solve for coefficients
          final beta = _solve(XTW_X, XTW_y);

          // Predict at the current point (since x[i] - x[i] = 0, only beta[0] matters)
          yHat[i] = beta[0];

          // Calculate absolute residual
          res[i] = (y[i] - yHat[i]).abs();
        } catch (e) {
          // If calculation fails for this point, keep original value
          // and continue with next point
          yHat[i] = y[i];
        }
      }
    }

    return yHat;
  } catch (e) {
    // Return original data if anything goes wrong
    return List<double>.from(y);
  }
}

/* ---------- LINEAR-ALGEBRA HELPERS ---------------------------------- */
List<List<double>> _matMul(List<List<double>> A, List<List<double>> B) {
  final m = A.length, n = B[0].length, k = B.length;
  return List.generate(
    m,
    (i) => List.generate(
      n,
      (j) => Iterable<int>.generate(k)
          .map((l) => A[i][l] * B[l][j])
          .reduce((a, b) => a + b),
    ),
  );
}

List<double> _matVec(List<List<double>> A, List<double> v) => [
      for (final row in A)
        Iterable<int>.generate(v.length)
            .map((i) => row[i] * v[i])
            .reduce((a, b) => a + b)
    ];

List<double> _solve(List<List<double>> A, List<double> b) {
  double det(List<List<double>> m) =>
      m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
      m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
      m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

  final d = det(A);
  if (d.abs() < 1e-12) return [0, 0, 0];

  List<double> col(int c) => [for (final r in A) r[c]];
  final dx = det([b, col(1), col(2)]);
  final dy = det([col(0), b, col(2)]);
  final dz = det([col(0), col(1), b]);
  return [dx / d, dy / d, dz / d];
}
