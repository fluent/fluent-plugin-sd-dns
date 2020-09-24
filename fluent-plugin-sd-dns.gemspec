# encoding: utf-8
$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-sd-dns"
  gem.description = "DNS based service discovery plugin for Fluentd"
  gem.license     = "Apache-2.0"
  gem.homepage    = "https://github.com/fluent/fluent-plugin-sd-dns"
  gem.summary     = gem.description
  gem.version     = "0.1.0"
  gem.authors     = ["Masahiro Nakagawa"]
  gem.email       = "repeatedly@gmail.com"
  #gem.platform    = Gem::Platform::RUBY
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']

  gem.add_dependency "fluentd", ">= 1.8"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "flexmock", "~> 2.0"
  gem.add_development_dependency "rr", "~> 1.0"
  gem.add_development_dependency "test-unit", "~> 3.3"
  gem.add_development_dependency "test-unit-rr", "~> 1.0"
end
