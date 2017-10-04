lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "libhoney/version"

Gem::Specification.new do |spec|
  spec.name        = 'libhoney'
  spec.version     = Libhoney::VERSION

  spec.summary     = "send data to Honeycomb"
  spec.description = "Ruby gem for sending data to Honeycomb"
  spec.authors     = ['The Honeycomb.io Team']
  spec.email       = 'support@honeycomb.io'
  spec.files       = ['lib/libhoney.rb', 'lib/libhoney/version.rb']
  spec.homepage    = 'https://github.com/honeycombio/libhoney-rb'
  spec.license     = 'Apache-2.0'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.2.0'

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "webmock", "~> 2.1"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "yardstick", "~> 0.9"
  spec.add_development_dependency "bump", "~> 0.5"
  spec.add_dependency "faraday", "~> 0.12"
  spec.add_dependency "faraday_middleware", "~> 0.12"
end
