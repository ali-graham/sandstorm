# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sandstorm/version'

Gem::Specification.new do |spec|
  spec.name          = 'sandstorm'
  spec.version       = Sandstorm::VERSION
  spec.authors       = ['Ali Graham']
  spec.email         = ['ali.graham@bulletproof.net']
  spec.description   = %q{ActiveModel-based ORM for Redis/InfluxDB}
  spec.summary       = %q{ActiveModel-based ORM for Redis/InfluxDB}
  spec.homepage      = 'https://github.com/flapjack/sandstorm'
  spec.license       = 'MIT'

  # see http://yehudakatz.com/2010/12/16/clarifying-the-roles-of-the-gemspec-and-gemfile/
  # following a middle road here, not shipping it with the gem :)
  spec.files         = `git ls-files`.split($\) - ['Gemfile.lock', 'gemfiles/Gemfile-ruby1.8.lock']

  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  required_ruby_version = '>= 1.9'
  spec.add_dependency 'activemodel'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'

  spec.requirements << "Redis and/or InfluxDB, and the related gems"
end
