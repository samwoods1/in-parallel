require_relative 'parallel_enumerable'
module InParallel
  class InParallelExecutor
    # How many seconds between outputting to stdout that we are waiting for child processes.
    # 0 or < 0 means no signaling.
    @@signal_interval = 30
    @@timeout = 1800
    @@process_infos = []
    def self.process_infos
      @@process_infos
    end

    @@background_objs = []
    @@result_id = 0

    @@pids = []

    @@main_pid = Process.pid

    def self.main_pid
      @@main_pid
    end

    def self.timeout
      @@timeout
    end

    def self.timeout=(value)
      @@timeout = value
    end

    # Example - will spawn 2 processes, (1 for each method) wait until they both complete, and log STDOUT:
    # InParallel.run_in_parallel {
    #   @result_1 = method1
    #   @result_2 = method2
    # }
    # NOTE: Only supports assigning instance variables within the block, not local variables
    def self.run_in_parallel(timeout = @@timeout, kill_all_on_error = false, &block)
      if Process.respond_to?(:fork)
        proxy = BlankBindingParallelProxy.new(block.binding)
        proxy.instance_eval(&block)
        return wait_for_processes(proxy, block.binding, timeout, kill_all_on_error)
      end
      puts 'Warning: Fork is not supported on this OS, executing block normally'
      block.call
    end

    # Example - Will spawn a process in the background to run puppet agent on two agents and return immediately:
    # Parallel.run_in_background {
    #   @result_1 = method1
    #   @result_2 = method2
    # }
    # # Do something else here before waiting for the process to complete
    #
    # # Optionally wait for the processes to complete before continuing.
    # # Otherwise use run_in_background(true) to clean up the process status and output immediately.
    # wait_for_processes(self)
    # NOTE: must call get_background_results to allow instance variables in calling object to be set,
    # otherwise @result_1 will evaluate to "unresolved_parallel_result_0"
    def self.run_in_background(ignore_result = true, &block)
      if Process.respond_to?(:fork)
        proxy = BlankBindingParallelProxy.new(block.binding)
        proxy.instance_eval(&block)

        if ignore_result
          Process.detach(@@process_infos.last[:pid])
          @@process_infos.pop
        else
          @@background_objs << {:proxy => proxy, :target => block.binding}
          return process_infos.last[:tmp_result]
        end
        return
      end
      puts 'Warning: Fork is not supported on this OS, executing block normally'
      result = block.call
      return nil if ignore_result
      result
    end

    # Waits for all processes to complete and logs STDOUT and STDERR in chunks from any processes
    # that were triggered from this Parallel class
    # @param [Object] proxy - The instance of the proxy class that the method was executed within
    # (probably only useful when called by run_in_background)
    # @param [Object] binding - The binding of the block to assign return values to instance variables
    # (probably only useful when called by run_in_background)
    # @param [Int] timeout Time in seconds to wait before giving up on a child process
    # @param [Boolean] kill_all_on_error Whether to wait for all processes to complete, or fail immediately -
    # killing all other forked processes - when one process errors.
    def self.wait_for_processes(proxy = self, binding = nil, timeout = nil, kill_all_on_error = false)
      raise_error = nil
      timeout ||= @@timeout
      trap(:INT) do
        puts "Warning, recieved interrupt.  Processing child results and exiting."
        kill_child_processes
      end
      return unless Process.respond_to?(:fork)
      # Custom process to wait so that we can do things like time out, and kill child processes if
      # one process returns with an error before the others complete.
      results_map = Array.new(@@process_infos.count)
      start_time = Time.now
      timer = start_time
      while !@@process_infos.empty? do
        if @@signal_interval > 0 && Time.now > timer + @@signal_interval
          puts 'Waiting for child processes.'
          timer = Time.now
        end
        if Time.now > start_time + timeout
          kill_child_processes
          raise_error = ::RuntimeError.new("Child process ran longer than timeout of #{timeout}")
        end
        @@process_infos.each {|process_info|
          # wait up to half a second for each thread to see if it is complete, if not, check the next thread.
          # returns immediately if the process has completed.
          thr = process_info[:wait_thread].join(0.5)
          unless thr.nil?
            # the process completed, get the result and rethrow on error.
            begin
              # Print the STDOUT and STDERR for each process with signals for start and end
              puts "\n------ Begin output for #{process_info[:method_sym]} - #{process_info[:pid]}\n"
              puts File.new(process_info[:std_out], 'r').readlines
              puts "------ Completed output for #{process_info[:method_sym]} - #{process_info[:pid]}\n"
              result = process_info[:result].read
              marshalled_result = (result.nil? || result.empty?) ? result : Marshal.load(result)
              if marshalled_result.is_a?(Exception)
                raise_error = marshalled_result.dup
                kill_child_processes if kill_all_on_error
                marshalled_result = nil
              end
              results_map[process_info[:index]] = {process_info[:tmp_result] => marshalled_result}
              File.delete(process_info[:std_out])
              # Kill all other processes and let them log their stdout before re-raising
              # if a child process raised an error.
            ensure
              # close the read end pipe
              process_info[:result].close unless process_info[:result].closed?
              @@process_infos.delete(process_info)
            end
          end
        }
      end

      results = []

      # pass in the 'self' from the block.binding which is the instance of the class
      # that contains the initial binding call.
      # This gives us access to the instance variables from that context.
      results = result_lookup(proxy, binding, results_map) if binding

      # If there are background_objs AND results, don't return the background obj results
      # (which would mess up expected results from each_in_parallel),
      # but do process their results in case they are assigned to instance variables
      @@background_objs.each {|obj|
         result_lookup(obj[:proxy], obj[:target], results_map)
      }
      @@background_objs.clear

      raise raise_error unless raise_error.nil?

      return results
    end

    # private method to execute some code in a separate process and store the STDOUT and STDERR for later retrieval
    def self._execute_in_parallel(method_sym, obj = self, &block)
      ret_val = nil
      # Communicate the return value of the method or block
      read_result, write_result = IO.pipe
      Dir.mkdir('tmp') unless Dir.exists? 'tmp'
      pid = fork do
        exit_status = 0
        trap(:INT) do
          puts("Warning: Interrupt received in child process; exiting #{Process.pid}")
          kill_child_processes
          return
        end
        write_file = File.new("tmp/parallel_process_#{Process.pid}", 'w')

        # IO buffer is 64kb, which isn't much... if debug logging is turned on,
        # this can be exceeded before a process completes.
        # Storing output in file rather than using IO.pipe
        STDOUT.reopen(write_file)
        STDERR.reopen(write_file)

        begin
          # close subprocess's copy of read_result since it only needs to write
          read_result.close
          ret_val = obj.instance_eval(&block)
          # Write the result to the write_result IO stream.
          # Have to serialize the value so it can be transmitted via IO
          if(!ret_val.nil? && ret_val.singleton_methods && ret_val.class != TrueClass && ret_val.class != FalseClass && ret_val.class != Fixnum)
            #in case there are other types that can't be duped
            begin
              ret_val = ret_val.dup
            rescue StandardError => err
              puts "Warning: return value from child process #{ret_val} " +
                       "could not be transferred to parent process: #{err.message}"
            end
          end
          # In case there are other types that can't be dumped
          begin
            Marshal.dump(ret_val, write_result) unless ret_val.nil?
          rescue StandardError => err
            puts "Warning: return value from child process #{ret_val} " +
                     "could not be transferred to parent process: #{err.message}"
          end
        rescue Exception => err
          puts "Error in process #{pid}: #{err.message}"
          # Return the error if an error is rescued so we can re-throw in the main process.
          Marshal.dump(err, write_result)
          exit_status = 1
        ensure
          write_result.close
          exit exit_status
        end
      end
      write_result.close
      # Process.detach returns a thread that will be nil if the process is still running and thr if not.
      # This allows us to check to see if processes have exited without having to call the blocking Process.wait functions.
      wait_thread = Process.detach(pid)
      # store the IO object with the STDOUT and waiting thread for each pid
      process_info = { :wait_thread => wait_thread,
                       :pid => pid,
                       :method_sym => method_sym,
                       :std_out => "tmp/parallel_process_#{pid}",
                       :result => read_result,
                       :tmp_result => "unresolved_parallel_result_#{@@result_id}",
                       :index => @@process_infos.count }
      @@process_infos.push(process_info)
      @@result_id += 1
      process_info
    end

    def self.kill_child_processes
      @@process_infos.each { |process_info|
        # Send INT to each child process so it returns and can print stdout and stderr to console before exiting.
        begin
          Process.kill("INT", process_info[:pid])
        rescue Errno::ESRCH
          # If one of the other processes has completed in the very short time before we try to kill it, handle the exception
        end
      }
    end
    private_class_method :kill_child_processes

    # Private method to lookup results from the results_map and replace the
    # temp values with actual return values
    def self.result_lookup(proxy_obj, target_obj, results_map)
      target_obj = eval('self', target_obj)
      proxy_obj ||= target_obj
      vars = (proxy_obj.instance_variables)
      results = []
      results_map.each { |tmp_result|
        results << tmp_result.values[0]
        vars.each {|var|
          if proxy_obj.instance_variable_get(var) == tmp_result.keys[0]
            target_obj.instance_variable_set(var, tmp_result.values[0])
            break
          end
        }
      }
      results
    end
    private_class_method :result_lookup

    # Proxy class used to wrap each method execution in a block and run it in parallel
    # A block from Parallel.run_in_parallel is executed with a binding of an instance of this class
    class BlankBindingParallelProxy < BasicObject
      # Don't worry about running methods like puts or other basic stuff in parallel
      include ::Kernel

      def initialize(obj)
        @object = obj
        @result_id = 0
      end

      # All methods within the block should show up as missing (unless defined in :Kernel)
      def method_missing(method_sym, *args, &block)
        if InParallelExecutor.main_pid == ::Process.pid
          out = InParallelExecutor._execute_in_parallel("'#{method_sym.to_s}' #{caller_locations[0].to_s}", @object.eval('self')) {send(method_sym, *args, &block)}
          puts "Forked process for '#{method_sym}' - PID = '#{out[:pid]}'\n"
          out[:tmp_result]
        end
      end
    end
  end

  # Executes each method within a block in a different process
  # Example - Will spawn a process in the background to execute each method
  # Parallel.run_in_parallel {
  #   @result_1 = method1
  #   @result_2 = method2
  # }
  # NOTE - Only instance variables can be assigned the return values of the methods within the block.
  # Local variables will not be assigned any values.
  # @param [Int] timeout Time in seconds to wait before giving up on a child process
  # @param [Boolean] kill_all_on_error Whether to wait for all processes to complete, or fail immediately -
  # killing all other forked processes - when one process errors.
  # @param [Block] block This method will yield to a block of code passed by the caller
  # @return [Array<Result>, Result] the return values of each method within the block
  def run_in_parallel(timeout=nil, kill_all_on_error = false, &block)
    timeout ||= InParallelExecutor.timeout
    InParallelExecutor.run_in_parallel(timeout, kill_all_on_error, &block)
  end

  # Forks a process for each method within a block and returns immediately
  # Example 1 - Will fork a process in the background to execute each method and return immediately:
  # Parallel.run_in_background {
  #   @result_1 = method1
  #   @result_2 = method2
  # }
  #
  # Example 2 - Will fork a process in the background to execute each method, return immediately, then later
  # wait for the process to complete, printing it's STDOUT and assigning return values to instance variables:
  # Parallel.run_in_background(false) {
  #   @result_1 = method1
  #   @result_2 = method2
  # }
  # # Do something else here before waiting for the process to complete
  #
  # wait_for_processes
  # NOTE: must call wait_for_processes to allow instance variables within the block to be set,
  # otherwise results will evaluate to "unresolved_parallel_result_X"
  # @param [Boolean] ignore_result True if you do not care about the STDOUT or return value of the methods executing in the background
  # @param [Block] block This method will yield to a block of code passed by the caller
  # @return [Array<Result>, Result] the return values of each method within the block
  def run_in_background(ignore_result = true, &block)
    InParallelExecutor.run_in_background(ignore_result, &block)
  end

  # Waits for all processes started by run_in_background to complete execution, then prints STDOUT
  # and assigns return values to instance variables.  See :run_in_background
  # @param [Int] timeout Time in seconds to wait before giving up on a child process
  # @param [Boolean] kill_all_on_error Whether to wait for all processes to complete, or fail immediately -
  # killing all other forked processes - when one process errors.
  # @return [Array<Result>, Result] the temporary return values of each method within the block
  def wait_for_processes(timeout=nil, kill_all_on_error = false)
    timeout ||= InParallelExecutor.timeout
    InParallelExecutor.wait_for_processes(nil, nil, timeout, kill_all_on_error)
  end
end
