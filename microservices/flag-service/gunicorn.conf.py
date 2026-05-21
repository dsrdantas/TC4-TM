import os
import logging

_log = logging.getLogger(__name__)


def post_fork(server, worker):
    """Reinitialize OTel SDK in each worker after gunicorn fork.

    opentelemetry-instrument configures the SDK in the master process.
    When gunicorn forks workers, Python does NOT clone background threads,
    so the BatchSpanProcessor export thread dies. Spans are queued but never
    sent. This hook reinitializes the full SDK — new providers, fresh export
    threads — and re-applies library patches so they bind to the new providers.
    """
    try:
        _setup_otel_worker()
        _log.info("[OTel] worker %s: SDK reinitialized", worker.pid)
    except Exception as exc:
        _log.error("[OTel] worker %s: failed to reinitialize SDK: %s", worker.pid, exc)


def _setup_otel_worker():
    import opentelemetry.trace as trace_api
    import opentelemetry.metrics as metrics_api
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.metrics import MeterProvider
    from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
    from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.propagate import set_global_textmap
    from opentelemetry.propagators.composite import CompositePropagator
    from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
    from opentelemetry.baggage.propagation import W3CBaggagePropagator

    # The OTel API only allows set_tracer_provider() once (returns early on
    # subsequent calls to protect against accidental double-init in a single
    # process). In forked workers we MUST replace the dead master provider,
    # so we reset the internal sentinel first.
    trace_api._TRACER_PROVIDER = None
    metrics_api._METER_PROVIDER = None

    endpoint = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318",
    )
    service_name = os.getenv("OTEL_SERVICE_NAME", "flag-service")
    environment = os.getenv("OTEL_ENVIRONMENT", "production")

    resource = Resource.create({
        "service.name": service_name,
        "service.namespace": "togglemaster",
        "deployment.environment": environment,
        "telemetry.sdk.language": "python",
        "telemetry.sdk.name": "opentelemetry",
    })

    # Traces — fresh BatchSpanProcessor with its own background thread
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{endpoint}/v1/traces"))
    )
    trace_api.set_tracer_provider(tracer_provider)

    # Metrics
    reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=f"{endpoint}/v1/metrics"),
        export_interval_millis=15000,
    )
    metrics_api.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

    # Propagators — W3C TraceContext + Baggage (required to link spans across services)
    set_global_textmap(CompositePropagator([
        TraceContextTextMapPropagator(),
        W3CBaggagePropagator(),
    ]))

    _reinstrument()
    _refresh_db_pool()


def _reinstrument():
    """Uninstrument then re-instrument each library so its cached tracer
    references the new TracerProvider, not the dead master one.

    skip_dep_check=True is required because psycopg2-binary satisfies the
    psycopg2 API but has a different package name, causing a false-positive
    DependencyConflict when pkg_resources checks the requirement string.
    """
    for mod_path, cls_name in [
        ("opentelemetry.instrumentation.flask", "FlaskInstrumentor"),
        ("opentelemetry.instrumentation.psycopg2", "Psycopg2Instrumentor"),
        ("opentelemetry.instrumentation.requests", "RequestsInstrumentor"),
    ]:
        try:
            import importlib
            mod = importlib.import_module(mod_path)
            instrumentor = getattr(mod, cls_name)()
            if instrumentor.is_instrumented_by_opentelemetry:
                instrumentor.uninstrument()
            instrumentor.instrument(skip_dep_check=True)
        except Exception as exc:
            _log.warning("[OTel] failed to reinstrument %s: %s", cls_name, exc)


def _refresh_db_pool():
    """Close idle connections in the pool so next getconn() creates new ones
    via the re-patched psycopg2.connect, producing properly traced connections.

    Does NOT call pool.closeall() — that sets pool.closed=True permanently.
    Instead we empty the idle list directly, leaving the pool object intact.
    """
    try:
        from app import pool
        for conn in list(pool._pool):
            try:
                conn.close()
            except Exception:
                pass
        pool._pool.clear()
    except Exception as exc:
        _log.warning("[OTel] failed to refresh DB pool: %s", exc)
