require 'logger'
module InParallel
  module ParallelLogger
    def self.included(base)
      # Use existing logger if it is defined
      unless(base.instance_variables.include?(:@logger) && base.logger)
        logger = Logger.new(STDOUT)
        logger.send(:extend, self)
        base.instance_variable_set(:@logger, logger)
      end
    end
  end
end
