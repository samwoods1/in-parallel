
A lightweight Ruby library with very simple syntax, making use of Process.fork to execute code in parallel.

# Use Cases
Many other Ruby libraries that simplify parallel execution support one primary use case - crunching through a large queue of small, similar tasks as quickly and efficiently as possible.  This library primarily supports the use case of executing a few larger and unrelated tasks in parallel, automatically managing the stdout and passing return values back to the main process. This library was created to be used by Puppet's Beaker test framework to enable parallel execution of some of the framework's tasks, and allow users to execute code in parallel within their tests.

If you are looking for something that excels at executing a large queue of tasks in parallel as efficiently as possible, you should take a look at the [parallel](https://github.com/grosser/parallel) project.

# Install
```gem install in-parallel```

# Usage
```include InParallel``` to use as a mix-in

The methods below allow you to fork processes to execute multiple methods or blocks within an enumerable in parallel.  They all have this common behavior:
1. STDOUT is captured for each forked process and logged all at once when the process completes or is terminated.
1. By default execution of processes in parallel will wait until execution of all processes are complete before continuing (with the exception of run_in_background).
    1. You can specify the parameter kill_all_on_error=true if you want to immediately exit all forked processes when an error executing any of the forked processes occurs.
1. When the forked process raises an exception or exits with a non zero exit code, an exception will be raised in the main process.
1. Terminating the main process with 'ctrl-c' or killing the process in some other way will immediately cause all forked processes to be killed and log their STDOUT up to that point.
1. If the result of the method or block can be marshalled, it will be returned as though it was executed within the same process.  If the result cannot be marshalled a warning is produced and the return value will be nil.
    1. NOTE: results of methods within run_in_parallel can be assigned to instance or class variables, but not local variables.  See examples below.
1. Will timeout (stop execution and raise an exception) based on a global timeout value, or timeout parameter.

## Methods
### run_in_parallel(timeout=nil, kill_all_on_error = false, &block)
1. Each method in a block will be executed in parallel (unless the method is defined in Kernel or BaseObject).
    1. Any methods further down the stack won't be affected, only the ones directly within the block.
1. Waits for each process in realtime and logs immediately upon completion of each process

```ruby
  def method_with_param(name)
    ret_val = "hello #{name} \n"
    puts ret_val
    ret_val
  end
  
  def method_without_param
    # A result more complex than a string will be marshalled and unmarshalled and work
    ret_val = {:foo => "bar"}
    puts ret_val
    return ret_val
  end

  # Example:
  # will spawn 2 processes, (1 for each method) wait until they both complete, log chunked STDOUT/STDERR for
  # each process and assign the method return values to instance variables:
  run_in_parallel do
    @result_1 = method_with_param('world')
    @result_2 = method_without_param
  end
  
  puts "#{@result_1}, #{@result_2[:foo]}"
```
stdout:
```
Forked process for 'method_with_param' - PID = '49398'
Forked process for 'method_without_param' - PID = '49399'

------ Begin output for method_with_param - 49398
hello world
------ Completed output for method_with_param - 49398

------ Begin output for method_without_param - 49399
{:foo=>"bar"}
------ Completed output for method_without_param - 49399
hello world, bar
```
### Enumerable.each_in_parallel(identifier=nil, timeout=(InParallel::InParallelExecutor.timeout), kill_all_on_error = false, &block)
1. This is very similar to other solutions, except that it directly extends the Enumerable class with an each_in_parallel method, giving you the ability to pretty simply spawn a process for any item in an array or map.
1. Identifies the block location (or caller location if the block does not have a source_location) in the console log to make it clear which block is being executed
1. Identifier param is only for logging, otherwise it will use the block source location.

```ruby
  ["foo", "bar", "baz"].each_in_parallel { |item| puts item }
```

### run_in_background(ignore_results = true, &block)
1. This does basically the same thing as run_in_parallel, except it does not wait for execution of all processes to complete, it returns immediately.
1. You can optionally ignore results completely (default) or delay evaluating the results until later
1. You can run multiple blocks in the background and then at some later point evaluate all of the results

```ruby
  TMP_FILE = '/tmp/test_file.txt'
  
  def create_file_with_delay(file_path)
    sleep 2
    File.open(file_path, 'w') { |f| f.write('contents') }
    return true
  end
  
  # Example 1 - ignore results
  run_in_background { create_file_with_delay(TMP_FILE) }
  
  # Should not exist immediately upon block completion
  puts(File.exists?(TMP_FILE)) # false
  sleep(3)
  # Should exist once the delay from create_file_with_delay is done
  puts(File.exists?(TMP_FILE)) # true
  ```
  ```ruby
  # Example 2 - delay results
  run_in_background(false) { @result = create_file_with_delay(TMP_FILE) }
  
  # Do something else
  
  run_in_background(false) { @result2 = create_file_with_delay('/tmp/someotherfile.txt') }
  
  # @result has not been assigned yet
  puts @result >> "unresolved_parallel_result_0"
  
  # This assigns all instance variables within the block and writes STDOUT and STDERR from the process to console.
  wait_for_processes
  puts @result # true
  puts @result2 # true
  
```

### wait_for_processes(timeout=nil, kill_all_on_error = false)
1. Used only after run_in_background with ignore_results=false
1. Optional args for timeout and kill_all_on_error
1. See run_in_background for examples

## Global Options
You can get or set the following values to set global defaults.  These defaults can also be specified per execution by supplying the values as parameters to the parallel methods.
```
  # How many seconds to wait between logging a 'Waiting for child processes.' message. Defaults to 30 seconds
  parallel_signal_interval

  # How many seconds to wait before timing out a forked child process and raising an exception. Defaults to 30 minutes.
  parallel_default_timeout

  # The log level to log output.
  # NOTE: The entire contents of STDOUT for forked processes will be printed to console regardless of
  # the log level set here.
  @logger.log_level
```

