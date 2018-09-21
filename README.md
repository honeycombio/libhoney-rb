# libhoney [![Build Status](https://travis-ci.org/honeycombio/libhoney-rb.svg?branch=master)](https://travis-ci.org/honeycombio/libhoney-rb) [![Gem Version](https://badge.fury.io/rb/libhoney.svg)](https://badge.fury.io/rb/libhoney)

Ruby gem for sending events to [Honeycomb](https://honeycomb.io). (For more information, see the [documentation](https://honeycomb.io/docs/) and [Ruby SDK guide](https://honeycomb.io/docs/connect/ruby).)

## Installation

To install the stable release:

```
gem install libhoney
```

or add `libhoney` to your `Gemfile`:

```ruby
gem 'libhoney'

# or, to follow the bleeding edge:
# gem 'libhoney', git: 'https://github.com/honeycombio/libhoney-rb.git'
```

This gem has some native dependencies, so if you see an error along the lines of "Failed to build gem native extension", you may need to install the Ruby development headers and a C++ compiler. e.g. on Ubuntu:

```
sudo apt-get install build-essential ruby-dev
```

Note that `libhoney` requires Ruby 2.2 or greater.


## Documentation

An API reference is available at [rubydoc.info/gems/libhoney](http://www.rubydoc.info/gems/libhoney).

## Example Usage

Honeycomb can calculate all sorts of statistics, so send the values you care about and let us crunch the averages, percentiles, lower/upper bounds, cardinality -- whatever you want -- for you.

```ruby
require 'libhoney'

# Create a client instance
honeycomb = Libhoney::Client.new(
  # Use an environment variable to set your write key with something like
  # `writekey: ENV['HONEYCOMB_WRITEKEY']`,
  writekey: 'YOUR_WRITE_KEY',
  dataset:  'honeycomb-ruby-example'
)

honeycomb.send_now({
  duration_ms:    153.12,
  method:         'get',
  hostname:       'appserver15',
  payload_length: 27
})

# Call close to flush any pending calls to Honeycomb
honeycomb.close
```

Check out the documentation for [`Libhoney::Client`](http://www.rubydoc.info/gems/libhoney/Libhoney/Client) for more detailed API documentation.

You can find a more complete example demonstrating usage in [`example/factorial.rb`](example/factorial.rb)

## Debugging instrumentation

If you've instrumented your code to send events to Honeycomb, you may want to
verify that you're sending the events you expected at the right time with the
desired fields. To support this use case, `libhoney` provides a
[`LogClient`](http://www.rubydoc.info/gems/libhoney/Libhoney/LogClient) that
outputs events to standard error, which you can swap in for the usual `Client`.
Example usage:

```ruby
honeycomb = Libhoney::LogClient.new

my_app = MyApp.new(..., honeycomb, ...)
my_app.do_stuff

# should output events to standard error
```

Note that this will disable sending events to Honeycomb, so you'll want to
revert this change once you've verified that the events are coming through
appropriately.

## Testing instrumented code

Once you've instrumented your code to send events to Honeycomb, you may want to
consider writing tests that verify your code is producing the events you expect,
annotating them with the right information, etc. That way, if your code changes
and breaks the instrumentation, you'll find out straight away, instead of at 3am
when you need that data available for debugging!

To support this use case, `libhoney` provides a
[`TestClient`](http://www.rubydoc.info/gems/libhoney/Libhoney/TestClient) which
you can swap in for the usual `Client`. Example usage:

```ruby
fakehoney = Libhoney::TestClient.new

my_app = MyApp.new(..., fakehoney, ...)
my_app.do_stuff

expect(fakehoney.events.size).to eq 3

first_event = fakehoney.events[0]
expect(first_event.data['hovercraft_contents']).to eq 'Eels'
```

For more detail see the docs for
[`TestClient`](http://www.rubydoc.info/gems/libhoney/Libhoney/TestClient) and
[`Event`](http://www.rubydoc.info/gems/libhoney/Libhoney/Event).

## Contributions

Features, bug fixes and other changes to `libhoney` are gladly accepted. Please
open issues or a pull request with your change. Remember to add your name to the
CONTRIBUTORS file!

All contributions will be released under the Apache License 2.0.

### Releasing a new version

Travis will automatically upload tagged releases to Rubygems. To release a new
version, run
```
bump patch --tag   # Or bump minor --tag, etc.
git push --follow-tags
```
