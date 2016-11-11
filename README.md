libhoney
========
Ruby gem for sending events to http://honeycomb.io from within your ruby code.

[![Build Status](https://travis-ci.org/honeycombio/libhoney-rb.svg?branch=master)](https://travis-ci.org/honeycombio/libhoney-rb)

## Summary

libhoney is written to ease the process of sending data to Honeycomb from within
your ruby code.

For an overview of how to use a honeycomb library, see our documentation at
https://honeycomb.io/docs/send-data/sdks/

## Installation

To install the stable release:

```
gem install libhoney
```

If you're using bundler, you can also reference the git repo and stay on the bleeding age by putting this in your `Gemfile`:

```
gem 'libhoney', :git => 'http://github.com/honeycombio/libhoney-rb.git'
```

## Example Usage
```ruby
require 'libhoney'

# create a client instance
honey = Libhoney::Client.new(:writekey => "your writekey",
                             :dataset => "your dataset")

# create an event and add fields to it
event = honey.event
event.add_field("duration_ms", 153.12)
event.add_field("method", "get")
# send the event
event.send

# when all done, call close
honey.close
```

You can find a more complete example demonstrating usage in `example/fact.rb`

## Contributions

Features, bug fixes and other changes to libhoney are gladly accepted. Please
open issues or a pull request with your change. Remember to add your name to the
CONTRIBUTORS file!

All contributions will be released under the Apache License 2.0.

