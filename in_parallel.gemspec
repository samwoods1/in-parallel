# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'in-parallel/version'

Gem::Specification.new do |spec|
  spec.name          = "in-parallel"
  spec.version       = InParallel::VERSION
  spec.authors       = ["samwoods1"]
  spec.email         = ["sam.woods@puppetlabs.com"]
  spec.summary       = "A lightweight library to execute a handful of tasks in parallel with simple syntax"
  spec.description   = "Many other Ruby libraries that simplify parallel execution support one primary use case - " +
      "crunching through a large queue of small, similar tasks as quickly and efficiently as possible.  This library " +
      "primarily supports the use case of executing a few larger and unrelated tasks in parallel, automatically " +
      "managing the stdout and passing return values back to the main process. This library was created to be used " +
      "by Puppet's Beaker test framework to enable parallel execution of some of the framework's tasks, and allow " +
      "users to execute code in parallel within their tests."
  spec.homepage      = "https://github.com/puppetlabs/in-parallel"
  spec.license       = "MIT"

  spec.files         = Dir['[A-Z]*[^~]'] + Dir['lib/**/*.rb'] + Dir['spec/*']

end
