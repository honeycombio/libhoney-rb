# ruby-wiki-tracing

This example illustrates a simple wiki application instrumented with the bare minimum necessary to utilize Honeycomb's tracing functionality.

## What We'll Do in This Example

We'll instrument a simple application for tracing by following a few general steps:

1. Set a top-level `trace.trace_id` at the origin of the request and set it on the request context. Generate a root span indicated by omitting a `trace.parent_id` field.
2. To represent a unit of work within a trace as a span, add code to generate a span ID and capture the start time. At the **call site** of the unit of work, pass down a new request context with the newly-generated span ID as the `trace.parent_id`. Upon work completion, send the span with a calculated `duration_ms`.
3. Rinse and repeat.

**Note**: The [OpenTelemetry for Ruby](https://docs.honeycomb.io/getting-data-in/opentelemetry/ruby/) handles all of this propagation magic for you :)

## Usage

You can [find your API key](https://docs.honeycomb.io/getting-data-in/api-keys/#find-api-keys) in your Environment Settings.
If you do not have an API key yet, sign up for a [free Honeycomb account](https://ui.honeycomb.io/signup).


Once you have your API key, run:

```bash
$ HONEYCOMB_API_KEY=foobarbaz ruby wiki.rb
```

And load [`http://localhost:4567/view/MyFirstWikiPage`](http://localhost:4567/view/MyFirstWikiPage) to create (then view) your first wiki page.

Methods within the simple wiki application have been instrumented with tracing-like calls, with tracing identifiers propagated via thread locals.

## Tips for Instrumenting Your Own Service

- For a given span (e.g. `"loadPage"`), remember that the span definition lives in its parent, and the instrumentation is around the **call site** of `loadPage`:
    ```ruby
    with_span("load_page") do
      # sets the appropriate "parent id" within the scope of the block
      load_page(title)
      # span is sent to Honeycomb upon completion of the block
    end
    ```
- If emitting Honeycomb events or structured logs, make sure that the **start** time gets used as the canonical timestamp, not the time at event emission.
- Remember, the root span should **not** have a `trace.parent_id`.
- Don't forget to add some metadata of your own! It's helpful to identify metadata in the surrounding code that might be interesting when debugging your application.
- Check out [OpenTelemetry for Ruby](https://docs.honeycomb.io/getting-data-in/opentelemetry/ruby/) to get this context propagation for free!

## A Note on Code Style

The purpose of this example is to illustrate the **bare minimum necessary** to propagate and set identifiers to enable tracing on an application for consumption by Honeycomb, illustrating the steps described in the top section of this README. We prioritized legibility over style and intentionally resisted refactoring that would sacrifice clarity. :)
