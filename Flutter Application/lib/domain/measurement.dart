class Measurement {
  final DateTime t;
  final double lat, lon, gpsAlt;
  final double? baroAlt;
  Measurement(this.t, this.lat, this.lon, this.gpsAlt, this.baroAlt);
}
