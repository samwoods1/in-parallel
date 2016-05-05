# in-parallel
A lightweight Ruby library with very simple syntax, making use of process.fork for parallelization

I know there are other libraries that do parallelization, but I wanted something very simple to consume, and this was fun. I plan on using this within a test framework to enable parallel execution of some of the framework's tasks, and allow people within thier tests to execute code in parallel when wanted.  This solution does not check to see how many processors you have, it just forks as many processes as you ask for.  That means that it will handle a handful of parallel processes well, but could definitely overload your system with ruby processes if you try to spin up a LOT of processes.  If you're looking for something simple and light-weight and on either linux or mac, then this solution could be what you want.

If you are looking for something a little more production ready, you should take a look at the [parallel](https://github.com/grosser/parallel) project.

## Methods:

### InParallel.run_in_parallel(&block)
1. You can put whatever methods you want to execute in parallel into a block, and each method will be executed in parallel (unless the method is defined in kernel). 
  1. Any methods further down the stack won't be affected, only the ones directly within the block.  
2. You can assign the results to instance variables and it just works, no dealing with an array or map of results.
3. Log STDOUT and STDERR chunked per process to the console so that it is easy to see what happened in which process.

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
  # will spawn 2 processes, (1 for each method) wait until they both complete, 
  # and log chunked STDOUT/STDERR for each process:
  InParallel.run_in_parallel {
    @result_1 = method_with_param('world')
    @result_2 = method_without_param
  }
  
  puts "#{@result_1}, #{@result_2[:foo]}"
```
  
STDOUT would be:
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

### InParallel.run_in_background(ignore_results = true, &block)
1. This does basically the same thing as run_in_parallel, except it does not wait for execution of all processes to complete, it returns immediately.
2. You can optionally ignore results completely (default) or delay evaluating the results until later
3. You can run multiple blocks in the background and then at some later point evaluate all of the results

```ruby
  TMP_FILE = '/tmp/test_file.txt'
  
  def create_file_with_delay(file_path)
    sleep 2
    File.open(file_path, 'w') { |f| f.write('contents')}
    return true
  end
  
  # Example 1 - ignore results
  InParallel.run_in_background{
    create_file_with_delay(TMP_FILE)
  }
  
  # Should not exist immediately upon block completion
  puts(File.exists?(TMP_FILE)) # false
  sleep(3)
  # Should exist once the delay from create_file_with_delay is done
  puts(File.exists?(TMP_FILE)) # true
  
  # Example 2 - delay results
  InParallel.run_in_background(false){
    @result = create_file_with_delay(TMP_FILE)
  }
  
  # Do something else
  
  InParallel.run_in_background(false){
    @result2 = create_file_with_delay('/tmp/someotherfile.txt')
  }
  
  # @result has not been assigned yet
  puts @result >> "unresolved_parallel_result_0"
  
  # This assigns all instance variables within the block and writes STDOUT and STDERR from the process to console.
  InParallel.get_background_results
  puts @result # true
  puts @result2 # true
  
```

### Array.each_in_parallel(&block)
1. This is very similar to other solutions, except that it directly extends the Array class with an each_in_parallel method, giving you the ability to pretty simply spawn a process for any item in an array.
2. Identifies the block location (or caller location if the block does not have a source_location) in the console log to make it clear which block is being executed

```ruby
  ["foo", "bar", "baz"].each_in_parallel { |item|
    puts |item|
  }
  
```
STDOUT:
```
'each_in_parallel' spawned process for '/Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>'' - PID = '51600'
'each_in_parallel' spawned process for '/Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>'' - PID = '51601'
'each_in_parallel' spawned process for '/Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>'' - PID = '51602'

------ Begin output for /Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>' - 51600
foo
------ Completed output for /Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>' - 51600

------ Begin output for /Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>' - 51601
bar
------ Completed output for /Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>' - 51601

------ Begin output for /Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>' - 51602
baz
------ Completed output for /Users/samwoods/parallel_test/test/paralell_spec.rb:77:in `block (2 levels) in <top (required)>' - 51602
```
