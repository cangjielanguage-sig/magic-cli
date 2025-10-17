package cli.telemetry.otel

public enum MetricType {
    | Counter
    | UpDownCounter
    | Histogram
    | ObservableCounter
    | ObservableGauge
}
