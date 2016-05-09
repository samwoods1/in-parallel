# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative 'in_parallel/version'

Gem::Specification.new do |spec|
  spec.name          = "in-parallel"
  spec.version       = InParallel::VERSION
  spec.authors       = ["samwoods1"]
  spec.email         = ["sam.woods@puppetlabs.com"]

  spec.summary       = "A lightweight library to execute a handful of tasks in parallel with simple syntax"
  spec.description   = "I know there are other libraries that do parallelization, but I wanted something very " +
      "simple to consume, and this was fun. I plan on using this within a test framework to enable parallel " +
      "execution of some of the framework's tasks, and allow people within thier tests to execute code in " +
      "parallel when wanted. This solution does not check to see how many processors you have, it just forks " +
      "as many processes as you ask for. That means that it will handle a handful of parallel processes well, " +
      "but could definitely overload your system with ruby processes if you try to spin up a LOT of processes. " +
      "If you're looking for something simple and light-weight and on either linux or mac, then this solution " +
      "could be what you want. If you are looking for something a little more production ready, you should take " +
      "a look at the parallel project."
  spec.homepage      = "https://github.com/samwoods1/in-parallel"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
end
