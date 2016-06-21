require 'rspec'
require_relative('../lib/in_parallel')
include InParallel
TMP_FILE = '/tmp/test_file.txt'

class SingletonTest
  def initialize
    @test_data = [1, 2, 3]
  end
  def get_test_data
    @test_data
  end
end

def get_singleton_class
  test = SingletonTest.new
  def test.someval
    "someval"
  end
  return test
end

# Helper functions for the unit tests
def method_with_param(param)
  puts "foo"
  puts "bar + #{param} \n"
  return "bar + #{param}"
end

def method_without_param
  ret_val = {:foo => "bar"}
  puts ret_val
  return ret_val
end

def simple_puts(my_string)
  puts my_string
end

def create_file_with_delay(file_path, wait=1)
  sleep wait
  File.open(file_path, 'w') { |f| f.write('contents')}
  return true
end

def get_pid
  return Process.pid
end

def raise_an_error
  raise StandardError.new('An error occurred')
end

#Tests
describe '.run_in_parallel' do
  before do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
  end

  it 'should run methods in another process' do
    run_in_parallel{
      @result = get_pid
      @result2 = get_pid
    }

    expect(@result).to_not eq(Process.pid)
    expect(@result2).to_not eq(Process.pid)
    expect(@result).to_not eq(@result2)
  end
  it 'should return correct values' do
    start_time = Time.now

    run_in_parallel{
      @result_from_test = method_with_param('blah')
      @result_2 = method_without_param
    }
    # return values for instance variables should be set correctly
    expect(@result_from_test).to eq 'bar + blah'
    # should be able to return objects (not just strings)
    expect(@result_2).to eq({:foo => "bar"})
  end

  it "should return a singleton class value" do

    run_in_parallel{
      @result = get_singleton_class
    }

    expect(@result.get_test_data).to eq([1, 2, 3])
  end

  it "should raise an exception and return immediately with kill_all_on_error and one of the processes errors." do
    expect{run_in_parallel(nil, true){
      @result = get_singleton_class
      @result_2 = raise_an_error
      @result_3 = create_file_with_delay(TMP_FILE)
    }}.to raise_error StandardError

    expect(@result_3).to_not eq(true)
  end

  it "should raise an exception and let all processes complete when one of the processes errors." do
    expect{run_in_parallel(nil, false){
      @result = get_singleton_class
      @result_2 = raise_an_error
      @result_3 = create_file_with_delay(TMP_FILE)
    }}.to raise_error StandardError

    expect(@result_3).to eq(true)
  end

  it "should not run in parallel if forking is not supported" do
    expect(Process).to receive( :respond_to? ).with( :fork ).and_return( false ).once

    expect {run_in_parallel{
      @result_from_test = method_with_param('blah')
      @result_2 = get_pid
    }}.to output(/Warning: Fork is not supported on this OS, executing block normally/).to_stdout

    expect(@result_from_test).to eq 'bar + blah'
    expect(@result_2).to eq Process.pid
  end

  # it "should chunk stdout per process" do
  #   expect {run_in_parallel {
  #     simple_puts('foobar')
  #   }}.to output(/------ Begin output for simple_puts.*foobar.*------ Completed output for simple_puts/).to_stdout
  # end
end

describe '.run_in_background' do
  before do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
  end

  it 'should run in the background' do
    run_in_background{
      @result = create_file_with_delay(TMP_FILE)
    }

    # Should not exist immediately upon block completion
    expect(File.exists? TMP_FILE).to eq false
    sleep(2)
    # Should exist once the delay in create_file_with_delay is done
    expect(File.exists? TMP_FILE).to eq true
  end

  it 'should allow you to get results if ignore_results is false' do
    @block_result = run_in_background(false){
      @result = create_file_with_delay(TMP_FILE)
    }
    wait_for_processes
    # We should get the correct value assigned for the method result
    expect(@result).to eq true
  end

end

describe '.wait_for_processes' do
  after do
    puts "got to after"
    InParallel::InParallelExecutor.timeout = 1200
  end
  it 'should timeout when the default timeout value is hit' do
    @block_result = run_in_background(false){
      @result = create_file_with_delay(TMP_FILE, 30)
    }
    InParallel::InParallelExecutor.timeout = 0.1
    expect{wait_for_processes}.to raise_error RuntimeError
  end

  it 'should timeout when a specified timeout value is hit' do
    @block_result = run_in_background(false){
      @result = create_file_with_delay(TMP_FILE, 30)
      @result2 = method_without_param
    }
    expect{wait_for_processes(0.1)}.to raise_error RuntimeError
  end
end

describe '.each_in_parallel' do
  it 'should run each iteration in a separate process' do
    pids = [1,2,3].each_in_parallel {|item|
      Process.pid
    }
    expect(pids.detect{ |pid| pids.count(pid) > 1 }).to be_nil
  end

  it 'should return correct values' do
    start_time = Time.now
    items = ['foo', 'bar', 'baz'].each_in_parallel {|item|
      puts item
      item
    }
    # return values should be an array of the returned items in the last line of the block
    expect(items <=> ['foo', 'bar', 'baz']).to eq 0
    # time should be less than combined delay in the 3 block calls
    expect(expect(Time.now - start_time).to be < 3)
  end

  it 'should run each iteration of a map in parallel' do
    start_time = Time.now
    items = ['foo', 'bar', 'baz'].map.each_in_parallel {|item|
      puts item
      item
    }
    # return values should be an array of the returned items in the last line of the block
    expect(items <=> ['foo', 'bar', 'baz']).to eq 0
  end

  it 'should not run in parallel if there is only 1 item in the enumerator' do
    expect {["foo"].each_in_parallel{|item|
      puts item
    }}.to_not output(/forked process for/).to_stdout

  end

  it 'should allow you to specify the method_sym' do
    expect{[1,2,3].each_in_parallel('my_method'){|item|
      puts item
    }}.to output(/'each_in_parallel' forked process for 'my_method'/).to_stdout
  end

end
