require 'bundler'
require 'bundler/gem_tasks'

require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/plugin/test_*.rb']
  test.verbose = true
end

task :default => [:build]