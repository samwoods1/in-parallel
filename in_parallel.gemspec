# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'in_parallel/version'

Gem::Specification.new do |spec|
  spec.name          = "in-parallel"
  spec.version       = InParallel::VERSION
  spec.authors       = ["samwoods1"]
  spec.email         = ["sam.woods@puppetlabs.com"]

  spec.summary       = "A lightweight library to execute a handful of tasks in parallel with simple syntax"
  spec.description   = "The other Ruby librarys that do parallel execution all support one primary use case " +
      "- crunching through a large queue of small tasks as quickly and efficiently as possible. This library " +
      "primarily supports the use case of needing to run a few larger tasks in parallel and managing the " +
      "stdout to make it easy to understand which processes are logging what. This library was created to be " +
      "used by the Beaker test framework to enable parallel execution of some of the framework's tasks, and " +
      "allow people within thier tests to execute code in parallel when wanted. This solution does not check " +
      "to see how many processors you have, it just forks as many processes as you ask for. That means that it " +
      "will handle a handful of parallel processes well, but could definitely overload your system with ruby " +
      "processes if you try to spin up a LOT of processes. If you're looking for something simple and " +
      "light-weight and on either linux or mac (forking processes is not supported on Windows), then this " +
      "solution could be what you want."
  spec.homepage      = "https://github.com/puppetlabs/in-parallel"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

end
