# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib', __FILE__)
require 'calabash-cucumber/version'

# ruby files
ruby_files = Dir.glob('lib/**/*.rb') + Dir.glob('bin/**/*.rb')

# additional files in bin
additional_bin_files = %w(bin/cal.xcconfig bin/CalabashSetup bin/calabash-ios)

# bin help file
bin_help = %w(doc/calabash-ios-help.txt)

# the calabash framework
staticlib = %w(staticlib/calabash.framework.zip staticlib/libFrankCalabash.a)

# calabash dylibs
dylibs = %w(dylibs/libCalabashDyn.dylib dylibs/libCalabashDynSim.dylib)

# files in script
scripts = %w(scripts/.irbrc scripts/launch.rb scripts/calabash.xcconfig.erb)

# files in script/data
scripts_data = Dir.glob('scripts/data/*.plist')

# pre-defined Steps
features = Dir.glob('features/**/*.rb')

# resources for the skeleton project generated by calabash-ios gen
features_skeleton = Dir.glob('features-skeleton/**/*.*')

# playback base64 files
playback = Dir.glob('lib/calabash-cucumber/resources/**/*.base64')

license = %w(LICENSE)

gem_files = ruby_files + additional_bin_files + bin_help + staticlib + scripts + scripts_data + features + features_skeleton + license + playback + dylibs

Gem::Specification.new do |s|
  s.name        = 'calabash-cucumber'
  s.version     = Calabash::Cucumber::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Karl Krukow']
  s.email       = ['karl@lesspainful.com']
  s.homepage    = 'http://calaba.sh'
  s.summary     = %q{Client for calabash-ios-server for automated functional testing on iOS}
  s.description = %q{calabash-cucumber drives tests for native iOS apps. You must link your app with calabash-ios-server framework to execute tests.}
  s.files         = gem_files
  s.test_files    = []
  s.executables   = %w(calabash-ios frank-calabash)
  s.require_paths = %w(lib)
  s.license       = 'EPL-1.0'

  s.required_ruby_version = '>= 1.9'

  s.add_dependency('cucumber', '~> 1.3.17')
  s.add_dependency('calabash-common', '~> 0.0.1')
  s.add_dependency('json', '~> 1.8')
  s.add_dependency('edn', '~> 1.0.6')
  s.add_dependency('CFPropertyList','~> 2.2.8')
  # Avoid 0.5 release because it does not contain ios-sim binary.
  s.add_dependency('sim_launcher', '~> 0.4.13')
  s.add_dependency('slowhandcuke', '~> 0.0.3')
  s.add_dependency('geocoder', '~>1.1.8')
  s.add_dependency('httpclient', '~> 2.3.3')
  # Match the xamarin-test-cloud dependency.
  s.add_dependency('bundler', '~> 1.3')
  s.add_dependency('awesome_print', '~> 1.2.0')
  s.add_dependency('run_loop', '~> 1.1.0')

  s.add_development_dependency 'rake', '~> 10.3'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'yard', '~> 0.8'
  s.add_development_dependency 'redcarpet', '~> 3.1'
  s.add_development_dependency 'pry', '~> 0.9'
  s.add_development_dependency 'pry-nav', '~> 0.2'
  s.add_development_dependency 'guard-rspec', '~> 4.3'
  s.add_development_dependency 'guard-bundler', '~> 2.0'
  s.add_development_dependency 'growl', '~> 1.0'
  s.add_development_dependency 'stub_env', '~> 0.2'
end
