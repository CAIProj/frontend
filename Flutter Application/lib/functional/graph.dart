import 'dart:math';

import 'package:equations/equations.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:tracking_app/functional/utils.dart';
import 'package:tracking_app/domain/measurement.dart';

/* ---------------- CHART -------------------------------------------- */
enum GraphFilter { Raw, Spline, LOESS }

class TrackGraph extends StatefulWidget {
  final List<Measurement> measurements;

  const TrackGraph({super.key, required List<Measurement> this.measurements});
  @override
  State<TrackGraph> createState() =>
      _TrackGraphState(measurements: measurements);
}

class _TrackGraphState extends State<TrackGraph> {
  final List<Measurement> measurements;
  GraphFilter _selFilter = GraphFilter.Raw;

  bool _showRaw = true;
  bool _showSmoothed = true;

  _TrackGraphState({required List<Measurement> this.measurements});

  List<double> _applyFilter(List<double> x, List<double> y) {
    // Safety: too few data or non-increasing? -> Return raw data
    if (x.length < 3) return List<double>.from(y);

    // Ensure x values are sorted and unique for proper interpolation
    List<double> xVals = List<double>.from(x);
    List<double> yVals = List<double>.from(y);

    // For completely identical values, return the original
    if (xVals.toSet().length <= 1) return yVals;

    switch (_selFilter) {
      case GraphFilter.Spline:
        try {
          // Create a clean list of nodes with strictly increasing x values
          final nodes = <InterpolationNode>[];
          double lastX = double.negativeInfinity;

          for (var i = 0; i < xVals.length; i++) {
            if (xVals[i] > lastX) {
              nodes.add(InterpolationNode(x: xVals[i], y: yVals[i]));
              lastX = xVals[i];
            }
          }

          // Need at least 3 points for a proper spline
          if (nodes.length < 3) return yVals;

          final spline = SplineInterpolation(nodes: nodes);

          // Now compute the spline for each original x value
          List<double> smoothed = [];
          for (var i = 0; i < xVals.length; i++) {
            try {
              smoothed.add(spline.compute(xVals[i]));
            } catch (e) {
              // Fallback to original if spline computation fails
              smoothed.add(yVals[i]);
            }
          }
          return smoothed;
        } catch (e) {
          // If any error occurs, return the original data
          return yVals;
        }

      case GraphFilter.LOESS:
        try {
          return loess(xVals, yVals, window: .25, iters: 3);
        } catch (e) {
          return yVals;
        }

      default:
        return yVals;
    }
  }

  Widget _buildChart(List<double> x, List<double> yRaw, List<double> sm) {
    if (x.length < 2) {
      return const Center(
        child: Text('No data available for chart'),
      );
    }

    final minY = (yRaw.isEmpty ? 0 : yRaw.reduce(min)).toDouble() - 10;
    final maxY = (yRaw.isEmpty ? 100 : yRaw.reduce(max)).toDouble() + 10;

    // Create the line bars data based on visibility settings
    final lineBarsData = <LineChartBarData>[];

    // Add raw data line if visible
    if (_showRaw) {
      lineBarsData.add(_line(yRaw, x, Colors.blue, false, 'Raw'));
    }

    // Add smoothed data line if visible
    if (_showSmoothed) {
      lineBarsData.add(
          _line(sm, x, Colors.orange, true, 'Smoothed (${_selFilter.name})'));
    }

    // Chart legend
    final legend = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_showRaw) ...[
          Container(
            width: 16,
            height: 3,
            color: Colors.blue,
          ),
          const SizedBox(width: 5),
          const Text('Raw'),
          const SizedBox(width: 20),
        ],
        if (_showSmoothed) ...[
          Container(
            width: 16,
            height: 3,
            color: Colors.orange,
          ),
          const SizedBox(width: 5),
          Text('Smoothed (${_selFilter.name})'),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: x.isEmpty ? 1 : x.last,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor:
                        Theme.of(context).colorScheme.surface.withOpacity(0.8),
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.toStringAsFixed(1)} m\n${spot.x.toStringAsFixed(2)} km',
                          TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            value.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                    axisNameWidget: const Text('Distance (km)'),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                    axisNameWidget: const Text('Altitude (m)'),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: lineBarsData,
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          legend, // Display the legend at the bottom
        ],
      ),
    );
  }

  LineChartBarData _line(
          List<double> y, List<double> x, Color c, bool dash, String title) =>
      LineChartBarData(
        spots: [
          for (var i = 0; i < y.length; i++) FlSpot(x[i], y[i]),
        ],
        isCurved: true,
        color: c,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        dashArray: dash ? [8, 4] : null,
        belowBarData: BarAreaData(
          show: true,
          color: c.withOpacity(0.2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dist = get_distances(measurements);
    final altRaw = measurements.map((x) => x.baroAlt ?? x.gpsAlt).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Graph visibility controls
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Raw data toggle
                          Row(
                            children: [
                              Checkbox(
                                value: _showRaw,
                                onChanged: (val) {
                                  setState(() => _showRaw = val ?? true);
                                },
                              ),
                              const Text('Raw Data'),
                            ],
                          ),
                          const SizedBox(width: 16),
                          // Smoothed data toggle
                          Row(
                            children: [
                              Checkbox(
                                value: _showSmoothed,
                                onChanged: (val) {
                                  setState(() => _showSmoothed = val ?? true);
                                },
                              ),
                              const Text('Smoothed'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Smoothening options
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DropdownButton<GraphFilter>(
                          value: _selFilter,
                          items: GraphFilter.values.map((GraphFilter value) {
                            return DropdownMenuItem<GraphFilter>(
                              value: value,
                              child: Text(value.name),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              _selFilter = newValue!;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                )),
            // The chart
            Expanded(
              child: _buildChart(dist, altRaw, _applyFilter(dist, altRaw)),
            ),
          ],
        ),
      ),
    );
  }
}
