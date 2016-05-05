require_relative 'array'

class InParallel
   @@supported = Process.respond_to?(:fork)
   @@outs = []
    def self.outs
      @@outs
    end

   @@background_objs = []
    @@result_id = 0

    # Example - will spawn 2 processes, (1 for each method) wait until they both complete, and log STDOUT:
    # InParallel.run_in_parallel {
    #   @result_1 = on agents[0], 'puppet agent -t'
    #   @result_2 = on agents[1], 'puppet agent -t'
    # }
    # NOTE: Only supports assigning instance variables within the block, not local variables
    def self.run_in_parallel(&block)
      if @@supported
        proxy = BlankBindingParallelProxy.new(self)
        proxy.instance_eval(&block)
        results_map = wait_for_processes
        # pass in the 'self' from the block.binding which is the instance of the class
        # that contains the initial binding call.
        # This gives us access to the local and instance variables from that context.
        return result_lookup(proxy, eval("self", block.binding), results_map)
      end
      puts 'Warning: Fork is not supported on this OS, executing block normally'
      block.call
    end

    # Private method to lookup results from the results_map and replace the
    # temp values with actual return values
    def self.result_lookup(proxy_obj, target_obj, results_map)
      vars = (proxy_obj.instance_variables)
      results_map.keys.each { |tmp_result|
        vars.each {|var|
          if proxy_obj.instance_variable_get(var) == tmp_result
            target_obj.instance_variable_set(var, results_map[tmp_result])
            break
          end
        }
      }

    end
    private_class_method :result_lookup

    # Example - Will spawn a process in the background to run puppet agent on two agents and return immediately:
    # Parallel.run_in_background {
    #   @result = on agents[0], 'puppet agent -t'
    #   @result_2 = on agents[1], 'puppet agent -t'
    # }
    # # Do something else here before waiting for the process to complete
    #
    # # Optionally wait for the processes to complete before continuing.
    # # Otherwise use run_in_background(true) to clean up the process status and output immediately.
    # Parrallel.get_background_results(self)
    # NOTE: must call get_background_results to allow instance variables in calling object to be set,
    # otherwise @result will evaluate to "unresolved_parallel_result_0"
    def self.run_in_background(ignore_result = true, &block)
      if @@supported
        proxy = BlankBindingParallelProxy.new(self)
        proxy.instance_eval(&block)

        if ignore_result
          Process.detach(@@outs.last[:pid])
          @@outs.pop
        else
          @@background_objs << {:proxy => proxy, :target => eval("self", block.binding)}
          return outs.last[:tmp_result]
        end
        return
      end
      puts 'Warning: Fork is not supported on this OS, executing block normally'
      result = block.call
      return nil if ignore_result
      result
    end

   def self.get_background_results
     results_map = wait_for_processes
     # pass in the 'self' from the block.binding which is the instance of the class
     # that contains the initial binding call.
     # This gives us access to the local and instance variables from that context.
     @@background_objs.each {|obj|
       return result_lookup(obj[:proxy], obj[:target], results_map)
     }
   end

    # Waits for all processes to complete and logs STDOUT and STDERR in chunks from any processes
    # that were triggered from this Parallel class
    def self.wait_for_processes
      return unless @@supported
      # Wait for all processes to complete
      statuses = Process.waitall

      results_map = {}
      # Print the STDOUT and STDERR for each process with signals for start and end
      while !@@outs.empty? do
        out = @@outs.shift
        begin
          puts "\n------ Begin output for #{out[:method_sym]} - #{out[:pid]}\n"
          puts out[:std_out].readlines
          puts "------ Completed output for #{out[:method_sym]} - #{out[:pid]}\n"
          results_map[out[:tmp_result]] = Marshal.load(out[:result].read)
        ensure
          # close the read end pipes
          out[:std_out].close unless out[:std_out].closed?
          out[:result].close unless out[:result].closed?
        end
      end

      statuses.each { |status|
        raise("Parallel process with PID '#{status[0]}' failed: #{status[1]}") unless status[1].success?
      }

      return results_map
    end

    # private method to execute some code in a separate process and store the STDOUT and STDERR for later retrieval
    def self._execute_in_parallel(method_sym, obj = self, &block)
      ret_val = nil
      # Communicate the return value of the method or block
      read_result, write_result = IO.pipe
      # Store the STDOUT and STDERR of the method or block
      read_io, write_io = IO.pipe
      pid = fork do
        STDOUT.reopen(write_io)
        STDERR.reopen(write_io)
        # Need to store this for the case of run_in_background in _execute
        @@result_writer = write_result
        begin
          # close subprocess's copy of read_io since it only needs to write
          read_io.close
          read_result.close
          ret_val = obj.instance_eval(&block)
          # Write the result to the write_result IO stream.
          # Have to serialize the value so it can be transmitted via IO
          Marshal.dump(ret_val, write_result)
        rescue SystemCallError => err
          puts "error: #{err.message}"
          write_io.write('.')
          exit 1
        ensure
          write_io.close
          write_result.close
        end
      end
      write_io.close
      write_result.close
      # store the IO object with the STDOUT for each pid
      out = { :pid => pid,
              :method_sym => method_sym,
              :std_out => read_io,
              :result => read_result,
              :tmp_result => "unresolved_parallel_result_#{@@result_id}" }
      @@outs.push(out)
      @@result_id += 1
      out
    end

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
          out = ::InParallel._execute_in_parallel(method_sym) {@object.send(method_sym, *args, &block)}
          puts "Forked process for '#{method_sym}' - PID = '#{out[:pid]}'\n"
          out[:tmp_result]
      end

    end
  end
