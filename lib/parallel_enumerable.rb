# Extending Enumerable to make it easy to do any .each in parallel
module Enumerable
  # Executes each iteration of the block in parallel
  #
  # Example - Will execute each iteration in a separate process, in parallel, log STDOUT per process, and return an array of results.
  #   my_array = [1,2,3]
  #   my_array.each_in_parallel { |int|
  #     my_method(int)
  #   }
  # @param [String] identifier - Optional identifier for logging purposes only. Will use the block location by default.
  # @param [Int] timeout - Seconds to wait for a forked process to complete before timing out
  # @return [Array<Object>] results - the return value of each block execution.
  def each_in_parallel(identifier=nil, timeout=(InParallel::InParallelExecutor.parallel_default_timeout), kill_all_on_error = false, &block)
    if InParallel::InParallelExecutor.fork_supported? && count > 1
      identifier ||= "#{caller_locations[0]}"
      each do |item|
        out = InParallel::InParallelExecutor._execute_in_parallel(identifier) {block.call(item)}
      end
      # return the array of values, no need to look up from the map.
      return InParallel::InParallelExecutor.wait_for_processes(nil, block.binding, timeout, kill_all_on_error)
    end
    # If fork is not supported
    block.call
    each(&block)
  end
end
